#!/usr/bin/env python3
"""Build the local pairing app and the shared icon. No store publishing or new credentials."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parent
project = source.parent
asset = project / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
subprocess.run(["swift", str(source / "make_icon.swift"), str(asset)], check=True)
app = Path.home() / "Applications/Card Scout Mac.app"
contents = app / "Contents"
(contents / "MacOS").mkdir(parents=True, exist_ok=True)
(contents / "Resources").mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix="card-scout-mac-build-") as temporary:
    binary = Path(temporary) / "CardScoutMac"
    subprocess.run(["swiftc", "-parse-as-library", "-O", "-target", "arm64-apple-macos14.0", str(source / "Companion.swift"), "-o", str(binary)], check=True)
    shutil.copyfile(binary, contents / "MacOS/CardScoutMac")
    (contents / "MacOS/CardScoutMac").chmod(0o755)
    icons = Path(temporary) / "AppIcon.iconset"; icons.mkdir()
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{size}x{size}" + ("@2x" if scale == 2 else "") + ".png"
            subprocess.run(["sips", "-z", str(size * scale), str(size * scale), str(asset), "--out", str(icons / name)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["iconutil", "-c", "icns", str(icons), "-o", str(contents / "Resources/AppIcon.icns")], check=True)
(contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.tobiaslatta.cardscout.companion", "CFBundleName": "Card Scout Mac", "CFBundleDisplayName": "Card Scout Mac", "CFBundleExecutable": "CardScoutMac", "CFBundleIconFile": "AppIcon", "CFBundlePackageType": "APPL", "CFBundleVersion": "14", "CFBundleShortVersionString": "1.1", "LSMinimumSystemVersion": "14.0", "NSHighResolutionCapable": True}))
subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
print("Installed:", app)
