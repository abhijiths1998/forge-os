#!/usr/bin/env bash
# Copy the rendered Forge Glass assets (generate.py -> out/) into the
# archiso profile. Re-run after changing generate.py.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${here}/out"
fs="${here}/../../profile/airootfs/usr/share"

resize() { # src dst size
    python3 -c 'import sys; from PIL import Image
im = Image.open(sys.argv[1]); s = int(sys.argv[3])
im.resize((s, s), Image.LANCZOS).save(sys.argv[2], optimize=True)' "$@"
}

# Desktop wallpaper package (Plasma picks images_dark/ under a dark scheme).
install -Dm644 "${out}/wallpaper-light-3840x2160.png" "${fs}/wallpapers/ForgeGlass/contents/images/3840x2160.png"
install -Dm644 "${out}/wallpaper-dark-3840x2160.png" "${fs}/wallpapers/ForgeGlass/contents/images_dark/3840x2160.png"
python3 -c 'import sys; from PIL import Image
Image.open(sys.argv[1]).resize((640, 360), Image.LANCZOS).save(sys.argv[2], optimize=True)' \
    "${out}/wallpaper-light-1920x1080.png" "${fs}/wallpapers/ForgeGlass/contents/screenshot.png"

# GRUB background (forge-postinstall.sh copies it into /boot/grub). Dark,
# so GRUB's white menu text stays readable on it.
install -Dm644 "${out}/wallpaper-dark-1920x1080.png" "${fs}/backgrounds/forge-os/wallpaper.png"

# Logos.
install -Dm644 "${out}/emblem-gradient.png" "${fs}/pixmaps/forge-os-emblem.png"
resize "${out}/logo-tile-light.png" "${fs}/pixmaps/forge-os-logo-tile.png" 512
mkdir -p "${fs}/plasma/look-and-feel/org.forgeos.glass/contents/splash/images"
resize "${out}/logo-tile-light.png" "${fs}/plasma/look-and-feel/org.forgeos.glass/contents/splash/images/logo.png" 384
resize "${out}/logo-tile-light.png" "${fs}/sddm/themes/forge-glass/logo.png" 192

# Plymouth.
ply="${fs}/plymouth/themes/forge-os"
install -Dm644 "${out}/lockup-light.png" "${ply}/logo.png"
install -Dm644 "${out}/wallpaper-light-1920x1080.png" "${ply}/background.png"
install -Dm644 "${out}/progress_box.png" "${ply}/progress_box.png"
install -Dm644 "${out}/progress_bar.png" "${ply}/progress_bar.png"

# Calamares.
cal="${here}/../../profile/airootfs/etc/calamares/branding/forge-os"
resize "${out}/logo-tile-light.png" "${cal}/forge-os-logo.png" 256
install -Dm644 "${out}/wallpaper-light-1920x1080.png" "${cal}/forge-os-wallpaper.png"

echo "Forge Glass assets installed into profile/airootfs."
