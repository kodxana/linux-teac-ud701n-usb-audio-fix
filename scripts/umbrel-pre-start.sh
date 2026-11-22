#!/usr/bin/env bash
# Experimental UmbrelOS pre-start hook for the tested machine/kernel.
# Review and adapt before use. This swaps a kernel module and will disrupt audio.
set -euo pipefail

KVER="$(uname -r)"
EXPECTED="6.12.113+deb13-amd64"
SRC="/home/umbrel/teac-driver-fix/linux-source-6.12/sound/usb/snd-usb-audio.ko"
DST="/lib/modules/$KVER/updates/teac/snd-usb-audio.ko"
DISABLE="/home/umbrel/teac-driver-fix/disable-autoload"
DRIVER="/sys/bus/usb/drivers/snd-usb-audio"
log() { echo "[TEAC FIX] $*"; }

[[ ! -e "$DISABLE" ]] || { log "Disabled by user"; exit 0; }
[[ "$KVER" == "$EXPECTED" ]] || { log "Kernel mismatch; skipping"; exit 0; }
[[ -f "$SRC" && -d "$DRIVER" ]] || { log "Missing module or driver; skipping"; exit 0; }
[[ "$(/usr/sbin/modinfo -F vermagic "$SRC")" == "$KVER "* ]] || {
  log "ABI mismatch; skipping"; exit 0;
}

# Conservative: skip if ANY ALSA device is open.
if /usr/bin/fuser -s /dev/snd/controlC* /dev/snd/pcmC*p 2>/dev/null; then
  log "Audio device in use; skipping"
  exit 0
fi

interfaces=()
for path in "$DRIVER"/*:*; do
  [[ -L "$path" ]] || continue
  iface="${path##*/}"
  usbdev="$(dirname "$(readlink -f "$path")")"
  [[ -r "$usbdev/idVendor" && -r "$usbdev/idProduct" ]] || {
    log "Cannot identify bound USB device; skipping"; exit 0;
  }
  [[ "$(cat "$usbdev/idVendor")" == "0644" &&
     "$(cat "$usbdev/idProduct")" == "806b" ]] || {
    log "Different USB audio device is bound; skipping"; exit 0;
  }
  interfaces+=("$iface")
done

rebind() {
  for iface in "${interfaces[@]}"; do
    if [[ -d "/sys/bus/usb/devices/$iface" &&
          ! -L "/sys/bus/usb/devices/$iface/driver" ]]; then
      echo "$iface" > "$DRIVER/bind" || log "Rebind failed: $iface"
    fi
  done
}

log "Preparing patched driver for $KVER"
for iface in "${interfaces[@]}"; do
  if ! echo "$iface" > "$DRIVER/unbind"; then
    log "Unbind failed; recovering"; rebind; exit 0
  fi
done

if ! /usr/sbin/modprobe -r snd_usb_audio; then
  log "Driver busy; recovering"; rebind; exit 0
fi

install -D -m 644 "$SRC" "$DST"
/usr/sbin/depmod -a "$KVER"

if ! /usr/sbin/modprobe snd_usb_audio; then
  log "Patched load failed; restoring stock selection"
  rm -f "$DST"
  /usr/sbin/depmod -a "$KVER"
  /usr/sbin/modprobe snd_usb_audio || true
  rebind
  exit 0
fi

rebind
log "Selected module: $(/usr/sbin/modinfo -n snd_usb_audio)"
log "Patched driver activation completed"
