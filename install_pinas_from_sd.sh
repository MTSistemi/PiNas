#!/bin/bash
# Autor: Mattia Tadini
# File: Install_PiNas_From_SD.sh
# Revision: 1.00
# Date 2020/11/17
# Configure RaspBerry Pi 4 for boot from USB Disks with two 8 GB partitions to work as RAID1 with BTRFS
# 
# Prerequisites:
# 1. SD Card With RaspiOS Buster armhf lite relased after 2020/08/20
# https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2020-08-24/2020-08-20-raspios-buster-armhf-lite.zip
#


#Install Prerequisites
echo "I Need To Update Repository And Install Packages..."
apt update
apt-get -qq install mdadm btrfs-tools duperemove rsync 
wget -O /root/watch.sh https://raw.githubusercontent.com/MTSistemi/PiNas/main/watch.sh
#Set Variable For Disks, Partitions And Arrays
SD_CARD=/dev/mmcblk0
SD_BOOT_PARTITION=${SD_CARD}p1
SD_ROOT_PARTITION=${SD_CARD}p2
SD_DATA_PARTITION=${SD_CARD}p3
FIRST_DISK=/dev/sda
FIRST_BOOT_PARTITION=${FIRST_DISK}1
FIRST_ROOT_PARTITION=${FIRST_DISK}2
FIRST_DATA_PARTITION=${FIRST_DISK}3
SECOND_DISK=/dev/sdb
SECOND_BOOT_PARTITION=${SECOND_DISK}1
SECOND_ROOT_PARTITION=${SECOND_DISK}2
SECOND_DATA_PARTITION=${SECOND_DISK}3
ARRAY=/dev/md
# BOOT cannot be RAIDed
ROOT_ARRAY=${ARRAY}0
DATA_ARRAY=${ARRAY}1

echo "Are We Root?"
[[ $EUID -eq 0 ]]
echo "OK"
echo
echo "Are We Running On The PiNas?"
[[ "$(uname --machine)" == arm* ]]
echo "OK"
echo
echo "Are We Running From The SD Card $SD_ROOT_PARTITION?"
df --exclude=tmpfs | awk -v PATTERN="$SD_ROOT_PARTITION" '$7 == "/" { if($1 != PATTERN) exit 1 }'
# --exclude-type to shorten list
# -v to pass SD_ROOT_PARTITION from bash into awk script
# $7 == "/" find the root partition and if it is not mounted to SD_ROOT_PARTITION exit with error
echo "OK"
echo
echo "Is Disk $FIRST_DISK plugged in?"
[[ -e "$FIRST_DISK" ]]
echo "OK"
echo
echo "Is Disk $SECOND_DISK plugged in?"
[[ -e "$SECOND_DISK" ]]
echo "OK"
echo
echo
echo "Now Destroy All Data On Disks $FIRST_DISK And $SECOND_DISK"
rm -f /etc/mdadm/mdadm.conf
partprobe -s
sleep 5
mdadm -S /dev/md*
dd if=/dev/zero of=/dev/sda bs=1M count=1024
dd if=/dev/zero of=/dev/sdb bs=1M count=1024

sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk "$FIRST_DISK"
  o # new partition table
  w # write change
EOF
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk "$SECOND_DISK"
  o # new partition table
  w # write change 
EOF
echo "Now Create Partitions Rootfs And Data On Disks $FIRST_DISK And $SECOND_DISK"

sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk "$FIRST_DISK"
  n # new partition
  p # primary partition
  1 # partition number 2
    # default,start immediately after preceding partition (boot)
  +256M  # create a 8GB partition (rootfs)
  t # partition type select
  c # partition type vfat
  n # new partition
  p # primary partition
  2 # partition number 2
    # default,start immediately after preceding partition (boot)
  +8G  # create a 8GB partition (rootfs)
  n # new partition
  p # primary partition
  3 # partion number 3
    # default, start immediately after preceding partition (rootfs)
    # default, extend partition to end of disk (create data partition)
  w # write the partition table
EOF
echo
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk "$SECOND_DISK"
  n # new partition
  p # primary partition
  1 # partition number 2
    # default,start immediately after preceding partition (boot)
  +256M  # create a 8GB partition (rootfs)
  t # partition type select
  c # partition type vfat
  n # new partition
  p # primary partition
  2 # partition number 2
    # default,start immediately after preceding partition (boot)
  +8G  # create a 8GB partition (rootfs)
  n # new partition
  p # primary partition
  3 # partion number 3
    # default, start immediately after preceding partition (rootfs)
    # default, extend partition to end of disk (create data partition)
  w # write the partition table
