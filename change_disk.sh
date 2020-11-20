#!/bin/bash
# Autor: Mattia Tadini
# File: change_disk.sh
# Revision: 1.00
#
#
#

#Set Variable For Disks, Partitions And Arrays
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
echo "YEAH!"

echo "Is Disk $FIRST_DISK plugged in?"
[[ -e "$FIRST_DISK" ]]
echo "OK"

echo "Is Disk $SECOND_DISK plugged in?"
[[ -e "$SECOND_DISK" ]]
echo "OK"

echo "Destroy Partition Table On $FIRST_DISK..."
echo "Copy Partition Table Of $SECOND_DISK To $FIRST_DISK..."
sfdisk -d "$SECOND_BOOT_PARTITION" | sfdisk "$FIRST_BOOT_PARTITION"
partprobe -s && lsblk
sleep 10
mkfs.fat "$FIRST_BOOT_PARTITION"
sleep 2
mount "$SECOND_BOOT_PARTITION" /boot
mkdir /tmp/boot
mount "$FIRST_BOOT_PARTITION" /tmp/boot
cp -R /boot/* /tmp/boot/
umount "$SECOND_BOOT_PARTITION"
umount "$FIRST_BOOT_PARTITION"
mount "$FIRST_BOOT_PARTITION" /boot
sleep 5
cat /proc/mdstat
sleep 5
#mdadm -S /dev/md127
dd if=/dev/zero of="$SECOND_BOOT_PARTITION" bs=1M count=1024
#mdadm --manage "$ROOT_ARRAY" --fail "$SECOND_BOOT_PARTITION"
#mdadm --manage "$ROOT_ARRAY" --remove "$SECOND_BOOT_PARTITION"
mdadm --manage "$ROOT_ARRAY" --add "$SECOND_BOOT_PARTITION"
sleep 5
./watch.sh
