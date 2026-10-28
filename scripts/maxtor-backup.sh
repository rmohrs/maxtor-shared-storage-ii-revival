#!/bin/bash
# maxtor-backup – back up Proxmox VMs/containers to a Maxtor Shared Storage II
#   The guests are taken from the Proxmox backup job that writes to $STORE
#   (Datacenter -> Backup; the job may stay disabled, it only holds the selection).
#
# Requirements (see docs/07-clients.md and docs/08-proxmox-backup.md):
#   - /etc/fstab entry for the share with systemd automount (examples/fstab.example)
#   - Proxmox storage:  pvesm add dir maxtor-backup --path /mnt/maxtor --content backup --is_mountpoint yes
#   - a backup job for that storage (can be disabled) with the guests to back up
#   - optional: SSH key of this host in /root/.ssh/authorized_keys on the Maxtor
#   - optional: EXTRA_DIRS below, e.g. the FRITZ!Box backups (docs/10-fritzbox-backup.md)
#
# Usage:
#   maxtor-backup                 back up, then ask whether to power the Maxtor off
#   maxtor-backup --shutdown      back up, then switch the Maxtor off without asking
#                                 (uses the firmware's front-button action, NOT the poweroff command;
#                                  --poweroff is accepted as an old alias)
#   maxtor-backup --keep-on       back up, leave the Maxtor running

# ---- adjust these -----------------------------------------------------------
MAXTOR="<MAXTOR_IP>"        # IP address of the Maxtor, e.g. 192.168.1.50
MNT="/mnt/maxtor"           # mount point from /etc/fstab
STORE="maxtor-backup"       # Proxmox storage name
KEEP=3                      # backups to keep per VM/container
JOB_ID=""                   # backup job to follow, e.g. "backup-1a2b3c4d";
                            # empty = the one job that writes to $STORE
EXTRA_DIRS=""               # local folders to copy along, space separated,
                            # e.g. "/root/fritzbox-backups" -> $MNT/extra/fritzbox-backups
HOST_BACKUP=1               # 1 = also save this host's own configuration (not covered by vzdump)
HOST_KEEP=10                # host archives to keep, in $MNT/host/
HOST_PATHS="/etc/pve /var/lib/pve-cluster /etc/network /etc/hosts /etc/hostname
 /etc/resolv.conf /etc/fstab /etc/cron.d /etc/crontab /etc/systemd/system /etc/vzdump.conf
 /etc/modprobe.d /etc/modules /etc/default/grub /etc/kernel /etc/apt/sources.list
 /etc/apt/sources.list.d /etc/ssh /usr/local/bin /var/spool/cron/crontabs
 /root/.ssh /root/.bashrc /root/.maxtor-cred /root/.fritz-cred"
                            # missing paths are skipped silently
# -----------------------------------------------------------------------------

SSHOPT="-o BatchMode=yes -o ConnectTimeout=5 \
 -o KexAlgorithms=+diffie-hellman-group1-sha1 \
 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
 -o Ciphers=+aes128-cbc"

