# Technical analysis and reproduction

## Hardware and software

- TEAC UD-701N USB ID `0644:806b`
- Debian 13 (UmbrelOS), kernel `6.12.113+deb13-amd64`
- Linux ALSA `snd-usb-audio`
- USB interface 1:
  - altset 1: `S16_LE`
  - altset 2: `S24_3LE`
  - altset 3: **`S32_LE DSD_U32_BE`** (both formats advertised)

## Fault

Original `sound/usb/quirks.c` mode selection:

```c
if (fmt->formats & SNDRV_PCM_FMTBIT_DSD_U32_BE) {
    /* send vendor DSD mode selection, wValue=1 */
} else {
    /* send PCM mode selection, wValue=0 */
}
```

Because `fmt->formats` is an alternate-setting **capability mask**, this selects DSD whenever the alternate setting *supports* DSD. It cannot tell whether the current stream requested `S32_LE`.

The endpoint stores the actual format in `ep->cur_format = params_format(params)`. The patch threads that value through `snd_usb_select_mode_quirk()` and tests `pcm_format == SNDRV_PCM_FORMAT_DSD_U32_BE`.

## Actual usbmon control-transfer evidence

Format: `bmRequestType bRequest wValue wIndex wLength`; request `41 00` is vendor-specific, interface-recipient, host-to-device.

```text
WORKING 24-bit PCM:
  01 0b 0000 0001 0000  # interface 1 altset 0
  41 00 0000 0001 0000  # vendor PCM mode (value 0)
  01 0b 0002 0001 0000  # interface 1 altset 2

BROKEN STOCK 32-bit PCM:
  01 0b 0000 0001 0000  # interface 1 altset 0
  41 00 0001 0001 0000  # vendor DSD mode (value 1) -- WRONG
  01 0b 0003 0001 0000  # interface 1 altset 3

PATCHED 32-bit PCM:
  01 0b 0000 0001 0000  # interface 1 altset 0
  41 00 0000 0001 0000  # vendor PCM mode (value 0) -- CORRECT
  01 0b 0003 0001 0000  # interface 1 altset 3

PATCHED NATIVE DSD512:
  41 00 0001 0001 0000  # vendor DSD mode (value 1) -- CORRECT
```

The unit's display and clean playback corroborated the corrected 32-bit PCM path at 96 kHz and 192 kHz. Native DSD512 was heard cleanly with MPD 0.24.4. The DSF header itself reported `sample_rate=22579200`, 2 channels and 1 bit/sample. MPD's `audio_format=dsd512:2` and ALSA `DSD_U32_BE` at `705600` frames/s match that DSD512 source.

## Diagnostic commands

```bash
lsusb -d 0644:806b
cat /proc/asound/cards
cat /proc/asound/card*/stream0
sudo speaker-test -D hw:CARD=UD701N,DEV=0 -c 2 -r 96000 -F S32_LE -t sine -l 1
sudo journalctl -k -b --no-pager | grep -Ei 'usb|clock|freq|error -'
```

The last test **can produce loud noise with an unpatched driver**. Mute the connected equipment first.

For debugging control commands on bus 1, load `usbmon` (`sudo /usr/sbin/modprobe usbmon`) and capture `/sys/kernel/debug/usb/usbmon/1u`, filtering to the current USB device number returned by `lsusb`. Device numbers change on reconnect.

## Scope and caveats

- This fixes a demonstrated mistake in format-mode selection. It does **not** guarantee other USB clock/control failures cannot occur.
- Not tested across all TEAC models, kernels, PCM rates up to 768 kHz, or DSD64/128/256. 
- Linux drivers and API signatures evolve; this patch may require rebasing.
- The patch is not upstream merged or maintained as a full DKMS project.
