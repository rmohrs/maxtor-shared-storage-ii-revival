# 4. Copy the system partitions to the second disk

The RAID only protects your data (partition 6). The operating system – root (`sda1`), firmware configuration (`sda2`) and `/tmp` (`sda5`) – exists only on the first disk. If that disk dies, the box will not boot even though your data is safe on the second disk.

Copying the three system partitions once makes the second disk a complete spare. It takes a few minutes (about 1 GB in total).

> ⚠️ `if=` must be **sda** (source), `of=` must be **sdb** (target). The other way round overwrites your running system.
>
> Do this only after the RAID resync has finished, and while nothing else (backups, copies) is running.

## Prerequisite

The second disk is partitioned exactly like the first ([guide 3](03-raid-rebuild.md), step 4).

## 1. Root partition (sda1)

```sh
sync
mount -o remount,ro / && echo "RO OK"
dd if=/dev/sda1 of=/dev/sdb1 bs=64k
mount -o remount,rw /
```

On a running box, `remount,ro` usually fails with `Device or resource busy`. Copy anyway – step 5 repairs the small inconsistencies in the copy.

## 2. Configuration partition (sda2)

```sh
umount /mnt/__mxo_sda2
dd if=/dev/sda2 of=/dev/sdb2 bs=64k
mount /dev/sda2 /mnt/__mxo_sda2
```

## 3. /tmp partition (sda5)

```sh
sync
dd if=/dev/sda5 of=/dev/sdb5 bs=64k
```

## 4. Boot code in the MBR

Only the first 446 bytes – the partition table of `sdb` stays untouched:

```sh
dd if=/dev/sda of=/dev/sdb bs=446 count=1
```

## 5. Check the copies

```sh
e2fsck -f -y /dev/sdb1
e2fsck -f -y /dev/sdb2
e2fsck -f -y /dev/sdb5
```

Expected: a recreated `lost+found` and a replayed journal on `sdb1`/`sdb5` (they were mounted while copying). That is normal.

## Keep it up to date

This copy is a **snapshot**, it is not mirrored continuously. After important changes in the web interface (users, shares, network settings) repeat step 2 and `e2fsck -f -y /dev/sdb2`.

## Boot partitions

The boot loader (U-Boot "Maxtor v1.07") can start the system from four places. `mxoparam -h` lists them:

| `mxoparam -q` | Boots from |
|---|---|
| 0 | drive 0, partition 1 (`sda1`, the default) |
| 1 | drive 0, partition 2 (`sda2`) |
| 2 | drive 1, partition 1 (`sdb1`) |
| 3 | drive 1, partition 2 (`sdb2`) |

`mxoparam -p` shows the current setting, `mxoparam -a` the boot fail counters. So partition 2 is a second system image, not only configuration – and the copy on the second disk is a real boot candidate. We have not switched the boot partition ourselves; only change it if you know you need to.

## If the first disk dies

Power off, put the second disk into the **first bay** (where `sda` was) so it is detected as `sda` at boot, put a new disk into the second bay and follow [guide 3](03-raid-rebuild.md) again.

> We have verified the copy itself, but not yet an actual boot from the second disk. If you test it, please report back in an issue.
