# PS1/2 5.1.1 — DMG signature-check fix

**Apple Silicon (M1 or later) · macOS 14 or later · build 29**

## Download and install

Download **[PS1-2-Installer-5.1.1-arm64.dmg](https://github.com/rafaelferreiram/ps1-2-emulator/releases/download/v5.1.1/PS1-2-Installer-5.1.1-arm64.dmg)**. Quit any older installer and eject its disk image first. Open the new DMG, then **Install PS1-2.app** inside it and click **Instalar** after preflight finishes.

The DMG includes the compiled launcher and setup assistant; missing DuckStation and PCSX2 apps are downloaded from their official releases. No Terminal, Git, Homebrew, Xcode or Command Line Tools are needed. Games and BIOS are not included; provide your own authorized files and configure the emulators and controller. Existing emulators, games, saves and settings are preserved.

[Full installation guide](https://github.com/rafaelferreiram/ps1-2-emulator/blob/v5.1.1/README.md#download-and-install) · [SHA-256 checksum](https://github.com/rafaelferreiram/ps1-2-emulator/releases/download/v5.1.1/PS1-2-Installer-5.1.1-arm64.dmg.sha256)

## What changed

Version 5.1.0 could stop at preflight with:

```text
InspectMachO: resource fork, Finder information, or similar detritus not allowed
```

The disk-image creation tool added Finder icon-position metadata to signed files after signature verification. This was a packaging defect, not evidence that your download was corrupted. Re-downloading 5.1.0 does not fix it.

The build now normalizes only the exact generated metadata in its private HFS+ image and audits the filesystem again after decoding the final compressed DMG. The developer-only tool is not shipped in the installer. Executable contents and code signatures remain unchanged; unexpected metadata fails the build. Runtime signature checks remain strict. Nothing disables Gatekeeper, clears quarantine or re-signs apps on your Mac.

## Security and validation limits

This release is **ad hoc signed, not Developer ID signed or Apple-notarized**. Security confirmations can still appear. Only if you trust the official download, follow [Apple's first-open guidance](https://support.apple.com/en-us/102445) for the specific blocked app. Do not disable macOS security.

**726 assertions across ten suites passed**, including 117 HFS metadata checks and 20 mounted-DMG installation checks. The regression tests reproduce the original Finder metadata error, check the normalization and preservation of signed bytes, and reject malformed images. An independent byte comparison confirmed that only 164 generated coordinate bytes changed across the 41 installer entries. The compressed image passed Apple's checksum verification and the final filesystem metadata audit.

The actual 5.1.1 DMG was mounted through Finder. Its nested signatures validated, and the bundled launcher installed into an isolated temporary folder with developer-tool lookup unavailable and quarantine preserved. The setup assistant also opened from the mounted image and reached its ready-to-install state. No real apps, emulators, games or saves were replaced.

**A fresh-download Gatekeeper/App Translocation flow on a clean Mac has not been tested.** These checks do not promise compatibility with every Mac or game, or removal of Apple's security confirmations.

SHA-256 of `PS1-2-Installer-5.1.1-arm64.dmg`:

```text
a5b4274a6b21ba46a65a1de70cbb158348bfe7b61cd568a558303479be4e3c15
```
