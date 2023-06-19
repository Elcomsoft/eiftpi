#!/bin/bash
SCRIPTROOT=$(readlink -f $0 | rev | cut -d '/' -f2- | rev)

function assert () {
    err=$1
    echo "FATAL: $err"
    exit 1
}

echo "*** Install dependencies ***"
pacman --noconfirm -Sy wget arch-install-scripts dosfstools pacman-contrib || assert

echo "*** Create imagefile ***"
dd if=/dev/zero of=eiftpi.img bs=100M count=18 || assert
(
    echo "o"
    echo "n"
    echo "p"
    echo "1"
    echo ""
    echo "+200M"
    echo "t"
    echo "c"
    echo "n"
    echo "p"
    echo "2"
    echo ""
    echo ""
    echo "w"
) | fdisk eiftpi.img || assert

export PART1_BLOCK_START=$(fdisk -lu eiftpi.img | grep img1 | tr -s ' ' | cut -d ' ' -f2)
export PART1_BLOCK_NUM=$(fdisk -lu eiftpi.img | grep img1 | tr -s ' ' | cut -d ' ' -f4)
export PART2_BLOCK_START=$(fdisk -lu eiftpi.img | grep img2 | tr -s ' ' | cut -d ' ' -f2)
export PART2_BLOCK_NUM=$(fdisk -lu eiftpi.img | grep img2 | tr -s ' ' | cut -d ' ' -f4)
echo "PART1_BLOCK_START=${PART1_BLOCK_START}"
echo "PART1_BLOCK_NUM=${PART1_BLOCK_NUM}"
echo "PART2_BLOCK_START=${PART2_BLOCK_START}"
echo "PART2_BLOCK_NUM=${PART2_BLOCK_NUM}"
mkfs.vfat -F32 -n PIBOOT --offset ${PART1_BLOCK_START} eiftpi.img ${PART1_BLOCK_NUM} || assert
mkfs.ext4 -L piroot -E offset=$((${PART2_BLOCK_START}*512)) eiftpi.img $((${PART2_BLOCK_NUM}/2)) || assert

