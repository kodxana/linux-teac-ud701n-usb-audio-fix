#!/usr/bin/env bash
# Build only; never installs or loads the resulting kernel module.
set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/extracted/linux-source-6.12" >&2
  echo "Source must exactly match your running Debian kernel." >&2
  exit 2
}
[[ $# -eq 1 ]] || usage
source_dir="$(realpath "$1")"
patch_file="$(realpath "$(dirname "$0")/../patches/linux-6.12-teac-ud701n.patch")"
kernel="$(uname -r)"
headers="/lib/modules/$kernel/build"

[[ -d "$headers" && -f "$source_dir/sound/usb/quirks.c" ]] || {
  echo "Missing headers or source." >&2; exit 1;
}
[[ "$kernel" == "6.12.113+deb13-amd64" ]] || {
  echo "Patch has only been tested on 6.12.113+deb13-amd64; refusing automatic build." >&2
  exit 1
}
if patch --dry-run -d "$source_dir" -p1 < "$patch_file"; then
  patch -d "$source_dir" -p1 < "$patch_file"
elif grep -q 'pcm_format == SNDRV_PCM_FORMAT_DSD_U32_BE' "$source_dir/sound/usb/quirks.c"; then
  echo "Patch appears already applied; proceeding."
else
  echo "Patch does not apply cleanly. Check source version; no build performed." >&2
  exit 1
fi
make -C "$headers" M="$source_dir/sound/usb" -j2 modules
module="$source_dir/sound/usb/snd-usb-audio.ko"
[[ -f "$module" ]] || { echo "Build did not produce module." >&2; exit 1; }
vermagic="$(/usr/sbin/modinfo -F vermagic "$module")"
[[ "$vermagic" == "$kernel "* ]] || { echo "ABI mismatch: $vermagic" >&2; exit 1; }
printf 'Built %s\nvermagic: %s\nSHA256: ' "$module" "$vermagic"
sha256sum "$module"
echo "No driver installed. Follow README for controlled testing."
