# 5. Repair the firmware file systems (e2fsck)

After years without use, `dmesg` will probably greet you with:

```
EXT3-fs warning: maximal mount count reached, running e2fsck is recommended
EXT3-fs warning: checktime reached, running e2fsck is recommended
```

The firmware never runs `e2fsck` itself. Usually that is only a reminder, but on our box the configuration partition really was damaged:

```
EXT3-fs error (device sda2): ext3_readdir: bad entry in directory #385 ...
EXT3-fs error (device sda2): ext3_journal_start_sb: Detected aborted journal
```

After an *aborted journal* the partition is effectively read-only – settings you change in the web interface may silently not be saved.

## Check the configuration partition (sda2)

`sda2` can be unmounted while the box runs:

```sh
# 1. back up its content to the data share first
tar czf /share/sda2-backup.tgz -C /mnt/__mxo_sda2 .

# 2. unmount, check, remount
umount /mnt/__mxo_sda2
e2fsck -f -y /dev/sda2
mount /dev/sda2 /mnt/__mxo_sda2
dmesg | tail -5
```

`tar` may report `Input/output error` for damaged files – the rest of the archive is still usable. Copy the archive to your computer as well.

On our box `e2fsck` removed a broken `etc/bonjour.conf` and the cache of the iTunes server (`__mt-daapd`). Both were harmless: the firmware regenerates `/etc/bonjour.conf` from `/etc/bonjour.conf-default` at boot (`mDNSResponder -f /etc/bonjour.conf`). To put it back on the configuration partition:

```sh
cp /etc/bonjour.conf /mnt/__mxo_sda2/etc/
sync
```

## The data partition (/share)

```sh
umount /share
e2fsck -f -y /dev/md0
mount /dev/md0 /share
```

Stop file access (Samba clients, backups) before you unmount. If you created a fresh array in [guide 3](03-raid-rebuild.md) (5b), there is nothing to check.

## The root partition (sda1)

Root cannot be unmounted while the box runs, so it cannot be checked safely online. Options:

- leave it (it was the least affected partition on our box), or
- check the copy on the second disk instead (`e2fsck -f -y /dev/sdb1`, see [guide 4](04-mirror-system.md)), or
- put the disk into a Linux PC (USB-SATA adapter) and run `e2fsck -f /dev/sdX1` there.
