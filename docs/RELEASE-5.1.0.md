# PS1/2 5.1.0 — guided DMG installer

> **Superseded by [5.1.1](https://github.com/rafaelferreiram/ps1-2-emulator/releases/tag/v5.1.1).** This DMG has a confirmed Finder metadata packaging defect that can fail strict signature validation during preflight. Download the corrected 5.1.1 installer instead. The notes below describe the original release; re-downloading 5.1.0 will not fix the defect.

**Apple Silicon (M1 or later) · macOS 14 or later · build 28**

## Download and install

Download **[PS1-2-Installer-5.1.0-arm64.dmg](https://github.com/rafaelferreiram/ps1-2-emulator/releases/download/v5.1.0/PS1-2-Installer-5.1.0-arm64.dmg)** from this release (about 4.5 MB). The automatic **Source code** archives are for local development, not the precompiled installer.

1. Open the DMG, then open **Install PS1-2.app** inside it.
2. Review the Mac check and destination, then click **Install**. The current assistant interface is in Portuguese; this button is labelled **Instalar**.
3. Wait for the bundled PS1/2 launcher and any missing official emulators to be installed.
4. Open DuckStation and PCSX2 using the completion buttons, provide your own authorized BIOS and games, and configure the emulators and controller.
5. Open PS1/2, choose your game folders, then quit the installer and eject the DMG.

The DMG does not require Terminal, Git, Homebrew, Xcode or Command Line Tools. An internet connection is needed for missing emulator downloads. Intel Macs are not supported by this launcher build. macOS may request Rosetta for an Intel emulator; any license acceptance remains your decision.

[Full installation guide](https://github.com/rafaelferreiram/ps1-2-emulator/blob/v5.1.0/README.md#download-and-install) · [SHA-256 checksum file](https://github.com/rafaelferreiram/ps1-2-emulator/releases/download/v5.1.0/PS1-2-Installer-5.1.0-arm64.dmg.sha256)

## What's included

- The compiled launcher, PS2-inspired native setup assistant and standalone installation helpers.
- Dynamic bundle-relative paths that do not depend on a username, Git checkout or writable source folder.
- Downloads of missing DuckStation and PCSX2 apps from their official releases, with SHA-256, bundle identity, signature and architecture checks.
- A native architecture inspector, removing the developer-tools requirement from packaged installation.
- Preservation of existing emulators, backups before replacing the launcher, and no changes to your games, BIOS, saves or emulator settings.
- The full source and tests, an English README, and a repeatable developer-side DMG build script.

## Security and setup requirements

**This release is ad hoc signed, not Developer ID signed or notarized by Apple.** The DMG does not bypass Gatekeeper. If macOS blocks it, verify the download and trust the project before using **System Settings → Privacy & Security → Open Anyway** for the specific app. Installed apps may require their own first-open confirmation. Never disable Gatekeeper or clear quarantine globally. [Apple's guidance](https://support.apple.com/en-us/102445).

Games, BIOS, saves and external emulators are not bundled in the DMG. Missing emulators are downloaded during installation. Initial BIOS/controller setup is still required, and installing the launcher does not guarantee compatibility or full speed for every game.

The project is not affiliated with Sony, DuckStation or PCSX2. Third-party artwork retains its own rights; see the repository's credits.

## Validation and known limits

- Eight relevant suites passed **589 assertions**.
- Apple's disk-image checksum verification passed for the final DMG.
- The exact DMG contents were independently extracted, their nested code signatures verified, and the real launcher installed into an isolated temporary folder with developer-tool lookup unavailable.
- The setup assistant opened without a source-path argument; official emulator downloads passed their hash, signature and architecture checks.
- **Disk-image mounting and a fresh-download Gatekeeper first-open flow could not be tested in the build environment.** This release has not been validated on every supported Mac or macOS version. No real emulator or user game was launched as part of these tests.

SHA-256 of `PS1-2-Installer-5.1.0-arm64.dmg`:

```text
1000c56fbaaaf45a7c1f5e9f6bddb9bd81204621179068d811555b781e0bc49c
```
