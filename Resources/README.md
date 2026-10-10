# App icon

`AppIcon-source.png` is the editable 1024 × 1024 PNG source. Regenerate the
committed `AppIcon.icns` with `bash script/build_icon.sh` after changing it.
The script uses the macOS tools `sips` and `iconutil` to create the standard
16, 32, 128, 256 and 512 point icon sizes at 1× and 2×. Temporary files are
removed automatically.

Both development and release builds embed `AppIcon.icns` and reference it in
`Info.plist`. Release verification checks that the bundled icon matches this
source asset byte for byte.
