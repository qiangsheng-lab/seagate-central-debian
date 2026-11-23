#!/bin/sh
set -eu
cd /build
truncate -s 1G root-slot.ext4
mke2fs -q -F -t ext4 -b 4096 -m 5 -O none,has_journal,ext_attr,resize_inode,dir_index,filetype,extent,flex_bg,sparse_super,large_file,huge_file,uninit_bg,dir_nlink,extra_isize -d assembled root-slot.ext4
debugfs -w -R 'write /build/custom/rfs.squashfs /rfs.squashfs' root-slot.ext4 >/build/slot-copy.log 2>&1
debugfs -R 'dump /rfs.squashfs /build/slot-extracted.squashfs' root-slot.ext4 >/dev/null
cmp custom/rfs.squashfs slot-extracted.squashfs
e2fsck -fn root-slot.ext4 > /build/e2fsck.log
dumpe2fs -h root-slot.ext4 2>/dev/null | awk -F: '/^Free blocks:/ {free=$2} /^Reserved block count:/ {reserve=$2} /^Block size:/ {size=$2} END {printf "Free above ext4 reserve, including cached installer: %.1f MiB\n",(free-reserve)*size/1048576; if (free<=reserve) exit 1}'
tail -1 /build/e2fsck.log
