# 2. Check the disks (SMART)

Good news: `smartctl` (version 5.1) is already on the box.

## Which disks are there?

```sh
cat /proc/partitions
cat /proc/mdstat
dmesg | grep -i -E 'sd[ab]|scsi|ata'
```

- Both disks should appear (`sda` on `scsi0`, `sdb` on `scsi1`).
- `cat /proc/mdstat` shows the RAID: `[2/2] [UU]` = both mirrors fine, `[2/1] [U_]` = degraded (only one disk working).

If a disk is not detected at all, power the box off, reseat the disk and try again. If it is still missing, test the disk in another computer (USB-SATA adapter).

## Read the SMART values

```sh
smartctl -a /dev/sda
smartctl -a /dev/sdb
```

If `smartctl` complains that the device is not supported (Marvell controller), try `-d marvell` or `-d ata`. On our box plain `smartctl -a /dev/sdX` worked.

### The values that matter

| ID | Attribute | Healthy | Meaning |
|---|---|---|---|
| 5 | `Reallocated_Sector_Ct` | 0 | Sectors already replaced by spares |
| 197 | `Current_Pending_Sector` | 0 | Sectors the disk could not read and waits to remap |
| 198 | `Offline_Uncorrectable` | 0 | Sectors that could not be repaired |
| 199 | `UDMA_CRC_Error_Count` | 0 (a single old count is OK) | Cable / connector problems – watch if it **rises** |
| – | `SMART Error Log` | `No Errors Logged` | |

Small numbers in 5/197/198 on an old disk are a warning, growing numbers mean: replace it.

### Values that only look scary

On Seagate disks, `Raw_Read_Error_Rate`, `Seek_Error_Rate` and `Hardware_ECC_Recovered` show huge raw values. That is normal – Seagate encodes several counters in one number. Look at the normalized `VALUE` vs. `THRESH` columns instead.

Seagate attribute **190** (airflow temperature) may show `In_the_past` in the `WHEN_FAILED` column. That means the disk was too hot at some point. Check that the box's fan runs and is not clogged with dust.

## Long self-test (recommended for every replacement disk)

```sh
smartctl -t long /dev/sdb          # starts the test inside the disk
smartctl -c /dev/sdb | grep -A1 'Self-test execution'   # progress
smartctl -l selftest /dev/sdb      # result (appears only when finished)
```

The test reads every sector and takes 1–3 hours depending on the disk (`Extended self-test routine recommended polling time` in the `smartctl -a` output tells you). The result should be:

```
# 1  Extended off-line   Completed   00%   ...   -
```

A dash in `LBA_of_first_error` = no bad sector found. Anything else → do not use that disk for your mirror.

> Real-world note: our first replacement was a used disk from a Windows PC. It was detected fine, but failed during the RAID resync with `sense key=0x3` (medium error) about 50 GB into the disk. A long test beforehand would have caught that. The second replacement passed the long test and resynced without a single error.
