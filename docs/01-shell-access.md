# 1. Shell access & permanent SSH login

The stock firmware has no shell. To do anything in these guides you need **root shell access** to the box.

## Getting a shell at all

We used a **community-patched firmware** that adds:

- a `dropbear` SSH server,
- a telnet daemon (`utelnetd`),
- a service list in the web interface to switch these on and off.

The community project for this was **Open MSS-II** – its wiki is still online at [scratchpad.fandom.com/wiki/Open_MSS-II](https://scratchpad.fandom.com/wiki/Open_MSS-II). We cannot vouch for any download linked from there; judge the source yourself. Flashing firmware is at your own risk. See also [Firmware & further reading](09-firmware-and-links.md).

Once you have a root shell (telnet, netcat or SSH), the prompt looks like this:

```
MSS:~ #
```

## Connecting with SSH from a modern computer

The old dropbear only speaks outdated algorithms. A current OpenSSH client refuses it unless you allow them explicitly:

```sh
ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 \
    -oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa \
    -oCiphers=+aes128-cbc root@<MAXTOR_IP>
```

To avoid typing this every time, put [`examples/ssh_config.example`](../examples/ssh_config.example) into `~/.ssh/config` (create the file if it does not exist, then `chmod 600 ~/.ssh/config`). Afterwards `ssh maxtor` is enough.

> macOS, German keyboard: `~` is **Option + N**, then space. `/` is **Shift + 7**.

## Why the root password keeps disappearing

The firmware **rebuilds `/etc` on every boot** (check the timestamps with `ls -la /`: `etc` has the date of the last boot). So `/etc/passwd` and `/etc/shadow` are overwritten, and a password you set with `passwd` is lost after the next reboot. On our box the regenerated root hash was an MD5 hash with an **empty salt** (`$1$$…`) – a sign that the firmware writes it itself.

`/root`, however, is an ordinary directory on the root partition and **survives reboots**. So the fix is an SSH key.

## Permanent login with an SSH key

On your computer (old dropbear only understands RSA – do **not** use ed25519):

```sh
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa_maxtor -N ''
cat ~/.ssh/id_rsa_maxtor.pub | ssh maxtor \
  'mkdir -p /root/.ssh && cat >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys'
```

You will be asked for the (current) root password one last time. Then add the key to the `Host maxtor` block in `~/.ssh/config`:

```
    IdentityFile ~/.ssh/id_rsa_maxtor
```

Test that it really works without a password:

```sh
ssh -o PasswordAuthentication=no maxtor echo ok
```

Then reboot the box (`ssh maxtor reboot`), wait 2–3 minutes and run the test again. If it still prints `ok`, the key survives reboots.

## Clean up

Once SSH with a key works reliably, switch **telnet (`utelnetd`) off** in the service list of the web interface – it sends everything, including passwords, in clear text. Keep it on until the SSH key has survived a reboot, otherwise you may lock yourself out.

## Switching the box off correctly

**Do not use `poweroff` or `halt`.** They only stop the kernel – the box stays powered, answers ping, but SSH, web interface and even the power button are dead. Only pulling the plug helps then.

The box has a small power controller that the firmware talks to. The front button is handled by the daemon `btnsd`, which calls:

```sh
/usr/sbin/mxotoolbox -f     # front button action: sync, stop all processes, reboot into "wait for button"
```

With the boot loader setting *Wait for button press* = ON (`mxoparam -a`), the box then really switches off (fan and button light off) and starts again when you press the front button. From your computer:

```sh
ssh maxtor /usr/sbin/mxotoolbox -f
```

The SSH connection drops – that is expected.

> ⚠️ **Never run `mxotoolbox -r`.** That is the reset-button action: it sets `firsttime`, clears the admin password and starts the first-time setup.

Useful, harmless: `mxoparam -a` shows the boot loader settings (U-Boot version, wait-for-button, watchdog, boot partition, boot fail counters).

## Never edit the wrong disk

From here on, many commands write to raw disks. Make it a habit to read every `dd`, `fdisk` and `mdadm` line twice:

- `if=` is the **source**, `of=` is the **target**.
- `sda` is normally the disk in the first bay, `sdb` the one in the second bay. Verify with `fdisk -l /dev/sda` and `fdisk -l /dev/sdb` before writing anything.