MODE="ask"
case "$1" in
  --shutdown|--poweroff) MODE="off" ;;
  --keep-on)  MODE="on" ;;
  "")         ;;
  *) echo "Usage: $0 [--shutdown|--keep-on]"; exit 2 ;;
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
# Guest selection from the Proxmox backup job (all / all except / pool / selected guests)
RC=1
SEL=$(pvesh get /cluster/backup --output-format json | perl -MJSON::PP -e '
  my ($store, $id) = @ARGV;
  my $jobs = decode_json(do { local $/; <STDIN> });
  my @m = grep { $id ne "" ? $_->{id} eq $id : ($_->{storage} // "") eq $store } @$jobs;
  die "no backup job " . ($id ne "" ? "with id $id" : "for storage $store") . "\n" unless @m;
  die "several backup jobs for storage $store - set JOB_ID\n" if @m > 1;
  my $j = $m[0];
  if    ($j->{all})  { print "--all 1", ($j->{exclude} ? " --exclude $j->{exclude}" : "") }
  elsif ($j->{pool}) { print "--pool $j->{pool}" }
  elsif ($j->{vmid}) { (my $v = $j->{vmid}) =~ s/,/ /g; print $v }
  else               { die "job $j->{id} selects no guests\n" }
' "$STORE" "$JOB_ID") || SEL=""
if [ -n "$SEL" ]; then
  echo "Guests from backup job: $SEL"
  # shellcheck disable=SC2086
  vzdump $SEL --storage "$STORE" --mode snapshot --compress zstd \
         --prune-backups keep-last="$KEEP"
  RC=$?
else
  echo "ERROR: could not read the guest selection from the backup job - nothing backed up"
  echo "       (Datacenter -> Backup: add a job for storage $STORE, it may stay disabled)"
fi

if [ -n "$EXTRA_DIRS" ]; then
  echo "== Copying extra folders =="
  for D in $EXTRA_DIRS; do
    if [ -d "$D" ]; then
      T="$MNT/extra/$(basename "$D")"
      mkdir -p "$T"
      # -u: only new/changed files; no -p, the SMB1 share cannot keep owners/modes
      if cp -ru "$D"/. "$T"/; then
        echo "$D -> $T ($(ls -1 "$T" | wc -l) files)"
      else
        echo "WARNING: copying $D failed"
      fi
    else
      echo "WARNING: $D does not exist - skipped"
    fi
  done
fi

if [ "$HOST_BACKUP" = "1" ]; then
  # vzdump saves the guests, but not the host: storage and network setup, fstab,
  # these scripts, credentials, SSH keys, cron jobs. Rebuilding a failed host is
  # much easier with them, so pack them into a small archive on every run.
  echo "== Host configuration =="
  H=$(hostname -s)
  TMP=$(mktemp -d)
  mkdir -p "$TMP/info"
  # Proxmox cluster database, consistent copy if sqlite3 is available
  if command -v sqlite3 >/dev/null 2>&1 && [ -f /var/lib/pve-cluster/config.db ]; then
    sqlite3 /var/lib/pve-cluster/config.db ".backup '$TMP/info/config.db'" 2>/dev/null
  fi
  # inventory for rebuilding: versions, disks, pools, guests, network, USB devices
  {
    echo "### $(date -R)"
    for C in "pveversion -v" "uname -a" "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL" \
             "zpool status" "zfs list" "pvs" "vgs" "lvs" "pvesm status" "qm list" "pct list" \
             "ip -br addr" "ip route" "lsusb" "lspci -nn" "dpkg -l"; do
      echo; echo "### $C"
      sh -c "$C" 2>&1
    done
  } > "$TMP/info/inventory.txt"
  P=""
  for X in $HOST_PATHS; do [ -e "$X" ] && P="$P ${X#/}"; done   # relative to /
  A="${H}_$(date +%F_%H%M).tar.gz"
  # shellcheck disable=SC2086
  if tar -czf "$TMP/$A" --ignore-failed-read --warning=no-file-changed \
         --exclude=/var/lib/pve-cluster/config.db-wal --exclude=/var/lib/pve-cluster/config.db-shm \
         -C / ${P# } -C "$TMP" info 2>/dev/null || [ -s "$TMP/$A" ]; then
    mkdir -p "$MNT/host"
    if cp "$TMP/$A" "$MNT/host/"; then
      echo "$MNT/host/$A ($(du -h "$TMP/$A" | cut -f1))"
      # keep the newest $HOST_KEEP archives of this host
      ls -1 "$MNT/host/${H}"_*.tar.gz 2>/dev/null | sort -r | tail -n +"$((HOST_KEEP + 1))" | xargs -r rm --
    else
      echo "WARNING: copying the host archive to the Maxtor failed"
    fi
  else
    echo "WARNING: creating the host archive failed"
  fi
  rm -rf "$TMP"
fi

echo "== Archives on the Maxtor =="
ls -lh "$MNT"/dump/*.zst 2>/dev/null | awk '{print $5, $9}'
df -h "$MNT" | tail -1

umount "$MNT" 2>/dev/null
# Re-arm the automount, otherwise the next access only sees the empty local folder
# ("directory is expected to be a mount point but is not mounted").
systemctl restart "$(systemd-escape --path "$MNT").automount" 2>/dev/null
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
