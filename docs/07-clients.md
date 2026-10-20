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

## macOS

Finder → *Go* → *Connect to Server* → `smb://<MAXTOR_IP>`

Recent macOS versions have very limited SMB1 support, so this may or may not work depending on your version. If Finder refuses, use a Linux machine (or a small VM/container) as the client.

The box announces itself via Bonjour (`mDNSResponder`). If it does not appear in the Finder sidebar, see the `bonjour.conf` note in [guide 5](05-repair-filesystems.md). Connecting by IP works regardless.

## Windows

Windows 10/11 ship with the *SMB 1.0/CIFS Client* disabled. You can enable it under *Windows Features*, but that weakens the security of the PC. Prefer a Linux machine as the client.

## What does NOT work

**Proxmox Backup Server (PBS) datastore on the Maxtor.** PBS creates tens of thousands of chunk directories:

- the old `smbd` crashed while creating them, and
- ext3 allows only about 32,000 subdirectories per directory anyway.

Use plain `vzdump` archives instead ([guide 8](08-proxmox-backup.md)).

**Realistic speed:** about 10 MB/s writing over SMB1 (the ARM CPU is the limit).
