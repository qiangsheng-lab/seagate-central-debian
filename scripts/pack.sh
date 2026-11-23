#!/bin/sh
set -eu
umask 022
cd /build
tree=/build/assembled
release=/build/custom
mkdir -p "$release"

# The container runtime supplies its own /dev and network identity while building.
# Restore the boot-time device nodes and the NAS network identity from the checked base.
rm -rf "$tree/dev"
cp -a root/dev "$tree/dev"
cp -a root/etc/hostname root/etc/hosts "$tree/etc/"
printf '# Updated by the DHCP client on eth0.\n' > "$tree/etc/resolv.conf"
rm -f "$tree/.dockerenv" "$tree/run/.containerenv" "$tree/usr/sbin/policy-rc.d"
rm -rf "$tree/build-settings"
find "$tree/tmp" -mindepth 1 -delete
find "$tree/run" -mindepth 1 -delete
find "$tree/var/log" -type f -exec truncate -s 0 {} +
find "$tree/var/lib/apt/lists" -mindepth 1 -delete
find "$tree/var/cache/apt" -maxdepth 1 -type f -delete
find "$tree/var/cache/apt/archives" -type f -name '*.deb' -delete
rm -f "$tree"/etc/ssh/ssh_host_*_key "$tree"/etc/ssh/ssh_host_*_key.pub
rm -f "$tree/var/lib/systemd/random-seed" "$tree/var/lib/dbus/machine-id"
rm -f "$tree/root/.bash_history" "$tree/home/sc/.bash_history"
rm -f "$tree"/var/lib/dhcp/*.leases "$tree"/var/lib/dhcp/*.leases~
# An empty ID lets systemd assign a per-device ID without re-presetting configured services.
: > "$tree/etc/machine-id"
install -d -m 0755 "$tree/etc/systemd/system/sshd-keygen.service.d"
cat > "$tree/etc/systemd/system/sshd-keygen.service.d/central.conf" <<'UNIT'
[Unit]
ConditionFirstBoot=
ConditionPathIsReadWrite=/etc/ssh
ConditionPathIsSymbolicLink=!/etc/ssh
UNIT
test -e "$tree/usr/share/zoneinfo/Asia/Shanghai"
ln -sfn /usr/share/zoneinfo/Asia/Shanghai "$tree/etc/localtime"
printf 'Asia/Shanghai\n' > "$tree/etc/timezone"
chmod 0444 "$tree/etc/machine-id"
if test -d "$tree/var/lib/dbus"; then ln -s /etc/machine-id "$tree/var/lib/dbus/machine-id"; fi
test -f "$tree/var/lib/samba/private/passdb.tdb"
test -L "$tree/etc/systemd/system/ssh.service.wants/sshd-keygen.service"
test -f "$tree/usr/sbin/smbd"
test -f "$tree/usr/sbin/minidlnad"
test -f "$tree/usr/sbin/smartd"
test -z "$(find "$tree/Data" -mindepth 1 -print -quit)"
test -z "$(find "$tree/root" "$tree/home" -name authorized_keys -type f -size +0c -print -quit)"
test -z "$(find "$tree/etc/ssh" -name 'ssh_host_*_key' -print -quit)"
chmod --reference=root "$tree"
chmod 0644 "$tree/etc/apt/apt.conf.d/99central-languages"
chmod 0700 "$tree/var/lib/samba/private"
for dir in var/lib/apt/lists var/cache/apt/archives; do
    chown --reference="root/$dir" "$tree/$dir"
    chmod --reference="root/$dir" "$tree/$dir"
done
if [ -d "$tree/var/cache/debconf/tmp.ci" ]; then rmdir "$tree/var/cache/debconf/tmp.ci"; fi
if [ ! -L "$tree/var/lock" ] && [ -L root/var/lock ]; then
    rmdir "$tree/var/lock"
    cp -a root/var/lock "$tree/var/lock"
fi
writable=$(find "$tree" -xdev \( -type f -o -type d \) -perm -0002 ! -perm -1000 -print -quit)
test -z "$writable" || { echo "Unexpected writable path: $writable"; exit 1; }
du -shx "$tree"
mksquashfs "$tree" "$release/rfs.squashfs" -noappend -comp gzip -b 131072 -Xcompression-level 1 -processors 3 -no-progress > /build/compression.log
cp -a uImage "$release/uImage"
sum=$(md5sum "$release/rfs.squashfs")
version=$(date -u +%Y.%m%d.%H%M%S-SCD)
stamp=$(date -u +%d-%m-%Y)
sed -e "s/^version=.*/version=$version/" -e "s/^release_date=.*/release_date=$stamp/" -e "s/^rfs=.*/rfs=${sum%% *}/" config.ser > "$release/config.ser"
cd "$release"
tar --format=ustar --owner=0 --group=0 -czf /build/Seagate-Central-Debian13-NAS-4k.img rfs.squashfs uImage config.ser
cmp uImage /build/uImage
for item in kernel:uImage rfs:rfs.squashfs; do
    value=$(sed -n "s/^${item%:*}=//p" config.ser)
    printf '%s  %s\n' "$value" "${item#*:}" | md5sum -c -
done
sha256sum /build/Seagate-Central-Debian13-NAS-4k.img
