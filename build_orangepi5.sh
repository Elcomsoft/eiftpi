#!/bin/bash
SCRIPTROOT=$(readlink -f $0 | rev | cut -d '/' -f2- | rev)
IMAGE_NAME=eiftpi_orangepi5.img
function assert () {
    err=$1
    echo "FATAL: $err"
    exit 1
}

echo "*** Install dependencies ***"
pacman --noconfirm -Sy  aarch64-linux-gnu-gcc \
                        arch-install-scripts \
                        bc \
                        bison \
                        diffutils \
                        docbook-xsl \
                        dosfstools \
                        dtc \
                        fakeroot \
                        flex \
                        gcc \
                        gdisk \
                        git \
                        inetutils \
                        make \
                        nano \
                        patch \
                        python3 \
                        python-pyelftools \
                        python-setuptools \
                        swig \
                        uboot-tools \
                        wget \
                        which \
                        xmlto \
                            || assert

echo "*** Create imagefile ***"
dd if=/dev/zero of=${IMAGE_NAME} bs=10M count=180 || assert
sgdisk -n 1:32768:+160M ${IMAGE_NAME}      || assert
sgdisk -t 1:ea00 ${IMAGE_NAME}       || assert
sgdisk -n 2 ${IMAGE_NAME}            || assert
sgdisk -t 2:8300 ${IMAGE_NAME}       || assert


export PART1_BLOCK_START=$(sgdisk -p ${IMAGE_NAME} | grep EA00 | tr -s ' ' | cut -d ' ' -f3)
export PART1_BLOCK_END=$(sgdisk -p ${IMAGE_NAME} | grep EA00 | tr -s ' ' | cut -d ' ' -f4)
export PART1_BLOCK_NUM=$((${PART1_BLOCK_END} - ${PART1_BLOCK_START}))
export PART2_BLOCK_START=$(sgdisk -p ${IMAGE_NAME} | grep 8300 | tr -s ' ' | cut -d ' ' -f3)
export PART2_BLOCK_END=$(sgdisk -p ${IMAGE_NAME} | grep 8300 | tr -s ' ' | cut -d ' ' -f4)
export PART2_BLOCK_NUM=$((${PART2_BLOCK_END} - ${PART2_BLOCK_START}))
echo "PART1_BLOCK_START=${PART1_BLOCK_START}"
echo "PART1_BLOCK_NUM=${PART1_BLOCK_NUM}"
echo "PART2_BLOCK_START=${PART2_BLOCK_START}"
echo "PART2_BLOCK_NUM=${PART2_BLOCK_NUM}"
mkfs.vfat -F32 -n PIBOOT -s 1 -S 512 --offset ${PART1_BLOCK_START} ${IMAGE_NAME} $((${PART1_BLOCK_NUM}/2)) || assert
mkfs.ext4 -L piroot -E offset=$((${PART2_BLOCK_START}*512)) ${IMAGE_NAME} $((${PART2_BLOCK_NUM}/2)) || assert

function mount_image (){
    dstpath=$1
    mkdir -p /mnt1 || assert
    mount -o offset=$((512*${PART1_BLOCK_START})) ${IMAGE_NAME} /mnt1 || assert
    LODEV=$(losetup -a | grep "/${IMAGE_NAME}" | cut -d ':' -f1)
    LOOFFSET=$(losetup -a | grep "/${IMAGE_NAME}" | rev | cut -d ' ' -f1 | rev)
    echo "LODEV=${LODEV}"
    echo "LOOFFSET=${LOOFFSET}"
    mount -o offset=$((512*${PART2_BLOCK_START}-${LOOFFSET})) ${LODEV} ${dstpath} || assert
    umount /mnt1 || assert
    rmdir /mnt1 || assert
    mkdir -p "${dstpath}/boot" || assert
    mount ${LODEV} "${dstpath}/boot" || assert
    echo "mount_image OK"
}

echo "*** Prepare installer ***"
mount -t tmpfs -s 2G /mnt || assert
wget -c http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz || assert
bsdtar -xpf ArchLinuxARM-rpi-aarch64-latest.tar.gz -C /mnt/ || assert