EOF
partprobe -s
echo "Now Formatting Partitions With VFAT For Boot"
mkfs.fat "$FIRST_BOOT_PARTITION"
mkfs.fat "$SECOND_BOOT_PARTITION"
echo 
echo "The New Partitions Schema Is"
lsblk
sleep 5
echo
echo "Is partition $FIRST_BOOT_PARTITION Not Mounted?"
if df | grep --quiet "$FIRST_BOOT_PARTITION"
then
        umount "$FIRST_BOOT_PARTITION"
fi
echo "OK"
echo
echo "Is partition $SECOND_BOOT_PARTITION Not Mounted?"
if df | grep --quiet "$SECOND_BOOT_PARTITION"
then
        umount "$SECOND_BOOT_PARTITION"
fi
echo "OK"
echo
echo "Start Syncronization Of $FIRST_BOOT_PARTITION..."
BOOT_MOUNTA=/tmp/bootA
mkdir --parents "$BOOT_MOUNTA"
mount "$FIRST_BOOT_PARTITION" "$BOOT_MOUNTA"
rsync --archive --exclude="/lost+found" /boot/ "$BOOT_MOUNTA"
echo "$FIRST_BOOT_PARTITION Are Syncronized"
echo
echo "Start Syncronization Of $SECOND_BOOT_PARTITION..."
BOOT_MOUNTB=/tmp/bootB
mkdir --parents "$BOOT_MOUNTB"
mount "$SECOND_BOOT_PARTITION" "$BOOT_MOUNTB"
rsync --archive --exclude="/lost+found" /boot/ "$BOOT_MOUNTB"
echo "$SECOND_BOOT_PARTITION Are Syncronized"
echo
echo "Create A New Cmdline.txt And A New Config.txt"
rm -f /tmp/bootA/cmdline.txt 
rm -f /tmp/bootB/cmdline.txt 
rm -f /tmp/bootB/config.txt 
touch /tmp/bootA/cmdline.txt
echo "console=serial0,115200 console=tty1 root=/dev/md0 rootfstype=btrfs elevator=deadline fsck.repair=yes boot_delay=20 rootdelay=10 rootwait" >> /tmp/bootA/cmdline.txt
printf "\n# Boot from updated initramfs.\ninitramfs initrd7l.img-v7l+ followkernel\n" >> /tmp/bootA/config.txt
cp /tmp/bootA/cmdline.txt /tmp/bootB/cmdline.txt
cp /tmp/bootA/config.txt /tmp/bootB/config.txt
echo "The Boot Partition Are Ready On Both Disks"
echo
echo "Now Create RAID Array For The RootFs"
mdadm --zero-superblock "$FIRST_ROOT_PARTITION"
mdadm --zero-superblock "$SECOND_ROOT_PARTITION"
mdadm --create "$ROOT_ARRAY" --level=1 --metadata=1.2 --raid-devices=2 "$FIRST_ROOT_PARTITION" "$SECOND_ROOT_PARTITION"
printf "ARRAY\t$ROOT_ARRAY\tname=$(hostname):0\n" >> /etc/mdadm/mdadm.conf
echo "OK"
echo
echo "Format array $ROOT_ARRAY..."
mkfs.btrfs -L "root" "$ROOT_ARRAY"
echo "OK"
echo
echo "Copy live system over to RAID Array $ROOT_ARRAY..."
echo "There is no progress indicator, and this could run for several minutes."
ROOT_MOUNT=/tmp/root
mkdir --parents "$ROOT_MOUNT"
mount "$ROOT_ARRAY" "$ROOT_MOUNT" 
rsync --archive --acls --xattrs --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/boot/*","/app/*"} / "$ROOT_MOUNT" 
echo "OK"
echo
echo "Searching For Current Kernel Version..."
valueold=$(find /lib/modules/ -name "*-v7l+" -print)
IFS='/'
oldkernel=$(echo $valueold | awk '{print $3}')
echo "The Current Kernel Version Is $oldkernel"
echo
echo "Now Create The InitRamFs..."
printf "\nraid1\nmd_mod\nmd\nlinear\nraid0\nraid5\nraid6\nbtrfs\next4\n" >> /etc/initramfs-tools/modules
update-initramfs -c -k $oldkernel
echo
sleep3
mv /boot/initrd.img-$oldkernel /tmp/bootA/initrd7l.img-v7l+
cp /tmp/bootA/initrd7l.img-v7l+ /tmp/bootB/initrd7l.img-v7l+
echo "InitRamFs Is Updated"
echo
echo "The New File Is initrd7l.img-v7l+ At Kernel Version $oldkernel"
echo
echo "Configure fstab on array $ROOT_ARRAY..."
rm -f /tmp/root/etc/fstab 
touch /tmp/root/etc/fstab
echo "proc            /proc           proc    defaults          0       0" >> /tmp/root/etc/fstab
echo "/dev/sda1  /boot           vfat     defaults,nofail       0       2" >> /tmp/root/etc/fstab
echo "/dev/md0   /               btrfs    defaults              0       0" >> /tmp/root/etc/fstab
echo "# a swapfile is not a swap partition, no line here" >> /tmp/root/etc/fstab
echo "#   use  dphys-swapfile swap[on|off]  for that" >> /tmp/root/etc/fstab
echo
echo
echo "Create Backup Directory"
mkdir  /tmp/root/backup
echo
echo "Make a Backup Of Current Kernel Modules..." 
echo
echo "Backup File Is $oldkernel.tar.gz"
tar -czvf /tmp/root/backup/$(uname -r).tar.gz /tmp/root/lib/modules/$(uname -r)
echo
echo "Make A Backup Of Current InitRamFS"
echo
echo "Backup File Is initrd7l.img-v7l+.$oldkernel.tar.gz"
tar -czvf /tmp/root/backup/initrd7l.img-v7l+.$oldkernel.tar.gz /tmp/bootA/initrd7l.img-v7l+
umount "$BOOT_MOUNTA"
umount "$BOOT_MOUNTB"
echo
echo
echo "Downloading Scripts are Started..."
wget -O /tmp/root/root/change_disk.sh https://raw.githubusercontent.com/MTSistemi/PiNas/main/change_disk.sh
wget -O /tmp/root/root/watch.sh https://raw.githubusercontent.com/MTSistemi/PiNas/main/watch.sh
wget https://raw.githubusercontent.com/MTSistemi/PiNas/main/update-pinas -O /tmp/root/usr/local/sbin/update-pinas
wget https://raw.githubusercontent.com/nachoparker/btrfs-snp/master/btrfs-snp -O /tmp/root/usr/local/sbin/btrfs-snp
wget https://raw.githubusercontent.com/nachoparker/btrfs-du/master/btrfs-du -O /tmp/root/usr/local/sbin/btrfs-du
wget -O /tmp/root/root/install_omv5.sh https://raw.githubusercontent.com/MTSistemi/PiNas/main/install_omv5.sh
echo
echo
echo "Set Scripts Permissions..."
chmod +x /tmp/root/usr/local/sbin/update-pinas
chmod +x /tmp/root/usr/local/sbin/btrfs-snp
chmod +x /tmp/root/usr/local/sbin/btrfs-du
chmod +x /tmp/root/root/*.sh
echo
echo 
echo "Configure Crotab For BTRFS Maintenance"
cp /tmp/root/etc/crontab /tmp/root/backup/crontab.backup
touch /tmp/root/etc/crontab 
echo "
## SnapShot ##
30 0	* * mon,wed,fri		root	btrfs-snp /srv/dev-disk-by-label-DATA/ SNAPSHOT 3

## Maintenance Filesystem ##
01 0    1-7 * sat		root	btrfs balance start --full-balance /srv/dev-disk-by-label-DATA/

01 0    7-14 * sun      root    btrfs scrub start /srv/dev-disk-by-label-DATA/

01 0	14-21 * mon		root	btrfs filesystem defragment -r /srv/dev-disk-by-label-DATA/
#" >> /tmp/root/etc/crontab
echo "Prepare mdadm.conf"
rm -f /tmp/root/etc/mdadm/mdadm.conf
touch /tmp/root/etc/mdadm/mdadm.conf
echo "ARRAY   /dev/md0        name=PiNas:0 " >> /tmp/root/etc/mdadm/mdadm.conf
echo
./watch.sh
clear
echo
echo 
echo "      ##########################################################"
echo "      #                                                        #"                                                      
echo "      #                                                        #"
echo "      #            Now 3 new commands are available            #"
echo "      #                                                        #"
echo "      #       update-pinas for update your RaspBerry Pi 4      #"
echo "      #                                                        #"
echo "      #       btrfs-snp for take and manteins a snapshot       #"
echo "      #                                                        #"
echo "      #       btrfs-du command like du specific for BTRFS      #"
echo "      #                                                        #"
echo "      #                                                        #"
echo "      #               Enjoy With Your New PiNas                #"
echo "      #                                                        #"
echo "      #                                                        #"
echo "      ##########################################################"
echo
echo
echo "    For Update Your PiNas Don't Use apt upgrade Or apt dist-upgrade  "
echo "     Break boot, because don't upgrade automatically the initramfs "
echo
echo
echo "                      Use only update-pinas                      "
echo
echo
echo "                  For Install OpenMediaVault 5                  " 
echo
echo "                       ./install_omv5.sh                       "
echo
echo "        For Restore Fault Disk Or Change Disk With New One "
echo
echo "                       ./change_disk.sh                     "
echo
echo
echo
echo
echo "I Need To Reboot..."
read -n1 -r -p "Press Any Key To Continue, Ctrl-C to Abort..." ignore
reboot
