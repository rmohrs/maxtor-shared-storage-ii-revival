# 7. Use it from Linux / macOS / Windows (SMB1)

The Maxtor's Samba speaks **SMB1 only** and does not support NTLMSSP. Modern clients have SMB1 switched off by default, because SMB1 is insecure. Only use the box inside your own home network, never expose it to the internet.

## Linux (recommended)

Install the CIFS tools (`apt install cifs-utils` on Debian/Ubuntu/Proxmox).

Credentials file, readable only by root:

```sh
cat > /root/.maxtor-cred <<'EOF'
username=<SMB_USER>
password=<SMB_PASSWORD>
EOF
chmod 600 /root/.maxtor-cred
```

Test mount:

```sh
mkdir -p /mnt/maxtor
mount -t cifs //<MAXTOR_IP>/<SHARE> /mnt/maxtor \
  -o credentials=/root/.maxtor-cred,vers=1.0,sec=ntlmv2,nounix,noperm,uid=0,gid=0,soft
```

| Option | Why |
|---|---|
| `vers=1.0` | the box only speaks SMB1 |
| `sec=ntlmv2` | the box cannot do NTLMSSP (the modern default) – without this, the mount fails |
| `nounix,noperm` | the old Samba's Unix extensions confuse modern clients |
| `uid=0,gid=0` | all files appear owned by root on the client |
| `soft` | **important:** if the box is off, access fails with an error instead of hanging forever |

For a permanent mount use [`examples/fstab.example`](../examples/fstab.example). It uses **systemd automount**: the share is mounted on first access, not at boot. This avoids two problems we hit:

- At boot the network was not ready yet → mount failed with `-113` (*No route to host*).
- When the Maxtor was powered off with the share still mounted, processes on the client got stuck in state `D` (uninterruptible) – only a reboot of the client helped. `soft` + automount prevents that.

After editing `/etc/fstab`:

```sh
systemctl daemon-reload
systemctl restart mnt-maxtor.automount
ls /mnt/maxtor         # triggers the mount
```

### "directory is expected to be a mount point but is not mounted"

Proxmox reports this (or `findmnt /mnt/maxtor` shows nothing) although the Maxtor is on. The automount unit is no longer active – typically after the box was switched off by hand while the share was mounted. `ls /mnt/maxtor` then only looks into the empty local folder and mounts nothing.

```sh
systemctl status mnt-maxtor.automount   # "inactive" or "failed"
systemctl daemon-reload
systemctl restart mnt-maxtor.automount
ls /mnt/maxtor >/dev/null
findmnt /mnt/maxtor                     # must show cifs //<MAXTOR_IP>/<SHARE>
```

If it still does not mount: `mount -v /mnt/maxtor` and `dmesg | tail`. Error `-112` = Samba on the box is not ready yet (wait a minute after switching on), `-13` = wrong credentials.

`maxtor-backup` and `maxtor-off` ([guide 8](08-proxmox-backup.md)) restart the automount unit after unmounting, so this should only happen when the box is switched off another way.

## macOS

Finder → *Go* → *Connect to Server* → `smb://<MAXTOR_IP>`

On a current macOS (tested October 2026) the connection **fails** with "Beim Verbinden mit dem Server ist ein Fehler aufgetreten" / "There was a problem connecting to the server". macOS no longer speaks SMB1 by default, and the box only supports the old NTLMv2 login without NTLMSSP. Allowing SMB1 in the Mac client is reversible and worth one try:

```sh
printf '[default]\nprotocol_vers_map=7\n' | sudo tee /etc/nsmb.conf   # allow SMB1/2/3
sudo rm /etc/nsmb.conf                                              # undo
```

We could not confirm that this is enough. If Finder still refuses, use a Linux machine (or a small VM/container) as the client, or copy single files over SSH:

```sh
cat file.pdf | ssh maxtor 'cat > /share/<SHARE>/file.pdf'
```

(`cat` over SSH instead of `scp`: the old dropbear often does not understand the modern scp protocol.)

### Why the box does not show up in the Finder sidebar

The Finder lists network file servers that announce `_smb._tcp` via Bonjour. Check from a Mac what is announced in your network:

```sh
dns-sd -B _smb._tcp          # stop with Ctrl+C after a few seconds
```

The Maxtor runs `mDNSResponder -f /etc/bonjour.conf`, but that file only announces its own services (`_mssmaxtorinfo._udp`, `_mssmaxtorconfig._tcp` on port 4301 for the old Maxtor software) and the NetBIOS ports (`_netbios-ns._udp` 137, `_netbios-ssn._tcp` 139) – **no `_smb._tcp`**. Back then the box was found through Maxtor's own software, not through the Finder.

You can add the missing entry (on the Maxtor):

```sh
cat >> /etc/bonjour.conf <<'EOF'

Maxtor
_smb._tcp.
139
val=val5
EOF
killall mDNSResponder
cd /usr/bin && ./mDNSResponder -f /etc/bonjour.conf -b
```

The box then appears in the Finder under *Network* – but connecting still fails on macOS versions without SMB1 (see above). Because the firmware rewrites `/etc` on every boot, the entry is gone after the next reboot. That is deliberate in our setup: an entry you cannot open is not useful. If your Mac *can* connect, make it permanent with:

```sh
cp /etc/bonjour.conf /mnt/__mxo_sda2/etc/bonjour.conf
cp /etc/bonjour.conf /etc/bonjour.conf-default
sync
```

Bonjour is only needed for automatic discovery. Mounts by IP (Linux, Proxmox) and `ssh` work without it.

## Windows

Windows 10/11 ship with the *SMB 1.0/CIFS Client* disabled. You can enable it under *Windows Features*, but that weakens the security of the PC. Prefer a Linux machine as the client.

## What does NOT work

**Proxmox Backup Server (PBS) datastore on the Maxtor.** PBS creates tens of thousands of chunk directories:

- the old `smbd` crashed while creating them, and
- ext3 allows only about 32,000 subdirectories per directory anyway.

Use plain `vzdump` archives instead ([guide 8](08-proxmox-backup.md)).

**Realistic speed:** about 10 MB/s writing over SMB1 (the ARM CPU is the limit).
