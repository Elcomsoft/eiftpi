#!/bin/bash
SCRIPTROOT=$(readlink -f $0 | rev | cut -d '/' -f2- | rev)
IMAGE_NAME=eiftpi_rpi3_rpi4.img

function assert () {
    err=$1
    echo "FATAL: $err"
    exit 1
}

echo "*** Install dependencies ***"
pacman --noconfirm -Sy  arch-install-scripts \
                        dosfstools \
                        nano \
                        wget \
                            || assert

echo "*** Create imagefile ***"
dd if=/dev/zero of=${IMAGE_NAME} bs=10M count=180 || assert
(
    echo "o"
    echo "n"
    echo "p"
    echo "1"
    echo ""
    echo "+160M"
    echo "t"
    echo "c"
    echo "n"
    echo "p"
    echo "2"
    echo ""
    echo ""
    echo "w"
) | fdisk ${IMAGE_NAME} || assert

export PART1_BLOCK_START=$(fdisk -lu ${IMAGE_NAME} | grep img1 | tr -s ' ' | cut -d ' ' -f2)
export PART1_BLOCK_NUM=$(fdisk -lu ${IMAGE_NAME} | grep img1 | tr -s ' ' | cut -d ' ' -f4)
export PART2_BLOCK_START=$(fdisk -lu ${IMAGE_NAME} | grep img2 | tr -s ' ' | cut -d ' ' -f2)
export PART2_BLOCK_NUM=$(fdisk -lu ${IMAGE_NAME} | grep img2 | tr -s ' ' | cut -d ' ' -f4)
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
    mount -o offset=$((512*${PART2_BLOCK_START} - ${LOOFFSET})) ${LODEV} ${dstpath} || assert
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
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --noconfirm -Sy arch-install-scripts pacman-contrib' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacstrap /mnt/ base' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist' || assert

echo "*** Remount image ***"
umount /mnt/mnt/boot || assert
umount /mnt/mnt || assert
umount /mnt || assert

mount_image "/mnt" || assert

## Install packages
arch-chroot /mnt/ /usr/bin/bash -c 'sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 20/g" /etc/pacman.conf' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --noconfirm -Suy' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --disable-download-timeout --noconfirm -S \
                                            linux-rpi \
                                            firmware-raspberrypi \
                                            raspberrypi-bootloader' || assert

${SCRIPTROOT}/configureimage.sh || assert

### Finialize ###
sync
umount /mnt/boot/ || assert
umount /mnt/ || assert

cp ${IMAGE_NAME} ${SCRIPTROOT}/
echo "*** DONE ***"
