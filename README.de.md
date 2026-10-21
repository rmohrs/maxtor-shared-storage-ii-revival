# Maxtor Shared Storage II – Wiederbelebung (deutsche Kurzfassung)

Eine alte **Maxtor Shared Storage II** wieder in Betrieb nehmen: Platten prüfen, RAID 1 neu aufbauen, Dateisysteme reparieren, dauerhaften SSH-Zugang einrichten und die Box als Backup-Ziel für Linux bzw. Proxmox VE nutzen.

Getestet mit **Firmware 3.1.28** (letzte Version der Shared Storage II) plus Community-Patch für SSH.

Die ausführlichen Anleitungen sind auf Englisch (damit sie möglichst vielen helfen), die Befehle sind aber dieselben. Diese Seite fasst das Wichtigste auf Deutsch zusammen.

> ⚠️ **Auf eigene Gefahr.** Du arbeitest als `root` auf einem 20 Jahre alten System. Ein falscher `dd`- oder `fdisk`-Befehl löscht Daten. Erst alles lesen, dann tippen.

## Die wichtigsten Erkenntnisse

- **Gebrauchte Ersatzplatten vorher testen:** `smartctl -t long /dev/sdb` – `smartctl` ist auf der Box vorhanden. Unsere erste Ersatzplatte ist beim Resync mit Lesefehlern ausgestiegen.
- **Das RAID baut sich nicht von selbst neu auf.** Neue Platte mit `fdisk` genau wie die alte partitionieren (kein `sfdisk` vorhanden), dann `mdadm /dev/md0 --add /dev/sdb6`.
- **Nur die Datenpartition ist gespiegelt.** Das System (sda1, sda2, sda5) liegt nur auf der ersten Platte – einmal per `dd` auf die zweite kopieren.
- **Die Firmware baut `/etc` bei jedem Start neu.** Ein mit `passwd` gesetztes Root-Passwort ist nach dem Neustart weg. Lösung: SSH-Schlüssel in `/root/.ssh`.
- **Einmal `e2fsck` laufen lassen.** Die Konfigurationspartition sda2 war bei uns beschädigt (*aborted journal*).
- **`poweroff` schaltet die Box nicht aus.** Es hält nur den Kernel an: Ping antwortet noch, SSH und Weboberfläche sind tot, die Taste reagiert nicht mehr – dann hilft nur der Stecker. Richtig ist die Front-Tasten-Aktion der Firmware: `/usr/sbin/mxotoolbox -f`. **Niemals `mxotoolbox -r`** (Reset-Taste: setzt das Admin-Passwort zurück und startet die Ersteinrichtung).
- **Nur SMB1.** Linux-Mount mit `vers=1.0,sec=ntlmv2,nounix,noperm` und unbedingt `soft` + systemd-Automount, sonst hängen Prozesse auf dem Server, wenn die Maxtor aus ist.
- **Kein Finder-Zugriff mit aktuellem macOS.** Die Box kündigt sich nicht als Dateiserver per Bonjour an, und SMB1 klappt mit aktuellem macOS ohnehin nicht. Zugriff über Linux oder Dateien per SSH kopieren.
- **Kein Proxmox Backup Server** auf der Maxtor (smbd stürzt ab, ext3 erlaubt max. ~32.000 Unterordner) – einfache `vzdump`-Backups funktionieren gut.
- **Geschwindigkeit:** RAID-Resync ~75 MB/s, Schreiben per SMB1 ~10 MB/s.

## Anleitungen

1. [Shell-Zugang & dauerhafter SSH-Login](docs/01-shell-access.md)
2. [Platten prüfen (SMART)](docs/02-check-disks.md)
3. [Platte tauschen & RAID 1 neu aufbauen](docs/03-raid-rebuild.md)
4. [Systempartitionen auf die zweite Platte kopieren](docs/04-mirror-system.md)
5. [Dateisysteme reparieren (e2fsck)](docs/05-repair-filesystems.md)
6. [Freigaben aufräumen](docs/06-shares.md)
7. [Zugriff von Linux / macOS / Windows (SMB1)](docs/07-clients.md)
8. [Backup-Ziel für Proxmox VE](docs/08-proxmox-backup.md)
9. [Firmware & weiterführende Links](docs/09-firmware-and-links.md)

Tipp für deutsche Mac-Tastaturen: `~` = **Wahltaste + N**, dann Leertaste. `/` = **Shift + 7**.

Fragen, Korrekturen, Erfahrungen mit anderen Plattengrößen oder Firmware-Versionen: gern als Issue oder Pull Request.