function mount_image (){
    dstpath=$1
    mkdir -p /mnt1 || assert
    mount -o offset=$((512*${PART1_BLOCK_START})) eiftpi.img /mnt1 || assert
    LODEV=$(losetup -a | grep "eiftpi.img" | cut -d ':' -f1)
    LOOFFSET=$(losetup -a | grep "eiftpi.img" | rev | cut -d ' ' -f1 | rev)
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
wget http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz || assert
bsdtar -xpf ArchLinuxARM-rpi-aarch64-latest.tar.gz -C /mnt/ || assert

echo "*** Mount image in installer ***"
mount_image "/mnt/mnt" || assert

echo "*** Stage1: install base ***"
arch-chroot /mnt/ /usr/bin/bash -c 'sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 20/g" /etc/pacman.conf' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman-key --init' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman-key --populate archlinuxarm' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'sed "s/# Server/Server/g" /etc/pacman.d/mirrorlist > /etc/pacman.d/mirrorlist.backup' || assert
rankmirrors -n 6 /mnt/etc/pacman.d/mirrorlist.backup > /mnt/etc/pacman.d/mirrorlist || assert
arch-chroot /mnt/ /usr/bin/bash -c "pacman --noconfirm -Sy arch-install-scripts || sed -i 's/\[community\]/#\[community\]/g' /etc/pacman.conf" #Bug workaround??
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --noconfirm -Sy arch-install-scripts' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacstrap /mnt/ base' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist' || assert

echo "*** Remount image ***"
umount /mnt/mnt/boot || assert
umount /mnt/mnt || assert
umount /mnt || assert

mount_image "/mnt" || assert

### Chroot to the image ###
echo "*** Stage2: Install packages ***"

# Clean caches
arch-chroot /mnt/ /usr/bin/bash -c 'rm -f /var/cache/pacman/pkg/*' || assert

## Install packages
arch-chroot /mnt/ /usr/bin/bash -c 'sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 20/g" /etc/pacman.conf' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --noconfirm -Suy' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'pacman --disable-download-timeout --noconfirm -S \
                                                    sudo \
                                                    openssh \
                                                    nano \
                                                    networkmanager \
                                                    dnsmasq \
                                                    nftables \
                                                    linux-rpi \
                                                    raspberrypi-bootloader' || assert


echo "*** Configure image ***"
## Start services
arch-chroot /mnt/ /usr/bin/bash -c 'systemctl enable NetworkManager' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'systemctl enable sshd' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'systemctl enable dnsmasq' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'systemctl enable nftables' || assert

## Allow sudo to be used
arch-chroot /mnt/ /usr/bin/bash -c 'sed -i "s/# %sudo/%sudo/g" /etc/sudoers' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'groupadd sudo' || assert

## Add eift user
arch-chroot /mnt/ /usr/bin/bash -c 'useradd -G sudo -ms /bin/bash eift' || assert
arch-chroot /mnt/ /usr/bin/bash -c '(echo "Elcomsoft";echo "Elcomsoft") | passwd eift' || assert

## Don't lockout after 3 invalid login attempts
arch-chroot /mnt/ /usr/bin/bash -c 'echo "deny=0" >> /etc/security/faillock.conf' || assert

## Setup system
# Configure mounts based on labels (important because PI3/PI4 are different)
arch-chroot /mnt/ /usr/bin/bash -c 'echo -e "LABEL=piroot\t/\text4\trw,relatime\t0\t1" >> /etc/fstab' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'echo -e "LABEL=PIBOOT\t/boot\tvfat\trw,relatime,fmask=0022,dmask=0022,codepage=437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro\t0\t2" >> /etc/fstab' || assert

# Set hostname
arch-chroot /mnt/ /usr/bin/bash -c 'echo "EIFTPI" > /etc/hostname' || assert

# Configure locale
arch-chroot /mnt/ /usr/bin/bash -c 'echo "en_US.UTF-8 UTF-8" > /etc/locale.gen' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'echo "LANG=en_US.UTF-8" > /etc/locale.conf' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'locale-gen' || assert

# Allow IPv4 forwarding
arch-chroot /mnt/ /usr/bin/bash -c 'echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-routing.conf' || assert

# Add ld search path
arch-chroot /mnt/ /usr/bin/bash -c 'echo "/usr/local/lib" >> /etc/ld.so.conf' || assert

# Copy config files to the image
cp -a ${SCRIPTROOT}/rootfs locrootfs
chown -R 0:0 locrootfs
cp -a locrootfs/* /mnt/ || assert

# Fixup permissions
arch-chroot /mnt/ /usr/bin/bash -c 'chmod 600 /etc/NetworkManager/system-connections/phoneport.nmconnection' || assert

## Cleanup
echo "*** Cleanup image ***"
# Clean caches
arch-chroot /mnt/ /usr/bin/bash -c 'rm -f /var/cache/pacman/pkg/*' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'rm -f /var/lib/pacman/sync/*' || assert

# Clean unneeded files
arch-chroot /mnt/ /usr/bin/bash -c 'rm -rf /usr/include' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'rm -rf /usr/share/man' || assert
arch-chroot /mnt/ /usr/bin/bash -c 'rm -rf /usr/share/doc' || assert


### Shrink image even more ###
echo "*** Shrink image ***"
e4defrag /mnt
umount /mnt/boot/ || assert
umount /mnt/ || assert
losetup -o $(($PART2_BLOCK_START*512)) -f eiftpi.img || assert
export ROOTFS_BDEV=$(losetup -a | grep "eiftpi.img" | cut -d ':' -f1)
echo "ROOTFS_BDEV=${ROOTFS_BDEV}"
e2fsck -f ${ROOTFS_BDEV} || assert
resize2fs -M ${ROOTFS_BDEV}
resize2fs -M ${ROOTFS_BDEV}
resize2fs -M ${ROOTFS_BDEV}
resize2fs -M ${ROOTFS_BDEV}
export MINIMAL_SIZE=$(resize2fs -M ${ROOTFS_BDEV} 2>&1 | grep -oE "already [0-9]+ " | grep -oE "[0-9]+")
export NEW_SIZE=$((${MINIMAL_SIZE} + 0))
echo "MINIMAL_SIZE=${MINIMAL_SIZE}"
echo "NEW_SIZE=${NEW_SIZE}"
resize2fs ${ROOTFS_BDEV} ${NEW_SIZE} || assert
e2fsck -f ${ROOTFS_BDEV} || assert
losetup -d ${ROOTFS_BDEV} || assert
(
    echo "d"
    echo "2"
    echo "n"
    echo "p"
    echo "2"
    echo ""
    echo "+$((${NEW_SIZE} * 8 - 1))"
    echo "n"
    echo "w"
) | fdisk eiftpi.img || assert
export PART2_BLOCK_END=$(fdisk -lu eiftpi.img | grep img2 | tr -s ' ' | cut -d ' ' -f3)
export NEW_IMAGE_SIZE=$(( (${PART2_BLOCK_END} + 1 ) * 512 ))
echo "PART2_BLOCK_END=${PART2_BLOCK_END}"
echo "NEW_IMAGE_SIZE=${NEW_IMAGE_SIZE}"
truncate -s ${NEW_IMAGE_SIZE} eiftpi.img || assert
mv eiftpi.img ${SCRIPTROOT}/
echo "*** DONE ***"