echo "*** Mount image in installer ***"
mount_image "/mnt/mnt" || assert

echo "*** Stage1: install base ***"
arch-chroot /mnt/ /usr/bin/bash -c 'sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 20/g" /etc/pacman.conf' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman-key --init' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman-key --populate archlinuxarm' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --noconfirm -Sy \
                                        arch-install-scripts \
                                        bc \
                                        bison \
                                        dtc \
                                        flex \
                                        gcc \
                                        git \
                                        make \
                                        openssl \
                                        pacman-contrib \
                                        patch \
                                        uboot-tools' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacstrap /mnt/ base' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist' || assert

echo "*** OrangePI: Compile kernel ***"
git clone https://gitlab.manjaro.org/manjaro-arm/packages/core/linux-rk3588.git || assert
useradd builder
chmod -R 777 linux-rk3588 || assert
wget https://raw.githubusercontent.com/mydatakeeper/drone-aarch64-makepkg/master/aarch64-makepkg.conf -O /etc/aarch64-makepkg.conf
wget https://raw.githubusercontent.com/mydatakeeper/drone-aarch64-makepkg/master/aarch64-makepkg -O /usr/bin/aarch64-makepkg
chmod +x /usr/bin/aarch64-makepkg
oldhash=$(md5sum /linux-rk3588/config | cut -d ' ' -f1)
cp /build/orangepi5/config /linux-rk3588/config
newhash=$(md5sum /linux-rk3588/config | cut -d ' ' -f1)
sed -i "s/${oldhash}/${newhash}/g" /linux-rk3588/PKGBUILD
bash -c 'cd linux-rk3588; su -c aarch64-makepkg builder' || assert
cp linux-rk3588/linux*.pkg* / || assert


echo "*** Remount image ***"
umount /mnt/mnt/boot || assert
umount /mnt/mnt || assert
umount /mnt || assert

mount_image "/mnt" || assert

## Install packages
arch-chroot /mnt/ /usr/bin/bash -c 'sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 20/g" /etc/pacman.conf' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --noconfirm -Suy' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --disable-download-timeout --noconfirm -S \
                                            fbset \
                                            linux-firmware \
                                            initramfs' || assert

${SCRIPTROOT}/configureimage.sh || assert

echo "*** OrangePI: Install kernel ***"
cp /linux*.pkg* /mnt/var/cache/pacman/pkg/
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --noconfirm -U /var/cache/pacman/pkg/linux*pkg.tar.xz' || assert

echo "*** OrangePI: Install files ***"
rm -f  /mnt/boot/initramfs-linux-fallback.img
rm -f  /mnt/boot/Image.gz
cp -RP /build/orangepi5/boot/* /mnt/boot/ || assert
cp /build/orangepi5/u-boot.bin /u-boot-orangepi.bin || assert
mkimage -A arm64 -O linux -T script -C none -n "U-Boot boot script" -d /mnt/boot/boot.cmd /mnt/boot/boot.scr
mkimage -A arm64 -T ramdisk -C gzip -a 0 -e 0 -d /mnt/boot/initramfs-linux.img /mnt/boot/uInitrd

## Cleanup
echo "*** Cleanup image ***"
# Clean caches
arch-chroot /mnt/ /usr/bin/bash -c 'rm -f /var/cache/pacman/pkg/*' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'rm -f /var/lib/pacman/sync/*' || assert

# Clean unneeded files
arch-chroot /mnt/ /usr/bin/bash -c 'rm -rf /usr/include' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'rm -rf /usr/share/man' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'rm -rf /usr/share/doc' || assert

### Finialize ###
sync
umount /mnt/boot/ || assert
umount /mnt/ || assert

dd if=/u-boot-orangepi.bin of=${IMAGE_NAME} bs=$((0x200)) seek=$((0x40)) conv=notrunc || assert
cp ${IMAGE_NAME} ${SCRIPTROOT}/
echo "*** DONE ***"
