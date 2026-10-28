# 8. Backup target for Proxmox VE

The Maxtor works fine as a storage for plain `vzdump` backups. Prerequisite: the share is mounted on the Proxmox host at `/mnt/maxtor` via [`examples/fstab.example`](../examples/fstab.example) (see [guide 7](07-clients.md)).

## 1. Add the storage

```sh
pvesm add dir maxtor-backup --path /mnt/maxtor --content backup --is_mountpoint yes
pvesm status
```

`--is_mountpoint yes` is important: if the share is not mounted, Proxmox marks the storage *inactive* instead of writing the backup to the local disk underneath `/mnt/maxtor`.

## 2. Test backup

Pick a small container (`pct list`):

```sh
vzdump <CT_ID> --storage maxtor-backup --mode snapshot --compress zstd
```

Expected:

```
INFO: creating vzdump archive '/mnt/maxtor/dump/vzdump-lxc-...tar.zst'
INFO: Total bytes written: 1143726080 (1.1GiB, 55MiB/s)
INFO: archive file size: 419MB
INFO: Finished Backup of VM ... (00:00:44)
```

The 55 MiB/s refer to uncompressed data. After zstd compression the Maxtor writes roughly 10 MB/s.

Proxmox shows `filesystem type on dumpdir is 'cifs' - using /var/tmp/... for temporary files` – that is normal.

## 3a. Box always on → scheduled job

*Datacenter → Backup → Add*: storage `maxtor-backup`, selection *All*, mode *Snapshot*, compression *ZSTD*, schedule e.g. `sun 03:00`, tab *Retention*: *Keep Last* = 3.

## 3b. Box only on for backups → script

Many people (us included) only switch the old box on for backups. [`scripts/maxtor-backup.sh`](../scripts/maxtor-backup.sh) does the whole run:

1. checks that the Maxtor answers,
2. shows the RAID status (needs SSH key, see below),
3. triggers the automount and verifies the share is really mounted,
4. backs up the guests selected in the Proxmox backup job for `maxtor-backup` (see below), keeps the last 3 of each,
   then copies any folders listed in `EXTRA_DIRS` (e.g. FRITZ!Box backups, [guide 10](10-fritzbox-backup.md)),
5. unmounts, re-arms the automount and asks whether to switch the Maxtor off (via the firmware's front-button action, then waits until it is really off).

**Which guests?** The script follows the backup job you set up in *Datacenter → Backup* for storage `maxtor-backup` – the same dialog as in 3a, but leave the job **disabled** (no box at the scheduled time anyway). Selection *All*, *All except* (exclude), *Pool* and individually ticked guests all work. Change the selection there, not in the script. If there is no such job, the script backs up nothing and says so; with several jobs on that storage set `JOB_ID` at the top of the script (`pvesh get /cluster/backup` lists the IDs).

Install it on the Proxmox host:

```sh
cp scripts/maxtor-backup.sh /usr/local/bin/maxtor-backup
chmod +x /usr/local/bin/maxtor-backup
# edit MAXTOR=<MAXTOR_IP> at the top
maxtor-backup
```

### How long does it take?

A full run of all guests easily takes more than half an hour. Example: a 33 GB Home Assistant/RaspberryMatic VM took about 10–12 minutes. The rates in the output jump around a lot – empty areas of a virtual disk are skipped at several hundred MB/s, real data goes at 10–20 MB/s. That is normal.

Started in a normal terminal, the backup is aborted when you close the window. Run it as a transient systemd unit instead – it keeps running on its own and switches the box off at the end:

```sh
systemd-run --unit=maxtor-backup /usr/local/bin/maxtor-backup --shutdown
journalctl -fu maxtor-backup        # watch; Ctrl+C only stops watching
systemctl status maxtor-backup      # still running?
```

`--shutdown` is required here, because the script cannot ask in the background. Switching off only works if the Proxmox host's SSH key is on the Maxtor **and** you have connected once by hand to accept the host key – a background job cannot answer the "Are you sure you want to continue connecting?" question.

### SSH key for the Proxmox host (optional)

So the script can read the RAID status and power the box off, give the Proxmox host its own key:

```sh
# on the Proxmox host - Proxmox usually has a key already; only create one if it is missing
[ -f /root/.ssh/id_rsa.pub ] || ssh-keygen -t rsa -b 2048 -N '' -f /root/.ssh/id_rsa
cat /root/.ssh/id_rsa.pub
```

Append that line to `/root/.ssh/authorized_keys` on the Maxtor (e.g. from a computer that already has key access):

```sh
echo '<PASTE_PUBLIC_KEY>' | ssh maxtor 'cat >> /root/.ssh/authorized_keys'
```

Without it the script still backs up; it just skips the RAID status and you power the box off yourself.

## Powering the box off safely

Never just pull the plug. An unclean shutdown makes the old md driver resync the whole mirror (about 2 hours) and ext3 has to replay its journal.

If you switched the box on without `maxtor-backup` – e.g. to restore a backup – use [`scripts/maxtor-off.sh`](../scripts/maxtor-off.sh). It unmounts the share, restarts the automount unit (so the next mount works again, see [guide 7](07-clients.md#directory-is-expected-to-be-a-mount-point-but-is-not-mounted)), switches the box off with `mxotoolbox -f` and waits until it no longer answers ping. It needs the Proxmox host's SSH key on the Maxtor (see above).

```sh
cp scripts/maxtor-off.sh /usr/local/bin/maxtor-off
chmod +x /usr/local/bin/maxtor-off
# edit MAXTOR=<MAXTOR_IP> at the top
maxtor-off
```

By hand:

```sh
umount /mnt/maxtor                         # on the Proxmox host first
systemctl restart mnt-maxtor.automount     # re-arm the automount for next time
ssh maxtor /usr/sbin/mxotoolbox -f         # or the front button / web interface
```

**Not** `ssh maxtor poweroff` – that only halts the kernel and leaves a box you can neither reach nor switch off without pulling the plug ([guide 1](01-shell-access.md#switching-the-box-off-correctly)). The script uses `mxotoolbox -f` and waits until the box stops answering ping.
