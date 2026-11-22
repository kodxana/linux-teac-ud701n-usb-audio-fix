# UmbrelOS deployment notes

**Tested:** UmbrelOS (Debian 13), kernel `6.12.113+deb13-amd64`, UD-701N `0644:806b`.

This file documents the tested host-specific approach. It is **not** a universal install recipe.

## Why a regular module install is lost

UmbrelOS displays the following warning on terminal access: system modifications made for debugging do not persist between system restarts. The original driver loads very early (observed around 6.44s); `umbrel-custom-pre-start.service` executes much later (observed around 17.64s).

On the tested system, the wrapper `/opt/umbrel-custom-hooks/run-pre-start` executes `/home/umbrel/umbrel/custom-hooks/pre-start` if that file exists and is executable. The wrapper continues boot regardless of the hook's status.

## Guarded startup logic

The tested hook used the following safeguards:

1. `/home/umbrel/teac-driver-fix/disable-autoload` marker disables the hook.
2. Kernel version must equal `6.12.113+deb13-amd64`.
3. `modinfo -F vermagic` must match the running kernel.
4. No ALSA controls or PCM playback nodes may be held by audio apps (e.g. Roon RAATServer).
5. Every currently bound `snd-usb-audio` interface must belong to the TEAC USB ID `0644:806b`.
6. Unbind only the TEAC audio interfaces, unload `snd_usb_audio` without force, copy the prebuilt module into `/lib/modules/$KVER/updates/teac/`, run `depmod`, reload the module and rebind the interfaces.
7. If unload/reload fails, restore the stock module selection and attempt rebinding; never force removal.

The actual early boot environment, interface numbers, and services may be different on another installation. **Inspect your boot logs and hook implementation before adapting this.** In particular, this procedure is not suitable if the driver also serves other active USB audio hardware.

## Observed verification

After enabling the hook, a reboot produced:

```text
[TEAC FIX] Preparing patched driver for 6.12.113+deb13-amd64
[TEAC FIX] Selected module: /lib/modules/6.12.113+deb13-amd64/updates/teac/snd-usb-audio.ko
[TEAC FIX] Patched driver activation completed
```

Then `/usr/sbin/modinfo -n snd_usb_audio` selected the override and ALSA detected `UD701N`. The DAC's numeric ALSA card index changed across reloads, so use `hw:CARD=UD701N,DEV=0`, **not** `hw:2,0`.

## Disable / rollback

A hook designed with the documented disable marker can be disabled via:

```bash
touch /home/umbrel/teac-driver-fix/disable-autoload
```

After reboot, verify that `/usr/sbin/modinfo -n snd_usb_audio` selects the stock `.ko.xz` module. The runtime is not changed merely by creating the disable marker. Also ensure no separate persistent override was installed by another process.

## Kernel updates

**Do not reuse a `.ko` built for a different kernel.** Rebuild the patch against the new running kernel's exact source and headers. The guard should fail closed and leave the stock driver alone on a version mismatch.

## Security and stability

Do not force `rmmod` while Roon, Infinity Core, MPD, or another application owns `/dev/snd`. Never attempt a USB driver replacement during playback. An unsigned module will not load under enforced Secure Boot/module signature restrictions. A boot hook that unloads kernel drivers should be tested with physical access and a rollback plan.
