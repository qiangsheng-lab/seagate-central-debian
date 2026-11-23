#!/bin/sh
set -eu
umask 022
cd /build
printf '%s  base.img\n' f14bb8c19e22e909dfc92d380c536480ec2c34b2385e2fd550e618a5e184fb56 | sha256sum -c -
tar -xzf base.img rfs.squashfs uImage config.ser
grep -qx 'device=cirrus_v1' config.ser
for pair in kernel:uImage rfs:rfs.squashfs; do
    digest=$(sed -n "s/^${pair%:*}=//p" config.ser)
    printf '%s  %s\n' "$digest" "${pair#*:}" | md5sum -c -
done
unsquashfs -no-progress -processors 3 -d root rfs.squashfs
