# 6. Clean up shares

The firmware keeps its share list on the configuration partition (`sda2`). Samba's config is generated from it at `/usr/lib/smb.conf`. Every share is a folder directly under `/share`:

```sh
grep -i -E '^\[|path' /usr/lib/smb.conf
```

```
[config]
path = /share/config
[Offentlich]
path = /share/Offentlich
[backup]
path = /share/backup
...
```

- `config` is used internally by the firmware – leave it alone.
- `Offentlich` / `Public` (depending on the language) is the default public share. It **cannot be deleted** (the button is greyed out). You can only *unshare* it ("Freigabe aufheben"); the folder stays.

## After a fresh file system

If you recreated `/share` ([guide 3](03-raid-rebuild.md), 5b), the web interface still lists the old shares, but their folders no longer exist. Recreate the folders first so the web interface can delete them cleanly:

```sh
mkdir -p /share/config /share/<OLD_SHARE_1> /share/<OLD_SHARE_2>
chmod 777 /share/Offentlich 2>/dev/null
```

Then, in the web interface:

1. Delete the shares you no longer need.
2. Delete and recreate the share you want to use (e.g. `backup`) and give your user full access – that way the firmware sets the permissions itself.

Check the result:

```sh
ls -la /share
grep -i -E '^\[|path' /usr/lib/smb.conf
```

Leftover empty folders can be removed with `rmdir /share/<NAME>`.

After changing shares, refresh the copy of the configuration partition on the second disk ([guide 4](04-mirror-system.md), step 2).
