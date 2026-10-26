#!/bin/bash
# maxtor-off – unmount the Maxtor share on the Proxmox host and switch the box off cleanly
#
# Use it when the Maxtor was switched on without running maxtor-backup,
# e.g. to restore a backup. maxtor-backup does the same at its end.
#
# Requirements (see docs/07-clients.md and docs/08-proxmox-backup.md):
#   - /etc/fstab entry for the share with systemd automount (examples/fstab.example)
#   - SSH key of this host in /root/.ssh/authorized_keys on the Maxtor
#
# Usage:
#   maxtor-off

# ---- adjust these -----------------------------------------------------------
MAXTOR="<MAXTOR_IP>"        # IP address of the Maxtor, e.g. 192.168.1.50
MNT="/mnt/maxtor"           # mount point from /etc/fstab
# -----------------------------------------------------------------------------

SSHOPT="-o BatchMode=yes -o ConnectTimeout=5 \
 -o KexAlgorithms=+diffie-hellman-group1-sha1 \
 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
 -o Ciphers=+aes128-cbc"

case "$MAXTOR" in
  "<"*) echo "Please set MAXTOR=<your IP> at the top of $0"; exit 2 ;;
esac

AUTOMOUNT="$(systemd-escape --path "$MNT").automount"   # /mnt/maxtor -> mnt-maxtor.automount

echo "== Unmounting =="
sync
if findmnt -t cifs "$MNT" >/dev/null; then
  umount "$MNT" || { echo "ERROR: $MNT is still in use (backup or restore running?)"; exit 1; }
fi
# Re-arm the automount, otherwise the next access only sees the empty local folder
# ("directory is expected to be a mount point but is not mounted").
systemctl restart "$AUTOMOUNT"

echo "== Switching off =="
# Do NOT use "poweroff": it only halts the kernel, the box stays on (ping answers,
# SSH/web are dead). The firmware's own way is the front-button action below.
# The exit code of ssh is not checked: the box may drop the connection while
# switching off. Whether it worked is decided by ping below.
# shellcheck disable=SC2086
ssh $SSHOPT root@"$MAXTOR" 'sync; /usr/sbin/mxotoolbox -f' >/dev/null 2>&1
printf "Waiting for the Maxtor to switch off"
for _ in $(seq 1 24); do
  sleep 5
  if ! ping -c 1 -W 2 "$MAXTOR" >/dev/null 2>&1; then
    echo; echo "Maxtor is off (press the front button to start it again)."
    exit 0
  fi
  printf "."
done
echo; echo "Maxtor still answers - switch it off via the web interface or the front button"
echo "(no SSH key for this host on the Maxtor? see docs/08-proxmox-backup.md)."
exit 1
