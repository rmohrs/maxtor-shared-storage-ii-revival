# 3. Replace a disk & rebuild the RAID 1

The data share `/share` is a Linux software RAID 1 (`/dev/md0`) built from partition 6 of both disks. If one disk dies, the box keeps running on the other one (`[2/1] [U_]` in `/proc/mdstat`). It does **not** rebuild by itself when you insert a new disk – a blank disk has no partitions, so you have to create them and add the disk manually.

> The examples assume the **healthy disk is `sda`** and the **new disk is `sdb`**. If it is the other way round on your box, swap the names everywhere. Check with `fdisk -l` first!

## 1. Remove the old disk from the array

If the failed disk is still listed in `/proc/mdstat` (marked `(F)`), remove it:

```sh
mdadm /dev/md0 --remove /dev/sdb6
```

## 2. Swap the disk

```sh
/usr/sbin/mxotoolbox -f     # NOT poweroff – see guide 1
```

Wait until the box is off (fan and button light off), swap the disk, press the front button. The box has no hot-swap – always change disks while it is powered off.

## 3. Check the new disk

```sh
fdisk -l /dev/sda
fdisk -l /dev/sdb
smartctl -a /dev/sdb
```

The new disk needs **at least as many cylinders/sectors** as the old one. Two "500 GB" disks from different vendors can differ by a few MB – if the new one is smaller, partition 6 will not fit. A larger disk is fine.

Then run the SMART long test from [guide 2](02-check-disks.md) before you put any trust in the disk.

## 4. Partition the new disk exactly like the old one

The box has **no `sfdisk`**, so we use `fdisk` interactively. This is the layout of the 500 GB model (`fdisk -l /dev/sda` shows 60801 cylinders):

| Partition | Start | End | Type |
|---|---|---|---|
| 1 | 1 | 31 | 83 Linux (boot flag) |
| 2 | 32 | 62 | 83 Linux |
| 3 | 63 | 93 | 82 Linux swap |
| 4 | 94 | 60801 | 5 Extended |
| 5 | 94 | 154 | 83 Linux |
| 6 | 155 | 60801 | fd Linux raid autodetect |

**Take the numbers from your own `fdisk -l /dev/sda`** if they differ. On a larger new disk, let partitions 4 and 6 end at the new disk's last cylinder.

```sh
fdisk /dev/sdb
```

Type (press Enter after each value):

```
o                      new empty partition table (old partitions on sdb are destroyed!)
n p 1    1     31
n p 2    32    62
n p 3    63    93
n e 4    94    60801
n l      94    154     (fdisk may not ask for "l" – just enter start/end)
n l      155   60801
t 3 82
t 6 fd
a 1
p                      compare with fdisk -l /dev/sda – must be identical
w                      write
```

The warnings about "more than 1024 cylinders" and "invalid flag 0x0000 of partition table 4" are harmless.

Check that the kernel sees the new partitions:

```sh
grep sdb /proc/partitions
```

`sdb1`…`sdb6` must be listed (`sdb4` with size `1` is normal for the extended partition). If `sdb6` is missing, reboot once.

## 5a. Add the new disk to the existing array (keeps your data)

This is the normal case:

```sh
mdadm /dev/md0 --add /dev/sdb6
mkswap /dev/sdb3
cat /proc/mdstat
```

## 5b. Alternative: start with a completely fresh, empty array (DELETES all data on /share)

Only if you want to get rid of the old data anyway:

```sh
umount /share
mdadm --stop /dev/md0
mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sda6 /dev/sdb6
#   answer "y" to "Continue creating array?" – the warnings about an
#   existing ext2fs / raid on sda6 are expected
mke2fs -j /dev/md0
mount /dev/md0 /share
mkswap /dev/sdb3
tune2fs -m 0 /dev/md0      # optional: free the 5 % root reserve (~23 GB on 500 GB)
```

Do **not** run `mdadm --create` before partition 6 exists on the new disk – it aborts with `Cannot open /dev/sdb6`. Nothing is destroyed in that case, but nothing happens either.

Afterwards recreate your shares in the web interface ([guide 6](06-shares.md)) – the old folders are gone with the old file system.

## 6. Wait for the resync

```sh
cat /proc/mdstat
```

```
md0 : active raid1 sdb6[1] sda6[0]
      487146880 blocks [2/2] [UU]
      [=====>...............]  resync = 29.7% ... finish=70.5min speed=78369K/sec
```

- Realistic speed: **~75 MB/s** → about **1¾ hours** for 500 GB.
- If it crawls at ~1 MB/s, something else is using the disks (e.g. a running `mke2fs`). It speeds up afterwards. You can also raise the guaranteed minimum (reset on reboot):
  ```sh
  echo 20000 > /proc/sys/dev/raid/speed_limit_min
  ```
- You may use the shares during the resync, it is just slower.
- **Do not reboot or power off during the resync** – it starts over from zero.

Watch for disk errors while it runs:

```sh
dmesg | grep -i -E 'error|sense|sdb'
```

`end_request: I/O error, dev sdb, sector …` with `sense key=0x3` means the new disk has bad sectors – md will kick it out (`(F)` in `/proc/mdstat`). Get another disk.

`VFS: Can't find ext3 filesystem on dev sdb1` at boot is harmless – the firmware tries to mount the (still empty) system partition of the second disk. [Guide 4](04-mirror-system.md) fills it.

When `/proc/mdstat` shows `[2/2] [UU]` without a progress bar, the mirror is complete.
