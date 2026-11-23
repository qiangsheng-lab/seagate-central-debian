# Seagate Central Debian NAS

为单盘 Seagate Central 4TB 构建可由希捷原厂管理页安装的 Debian 13 固件。基础镜像来自 bertofurth 的 v1.6.1，沿用其 4 KiB 页大小的 `6.1.69-sc` 内核。每次构建从 Debian 签名仓库更新 trixie 的 armel 软件包，并为这一份固件生成独立密码。[上游发布说明](https://github.com/bertofurth/Seagate-Central-Debian/releases/tag/v1.6.1)

| 服务 | 使用方式 |
| --- | --- |
| SSH / SFTP | 以 `sc` 登录，需要管理权限时执行 `su -` |
| Samba | 以 `sc` 连接 `smb://设备IP/NAS`，共享目录为 `/Data/Share` |
| rsync | 通过 SSH 备份到 `sc@设备IP:/Data/Share/` |
| ReadyMedia / DLNA | 电视在局域网选择 Seagate Central，媒体目录为 `/Data/Share/Media` |
| SMART | 内置 SATA 硬盘由 smartd 监控，可用 `smartctl -H -A /dev/sda` 查看 |

## 构建

在安装了 Bash、curl、OpenSSL 和 Docker 的电脑运行。Docker 需要能执行 `linux/arm/v5` 容器。构建过程在容器内操作普通文件，无需接入 NAS 硬盘。

```sh
git clone https://github.com/qiangsheng-lab/seagate-central-debian.git
cd seagate-central-debian
./build.sh
```

也可以复用已下载的上游原始镜像，并指定输出目录。两种方式都会核对 v1.6.1 发布文件的 SHA-256。

```sh
./build.sh /path/to/Debian-Trixie-Seagate-Central-4k-v1.6.1.img ./dist
```

构建结果位于脚本打印的 `central-…/` 目录，包括网页升级用的 `.img`、`SHA256SUMS` 和本机私有的 `initial-passwords.txt`。在该目录运行 `sha256sum -c SHA256SUMS`，macOS 可运行 `shasum -a 256 -c SHA256SUMS`。保管好与镜像配套的密码文件。

## 安装与数据卷

1. 确认原厂管理页显示 Seagate Central，记下 LAN 地址，备份需要保留的数据。全新未分区的硬盘需要另外准备启动分区。
2. 在原厂管理页进入 **Settings → Advanced → Firmware Update → Install From File**，选择构建得到的镜像。更新期间保持供电。
3. 等指示灯常绿后，从路由器确认 IP，使用 `ssh sc@设备IP` 登录。主机密钥在 NAS 上生成。用 `su -` 切换为 root。

先检查实机布局。

```sh
getconf PAGESIZE
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
lvs -o vg_name,lv_name,lv_size,devices
findmnt --mountpoint /Data
swapon --show
```

原厂 4 TB 布局通常将约 3.6 TiB 的数据卷放在 `sda8` 上，对应 `/dev/vg1/lv1`。用 `tune2fs -l /dev/vg1/lv1` 查看文件系统的 Block size。已使用 4096 字节块的 ext4 可以直接通过 `mount /Data` 挂载。

**原厂 64 KiB 块的 ext4 需要重建才能由此内核挂载。下面的格式化命令会清空整个逻辑卷。** 仅在实机确认目标逻辑卷、卷已卸载，且其中的数据已备份或可清除时执行。

```sh
mkfs.ext4 -b 4096 -m 0 -L Data /dev/vg1/lv1
mount /Data
```

若交换区没有启用，且已核实 `/dev/sda6` 是原厂未使用的 1 GiB 交换分区，可用 `mkswap -p 4096 /dev/sda6` 重建，再执行 `swapon /dev/sda6`。确认 `/Data` 已挂载后启动共享与媒体服务。

```sh
findmnt --mountpoint /Data
systemctl start smbd minidlna
systemctl is-active ssh smbd minidlna smartmontools
```

只有 `Media` 中的文件会通过 DLNA 提供给同一局域网的播放器。Linux 登录密码和 Samba 密码可以分别用 `passwd` 和 `smbpasswd` 修改。时区默认采用 `Asia/Shanghai`。

## 验证范围

构建脚本核对升级包内的内核与根文件系统摘要，并在 1 GiB ext4 测试分区写入完整系统及安装缓存，回读比对缓存并执行 `e2fsck`。此前的 Debian 13.8 镜像在 ARM11 MPCore 模拟环境中验证了 SSH 登录、SFTP/rsync/SMB3 文件回读、拒绝匿名共享访问，以及 DLNA 多播发现和取流。实机启动与 SATA 硬盘的 SMART 读取仍需在设备上验证。

上游提供了原厂备用系统的恢复步骤及基础镜像的构建方法。[恢复步骤](https://github.com/bertofurth/Seagate-Central-Debian#revert-to-original-firmware) · [上游构建说明](https://github.com/bertofurth/Seagate-Central-Debian/blob/v1.6.1/HOWTO-create-debian-image.md) · [上游许可](https://github.com/bertofurth/Seagate-Central-Debian/blob/v1.6.1/LICENSE)
