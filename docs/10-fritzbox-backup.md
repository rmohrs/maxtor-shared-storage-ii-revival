# 10. Back up the FRITZ!Box configuration

An AVM FRITZ!Box can only export its configuration by hand in the web interface – it cannot write backups to a network share, and certainly not to an SMB1-only box. The trick: let the always-on Linux / Proxmox host fetch the configuration on a schedule and keep it locally. [`maxtor-backup`](../scripts/maxtor-backup.sh) copies that folder to the Maxtor whenever the box is switched on for a backup run.

```
FRITZ!Box ──TR-064──▶ Proxmox host /root/fritzbox-backups ──maxtor-backup──▶ Maxtor /share/<SHARE>/extra/fritzbox-backups
           (weekly, cron)                                   (whenever the Maxtor is on)
```

This way you have two copies (host + RAID 1), and the backup also works while the Maxtor is off.

Tested with a FRITZ!Box 7490; the TR-064 call `X_AVM-DE_GetConfigFile` exists on all current FRITZ!OS versions.

## 1. Prepare the FRITZ!Box (once)

1. *Home Network → Network → Network Settings*: enable **Allow access for applications** (TR-064).
2. *System → FRITZ!Box Users*: add a user, e.g. `backup`, with the right **FRITZ!Box settings**.
3. Choose an **export password**. Without it, the backup file cannot be restored – store it in your password manager as well, not only on the host.

## 2. Credentials on the host

```sh
cat > /root/.fritz-cred <<'EOF'
FRITZ_USER=<FRITZ_USER>
FRITZ_PASS=<FRITZ_PASSWORD>
EXPORT_PASS=<EXPORT_PASSWORD>
EOF
chmod 600 /root/.fritz-cred
```

## 3. Install the script

```sh
cp scripts/fritzbox-backup.sh /usr/local/bin/fritzbox-backup
chmod +x /usr/local/bin/fritzbox-backup
# edit FB=<FRITZBOX_IP> (and NAME if you like) at the top
fritzbox-backup
```

Expected:

```
Saved: /root/fritzbox-backups/fritzbox_2026-10-23_1105.export (40K)
```

The file starts with `**** FRITZ!Box Configuration File` – the script checks that. Sizes from about 30 KB to a few hundred KB are normal, depending on phone books, smart-home devices etc. The script keeps the newest 10 files.

If you get `no download URL`: check TR-064, user name/password and the user's rights. The script prints the FRITZ!Box's own error message if there is one.

## 4. Run it weekly

```sh
echo '15 3 * * 0 root /usr/local/bin/fritzbox-backup >/dev/null 2>&1' > /etc/cron.d/fritzbox-backup
```

(Sunday 03:15. Remove `>/dev/null 2>&1` if your host mails cron output to you.)

## 5. Copy it to the Maxtor

In `/usr/local/bin/maxtor-backup` set:

```sh
EXTRA_DIRS="/root/fritzbox-backups"
```

On every run, after the VM/container backups, the script copies new files to `/mnt/maxtor/extra/fritzbox-backups`. You can list more folders separated by spaces. Old files on the Maxtor are not deleted – the configuration files are tiny, so that does not matter.

## Restoring

*System → Backup → Restore* in the FRITZ!Box web interface, select the `.export` file and enter the export password. Restoring to the **same model** restores everything; on a different model FRITZ!OS only takes over part of the settings.

## Alternative without a script

The FRITZ!Box **Push Service** can e-mail a configuration backup automatically after changes (*System → Push Service*). That is a nice third copy outside your home network.
