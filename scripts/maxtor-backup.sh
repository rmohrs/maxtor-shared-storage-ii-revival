#!/bin/bash
# maxtor-backup – back up all Proxmox VMs/containers to a Maxtor Shared Storage II
#
# Requirements (see docs/07-clients.md and docs/08-proxmox-backup.md):
#   - /etc/fstab entry for the share with systemd automount (examples/fstab.example)
#   - Proxmox storage:  pvesm add dir maxtor-backup --path /mnt/maxtor --content backup --is_mountpoint yes
#   - optional: SSH key of this host in /root/.ssh/authorized_keys on the Maxtor
#
# Usage:
#   maxtor-backup                 back up, then ask whether to power the Maxtor off
#   maxtor-backup --poweroff      back up, then power off without asking
#   maxtor-backup --keep-on       back up, leave the Maxtor running

# ---- adjust these -----------------------------------------------------------
MAXTOR="<MAXTOR_IP>"        # IP address of the Maxtor, e.g. 192.168.1.50
MNT="/mnt/maxtor"           # mount point from /etc/fstab
STORE="maxtor-backup"       # Proxmox storage name
KEEP=3                      # backups to keep per VM/container
# -----------------------------------------------------------------------------

SSHOPT="-o BatchMode=yes -o ConnectTimeout=5 \
 -o KexAlgorithms=+diffie-hellman-group1-sha1 \
 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
 -o Ciphers=+aes128-cbc"

MODE="ask"
case "$1" in
  --poweroff) MODE="off" ;;
  --keep-on)  MODE="on" ;;
  "")         ;;
  *) echo "Usage: $0 [--poweroff|--keep-on]"; exit 2 ;;
esac

case "$MAXTOR" in
  "<"*) echo "Please set MAXTOR=<your IP> at the top of $0"; exit 2 ;;
esac

echo "== Maxtor reachable? =="
if ! ping -c 2 -W 2 "$MAXTOR" >/dev/null; then
  echo "ERROR: $MAXTOR does not answer - is the Maxtor switched on?"
  exit 1
fi

echo "== RAID status =="
# shellcheck disable=SC2086
if MD=$(ssh $SSHOPT root@"$MAXTOR" 'cat /proc/mdstat' 2>/dev/null); then
  echo "$MD" | grep -A1 '^md0'
  echo "$MD" | grep -q '\[UU\]' || echo "WARNING: RAID is not complete ([UU] missing) - backup runs anyway"
else
  echo "(not available - no SSH key for this host on the Maxtor)"
fi

echo "== Mounting share =="
ls "$MNT" >/dev/null 2>&1        # triggers the systemd automount
if ! awk -v m="$MNT" '$2==m && $3=="cifs"' /proc/mounts | grep -q .; then
  echo "ERROR: $MNT is not mounted (check /etc/fstab and 'mount -v $MNT')."
  exit 1
fi
pvesm set "$STORE" --disable 0 2>/dev/null
df -h "$MNT" | tail -1

echo "== Backup running =="
vzdump --all 1 --storage "$STORE" --mode snapshot --compress zstd \
       --prune-backups keep-last="$KEEP"
RC=$?

echo "== Archives on the Maxtor =="
ls -lh "$MNT"/dump/*.zst 2>/dev/null | awk '{print $5, $9}'
df -h "$MNT" | tail -1

umount "$MNT" 2>/dev/null
if [ $RC -eq 0 ]; then
  echo "== Backup OK =="
else
  echo "== WARNING: backup finished with errors (exit code $RC) =="
fi

if [ "$MODE" = "ask" ]; then
  read -r -p "Power the Maxtor off now? [y/N] " A
  case "$A" in y|Y|j|J) MODE="off" ;; esac
fi
if [ "$MODE" = "off" ]; then
  # Do NOT use "poweroff": it only halts the kernel, the box stays on (ping answers,
  # SSH/web are dead). The firmware's own way is the front-button action below.
  # shellcheck disable=SC2086
  if ssh $SSHOPT root@"$MAXTOR" true 2>/dev/null; then
    # shellcheck disable=SC2086
    ssh $SSHOPT root@"$MAXTOR" 'sync; /usr/sbin/mxotoolbox -f' >/dev/null 2>&1
    printf "Waiting for the Maxtor to switch off"
    for _ in $(seq 1 24); do
      sleep 5
      if ! ping -c 1 -W 2 "$MAXTOR" >/dev/null 2>&1; then
        echo; echo "Maxtor is off (press the front button to start it again)."
        exit $RC
      fi
      printf "."
    done
    echo; echo "Maxtor still answers - switch it off via the web interface or the front button."
  else
    echo "No SSH key for this host on the Maxtor - switch it off via the web interface,"
    echo "the front button or from a computer with key access: ssh maxtor /usr/sbin/mxotoolbox -f"
  fi
fi

exit $RC
