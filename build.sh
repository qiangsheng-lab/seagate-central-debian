#!/usr/bin/env bash
set -euo pipefail
umask 077
project=$(cd "$(dirname "$0")" && pwd)
if [[ ${1:-} == --help || $# -gt 2 ]]; then
    echo "Usage: ./build.sh [upstream-v1.6.1.img] [output-directory]"
    [[ $# -le 2 ]] && exit 0
    exit 2
fi
output_root=${2:-"$project/dist"}
mkdir -p "$output_root"
out=$(mktemp -d "$output_root/central-XXXXXXXX")
helper= target= imported= complete=0
cleanup() {
    [[ -z $target ]] || docker rm -f "$target" >/dev/null || true
    [[ -z $helper ]] || docker rm -f "$helper" >/dev/null || true
    [[ -z $imported ]] || docker image rm "$imported" >/dev/null || true
    if [[ $complete == 0 ]]; then rm -rf -- "$out"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

base=${1:-}
if [[ -z $base ]]; then
    base="$out/base.img"
    curl -fL --retry 3 -o "$base" \
        https://github.com/bertofurth/Seagate-Central-Debian/releases/download/v1.6.1/Debian-Trixie-Seagate-Central-4k-v1.6.1.img
fi
[[ -f $base ]] || { echo "Missing input image: $base" >&2; exit 1; }

helper_image=$(docker build -q "$project")
helper=$(docker run -d --network none "$helper_image" sleep infinity)
docker cp "$base" "$helper:/build/base.img"
docker exec "$helper" /recipe/unpack.sh
if [[ $# -eq 0 || -z ${1:-} ]]; then rm -- "$base"; fi

# Import a uniquely tagged build image so concurrent builds can clean up independently.
tag="seagate-central-build:$(openssl rand -hex 12)"
docker exec "$helper" tar --numeric-owner --xattrs --xattrs-include='*' -C /build/root -cpf - . \
    | docker import --platform linux/arm/v5 - "$tag" >/dev/null
imported=$tag
target=$(docker run -d --platform linux/arm/v5 "$imported" /bin/sleep infinity)
docker exec "$target" mkdir -p /build-settings
docker cp "$project/settings/." "$target:/build-settings/"
docker cp "$project/scripts/provision.sh" "$target:/build-settings/provision.sh"
sc_password=$(openssl rand -hex 24)
root_password=$(openssl rand -hex 24)
printf '%s\n%s\n' "$sc_password" "$root_password" | docker exec -i "$target" /build-settings/provision.sh

docker exec "$helper" mkdir -p /build/assembled
docker export "$target" | docker exec -i "$helper" tar --numeric-owner --xattrs --xattrs-include='*' -xpf - -C /build/assembled
docker exec "$helper" /recipe/pack.sh
docker exec "$helper" /recipe/check-space.sh

image=Seagate-Central-Debian13-NAS-4k.img
docker cp "$helper:/build/$image" "$out/$image"
docker exec -w /build "$helper" sha256sum "$image" > "$out/SHA256SUMS"
printf 'sc (SSH, SFTP, rsync, SMB): %s\nroot (su -): %s\n' "$sc_password" "$root_password" > "$out/initial-passwords.txt"
complete=1
printf 'Firmware, SHA256SUMS and initial passwords: %s\n' "$out"
