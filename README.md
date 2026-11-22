# TEAC UD-701N Linux USB audio PCM/DSD mode fix

**Experimental Linux `snd-usb-audio` patch, tested on a TEAC UD-701N (`0644:806b`).**

On Debian kernel `6.12.113+deb13-amd64`, requesting **32-bit PCM (`S32_LE`)** over USB incorrectly selected the DAC's **native DSD mode**. The DAC displayed DSD 3.0M and produced noise. The same USB alternate setting advertises both `S32_LE` and `DSD_U32_BE`.

The driver's `snd_usb_select_mode_quirk()` checks the *formats supported by the alternate setting*, not the *format selected for playback*. The [patch](patches/linux-6.12-teac-ud701n.patch) passes `ep->cur_format` to the mode selection helper and uses it to distinguish PCM from native DSD.

> **Experimental, kernel-version-specific.** No prebuilt kernel modules are distributed. Do not install the patch blindly on a different kernel. USB audio errors can result in **very loud digital noise**; mute your amp/headphones before testing.

## Evidence

| Test | Stock driver | Patched driver |
| --- | --- | --- |
| PCM 24-bit / 96 kHz (`S24_3LE`) | Clean, PCM mode | Clean |
| PCM 32-bit / 96 kHz (`S32_LE`) | Noise; DAC shows DSD | Clean; DAC shows PCM 96 kHz |
| PCM 32-bit / 192 kHz (`S32_LE`) | Not validated | Clean; DAC shows PCM 192 kHz |
| Native stereo DSD512 (`DSD_U32_BE`) | Not fully validated | Correct DSD mode command; clean audio in MPD |
| PCM ↔ DSD transitions | Not fully validated | Some transitions tested; not a full regression suite |

Observed vendor control transfers on USB bus 1 for TEAC `0644:806b`:
- **Stock, 32-bit PCM:** `41 00 0001 0001 0000` (mode value 1, DSD).
- **Patched, 32-bit PCM:** `41 00 0000 0001 0000` (mode value 0, PCM).
- **Patched, native DSD512:** `41 00 0001 0001 0000` (mode value 1, DSD).

Test system: MINISFORUM UM890 Pro; UmbrelOS on Debian 13; Linux `6.12.113+deb13-amd64`; latest TEAC firmware as reported by tester. **A DSF header check confirmed the test recording was actually stereo DSD512 at 22.5792 MHz**, despite an earlier misleading FFprobe display. The testing included MPD 0.24.4 and ALSA `speaker-test`.

This is a **targeted mode-selection fix**. It does not guarantee every PCM/DSD sample rate, every USB host, or every player is stable. An unrelated USB clock error and an MPD configuration retry loop were observed during experimentation.

## Build (on a matching Debian kernel)

1. Obtain the **exact matching Linux source** and headers for your running kernel. The patch was applied to Debian Linux 6.12.113-1 source.
2. From the source root, apply `patch -p1 < /path/to/linux-6.12-teac-ud701n.patch`.
3. Run:

```bash
make -C "/lib/modules/$(uname -r)/build" M="$PWD/sound/usb" -j2 modules
/usr/sbin/modinfo -F vermagic sound/usb/snd-usb-audio.ko
```

The generated module must match the running kernel's ABI and dependency symbols. If the build fails, do not load it.

## Controlled testing

On a test host, stop audio services, disconnect the DAC, unload the stock driver with `sudo /usr/sbin/modprobe -r snd_usb_audio` (never force it), ensure dependencies including `mc` and `snd_usbmidi_lib` are loaded, and load the built module using `insmod /path/to/snd-usb-audio.ko`. Reconnect the DAC and test at muted/low volume.

```bash
sudo speaker-test -D hw:CARD=UD701N,DEV=0 -c 2 -r 96000 -F S32_LE -t sine -l 1
sudo speaker-test -D hw:CARD=UD701N,DEV=0 -c 2 -r 192000 -F S32_LE -t sine -l 1
```

Verify the TEAC displays **PCM**, not DSD. For native DSD testing, use a native DSD-capable player and inspect `/proc/asound/card*/pcm*p/sub*/hw_params`; DoP is not the same as native DSD. Do not confuse the ALSA DSD word/frame rate with the DSD bit clock: `DSD_U32_BE` at 705600 frames/s represents DSD512 at 22.5792 MHz.

## UmbrelOS persistence

UmbrelOS restores system files at reboot, so copying the module to `/lib/modules` manually is **not persistent**. The tested platform exposed `/opt/umbrel-custom-hooks/run-pre-start` which executes the persistent `/home/umbrel/umbrel/custom-hooks/pre-start` before `umbrel.service`. The stock module was registered ~6 seconds into boot, and the hook ran ~18 seconds into boot. That means **restoring the module alone is not enough**: the already-loaded module must be safely replaced *before audio apps start*.

See [UmbrelOS deployment notes](docs/umbrelos.md). We deliberately do not provide a universal unattended auto-swap installer: kernel changes and device consumers vary. The hook must skip on kernel mismatch, missing build, other bound USB audio devices, and busy audio devices. Never force module removal.

## Rollback

For a temporary replacement, unplug the DAC, stop audio apps, and run:

```bash
sudo /usr/sbin/modprobe -r snd_usb_audio
sudo /usr/sbin/modprobe snd_usb_audio
```

The second command loads whatever module currently has priority on disk. To restore stock selection, **first** remove the patched `updates/teac/snd-usb-audio.ko` override (if installed) and run `sudo /usr/sbin/depmod -a`; then reload or reboot. On UmbrelOS, a persistent pre-start hook must also be disabled, or it will reinstall the override at boot.

## Upstreaming

This patch is a candidate for upstream review by the Linux ALSA USB audio maintainers. It has been built and tested with one TEAC UD-701N, but it has **not** undergone upstream review or broad hardware regression testing.

Linux-derived patch content follows the licensing terms of the applicable Linux kernel source. No official TEAC or Linux endorsement is implied.
