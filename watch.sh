#!/bin/bash 
#RAID1 Configuration For PiNas 
#Autor: Mattia Tadini 
#File: watch.sh
#Revision: 1.00 

watch  -n1 cat /proc/mdstat &
WATCHPID=$!
while
progress=$(cat /proc/mdstat |grep -oE 'recovery = ? [0-9]*')
do

if (("$progress" >= "100"))
    then
        break

fi
sleep 1
done

kill $WATCHPID

echo "Now The Array Is Syncronized" 
