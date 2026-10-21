# 9. Firmware & further reading

Most of the original resources are gone. These are the ones we found still online in 2026. We have **not** verified every statement on them – treat them as starting points.

## Firmware versions

| Version | What it is |
|---|---|
| **3.1.28** (`MSS_V_3_1_28.bin`, ~16 MB, download below) | Reported to be the last official firmware of the Shared Storage II itself. Fixes for the extended US daylight saving time rules, DLNA/UPnP certification, wrong capacity display in "Simple View". |
| **3.5.74** | Turns the box into a "Maxtor Central Axis" (Seagate's successor product). A Japanese blog author who replaced the internal disks deliberately stayed on 3.1.28 instead. |

**All guides in this repository were tested on firmware 3.1.28** (plus the community patch for SSH/telnet). Check your own version in the web interface before you change anything – on other versions paths and behaviour may differ. None of the steps here requires a firmware update.

## Installing the system on a completely blank disk

Our guides assume one working disk from which you copy the system ([guide 4](04-mirror-system.md)). If **both** original disks are dead, you have to put the firmware onto a new disk from scratch. People have reportedly done this by partitioning the new disk like the original layout (see the table in the [README](../README.md)), formatting partitions 5 and 6 as ext3, creating swap on partition 3, and writing the system from the firmware file onto partitions 1/2 with `dd` from a Linux PC. The Open MSS-II wiki describes the partition roles. We have not tested this route.

## Links

- **Open MSS-II wiki** (community firmware, partition layout, shell access): <https://scratchpad.fandom.com/wiki/Open_MSS-II>
- **Firmware 3.1.28 download** – Seagate's original URL `http://www.seagate.com/support/mss/mss_v_3_1_28.zip` is dead, but the Internet Archive kept a copy (April 2018):
  <https://web.archive.org/web/20180416115740id_/https://www.seagate.com/support/mss/mss_v_3_1_28.zip>
  The ZIP contains `MSS_V_3_1_28.bin` (about 16 MB). SHA-256 of the extracted `.bin`, downloaded from that archive link in October 2026:
  ```
  a3811b909f901167f32a1440c9c2d933f2948648381480b3bacb100727b6b2ef  MSS_V_3_1_28.bin
  ```
  Check your copy with `shasum -a 256 MSS_V_3_1_28.bin` (macOS) or `sha256sum MSS_V_3_1_28.bin` (Linux).
- **Firmware 3.1.28 release notes** (Data Recovery Salon, 2009): <https://www.datarecoverytools.co.uk/2009/08/04/firmware-update-v3128-for-maxtor-shared-storage-ii/> – its download button points to the dead Seagate URL above.
- **Japanese blog: replacing the internal HDD of a Shared Storage II** (2009, Blogger) – search for `Maxtor Shared Storage II 内蔵HDDを交換`
- **Seagate product overview** (specs, model numbers): <https://www.seagate.com/au/en/support/kb/maxtor-shared-storage-ii-product-overview-2105en/>

Found another source that still works? Please add it via pull request.
