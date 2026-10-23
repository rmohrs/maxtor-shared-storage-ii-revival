#!/bin/bash
# fritzbox-backup – save the configuration of an AVM FRITZ!Box to a local folder
#
# Runs on any Linux host (e.g. the Proxmox host), needs only curl.
# The FRITZ!Box cannot write backups to a network share itself, so this host
# pulls the configuration via TR-064 and keeps it locally. maxtor-backup then
# copies the folder to the Maxtor (EXTRA_DIRS) whenever the box is switched on.
#
# Setup: see docs/10-fritzbox-backup.md
#   - FRITZ!Box: "Allow access for applications" (TR-064) enabled
#   - FRITZ!Box user with the right "FRITZ!Box settings"
#   - credentials file (chmod 600), default /root/.fritz-cred:
#       FRITZ_USER=<FRITZ_USER>
#       FRITZ_PASS=<FRITZ_PASSWORD>
#       EXPORT_PASS=<EXPORT_PASSWORD>   # needed to restore the file later!

# ---- adjust these -----------------------------------------------------------
FB="<FRITZBOX_IP>"            # IP address of the FRITZ!Box, e.g. 192.168.178.1
CRED="/root/.fritz-cred"      # credentials file
DIR="/root/fritzbox-backups"  # where the backups are kept
KEEP=10                       # number of backups to keep
NAME="fritzbox"               # file name prefix, e.g. fritzbox-7490
# -----------------------------------------------------------------------------

set -euo pipefail

case "$FB" in
  "<"*) echo "Please set FB=<your FRITZ!Box IP> at the top of $0"; exit 2 ;;
esac
[ -r "$CRED" ] || { echo "ERROR: credentials file $CRED missing"; exit 1; }
# shellcheck disable=SC1090
source "$CRED"

# escape characters that would break the SOAP XML
xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
PW_XML=$(printf '%s' "$EXPORT_PASS" | xml_escape)

mkdir -p "$DIR"
chmod 700 "$DIR"

# 1. ask the FRITZ!Box for a configuration file -> returns a download URL
RESP=$(curl -s --max-time 30 --digest -u "$FRITZ_USER:$FRITZ_PASS" \
  "http://$FB:49000/upnp/control/deviceconfig" \
  -H 'Content-Type: text/xml; charset="utf-8"' \
  -H 'SoapAction: urn:dslforum-org:service:DeviceConfig:1#X_AVM-DE_GetConfigFile' \
  --data-binary "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">
<s:Body><u:X_AVM-DE_GetConfigFile xmlns:u=\"urn:dslforum-org:service:DeviceConfig:1\">
<NewX_AVM-DE_Password>$PW_XML</NewX_AVM-DE_Password>
</u:X_AVM-DE_GetConfigFile></s:Body></s:Envelope>") || true

URL=$(printf '%s' "$RESP" | sed -n 's:.*<NewX_AVM-DE_ConfigFileUrl>\(.*\)</NewX_AVM-DE_ConfigFileUrl>.*:\1:p')
if [ -z "$URL" ]; then
  echo "ERROR: no download URL from the FRITZ!Box."
  echo "Check: TR-064 enabled, user name/password, user right 'FRITZ!Box settings'."
  printf '%s\n' "$RESP" | grep -o '<errorDescription>[^<]*' | sed 's/<errorDescription>/FRITZ!Box says: /' || true
  exit 1
fi

# 2. download it
FILE="$DIR/${NAME}_$(date +%F_%H%M).export"
curl -s --max-time 60 --digest -u "$FRITZ_USER:$FRITZ_PASS" "$URL" -o "$FILE"

if ! head -1 "$FILE" | grep -q 'FRITZ!Box Configuration File'; then
  echo "ERROR: downloaded file does not look like a FRITZ!Box configuration: $FILE"
  exit 1
fi
chmod 600 "$FILE"
echo "Saved: $FILE ($(du -h "$FILE" | cut -f1))"

# 3. keep only the newest $KEEP files
ls -1t "$DIR"/"$NAME"_*.export | tail -n +"$((KEEP + 1))" | xargs -r rm --
