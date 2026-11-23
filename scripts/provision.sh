#!/bin/sh
set -eu
umask 022
cd /build-settings
test "$(dpkg --print-architecture)" = armel
. /etc/os-release
test "$VERSION_CODENAME" = trixie
test -f /usr/sbin/sc-bootup.sh
# Read the two newly generated passwords before any package scripts run.
IFS= read -r sc_password
IFS= read -r root_password
test -n "$sc_password" && test -n "$root_password"

export DEBIAN_FRONTEND=noninteractive LC_ALL=C SYSTEMD_OFFLINE=1 UCF_FORCE_CONFFOLD=1
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 0755 /usr/sbin/policy-rc.d
printf 'Acquire::Languages "none";\n' > /etc/apt/apt.conf.d/99central-languages
# The base image has no CA bundle. APT verifies Debian's archive signatures throughout.
cat > /etc/apt/sources.list <<'SOURCES'
deb [arch=armel signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian trixie main
deb [arch=armel signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian trixie-updates main
deb [arch=armel signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://deb.debian.org/debian-security trixie-security main
SOURCES
find /var/lib/apt/lists -mindepth 1 -delete
apt-get -o APT::Update::Error-Mode=any -o Acquire::Retries=3 update
apt-get -y -o Acquire::Retries=3 -o Dpkg::Options::=--force-confold \
    --no-remove --no-install-recommends --with-new-pkgs upgrade
apt-get -y -o Acquire::Retries=3 -o Dpkg::Options::=--force-confold \
    --no-remove --no-install-recommends install \
    openssh-server openssh-sftp-server samba rsync smartmontools minidlna ca-certificates
test -s /etc/ssl/certs/ca-certificates.crt
sed -i 's|http://deb.debian.org/|https://deb.debian.org/|g' /etc/apt/sources.list
apt-get -o APT::Update::Error-Mode=any -o Acquire::Retries=3 update

install -m 0644 smb.conf /etc/samba/smb.conf
install -m 0644 minidlna.conf /etc/minidlna.conf
install -m 0644 central-data.service /etc/systemd/system/
install -m 0644 central-data.conf /usr/local/share/
for service in smbd minidlna; do
    install -d -m 0755 "/etc/systemd/system/$service.service.d"
    install -m 0644 data-dependency.conf "/etc/systemd/system/$service.service.d/central-data.conf"
done
usermod -aG sc minidlna
install -m 0644 central-maintenance.conf /etc/ssh/sshd_config.d/00-central.conf
printf '/dev/sda -a -n standby,q\n' > /etc/smartd.conf
printf 'sc:%s\nroot:%s\n' "$sc_password" "$root_password" | chpasswd
printf '%s\n%s\n' "$sc_password" "$sc_password" | smbpasswd -s -a sc
unset sc_password root_password
for service in nmbd rsync sc-statuspage sc-generate-status samba-ad-dc; do
    if systemctl --root=/ is-enabled "$service.service" >/dev/null 2>&1; then
        systemctl --root=/ disable "$service.service"
    fi
done
systemctl --root=/ enable ssh.service sshd-keygen.service smbd.service minidlna.service smartmontools.service
testparm -s /etc/samba/smb.conf >/dev/null
test -z "$(dpkg --audit)"
apt-get clean
