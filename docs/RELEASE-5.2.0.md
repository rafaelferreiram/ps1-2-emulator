# PS1/2 5.2.0 — Portable SSD covers

**Apple Silicon (M1 or later) · macOS 14 or later · build 30**

## Download and install

Download **[PS1-2-Installer-5.2.0-arm64.dmg](https://github.com/rafaelferreiram/ps1-2-emulator/releases/download/v5.2.0/PS1-2-Installer-5.2.0-arm64.dmg)**. Quit PS1/2 and any older installer, eject its image, then open the new DMG. Double-click **Install PS1-2.app** and click **Instalar** after preflight finishes.

The DMG includes the compiled launcher and setup assistant. Missing DuckStation and PCSX2 apps are downloaded from their official releases. No Terminal, Git, Homebrew, Xcode or Command Line Tools are needed. Existing emulators are preserved, and the previous launcher is backed up when replaced. Games, BIOS, saves and personal settings are not included or changed.

[Full installation guide](https://github.com/rafaelferreiram/ps1-2-emulator/blob/v5.2.0/README.md#download-and-install) · [SHA-256 checksum](https://github.com/rafaelferreiram/ps1-2-emulator/releases/download/v5.2.0/PS1-2-Installer-5.2.0-arm64.dmg.sha256)

## What changed

- **Portable covers:** the central reads a `Capas` folder inside each selected PS1 or PS2 game-library folder. The images travel with the SSD instead of depending on a particular Mac's emulator artwork directory.
- **Reliable matching:** prefer the complete game filename stem plus PNG, JPG, JPEG or WebP. Separate filenames keep mods distinct when they reuse a disc serial; ambiguous names are not guessed. PS2 images must be portrait front covers, not unfolded cases.
- **Local cache retained:** loaded catalogs and thumbnails stay available for offline browsing on that Mac. Refresh detects new or changed portable images; warm browsing does not repeatedly scan the SSD.
- **Existing fallbacks preserved:** bundled, emulator-local and eligible nearby artwork are still used when no valid, unambiguous portable cover is found.
- The release retains the **5.1.1 DMG signature/metadata fix**, strict checks and quarantine handling.

## Use the same SSD on another Mac

1. Keep `Capas` inside each game folder, for example `PS1/Jogos/Capas` and `PS2/Jogos/Capas`.
2. Copy the actual images there, using each game's complete filename without its disc extension. For example, `Space Jam (USA).cue` uses `Space Jam (USA).jpg`. Retain serial prefixes and version suffixes when present. Symlinked artwork is ignored.
3. Install **5.2.0 or later** on the other Mac. Select each parent `Jogos` folder in the central's game-folder settings, not `Capas` itself.
4. Open each console's catalog and choose **Atualizar / R / Triangle**. No old-Mac cache, database or emulator covers are needed for filename-matched images.

The disk can have a different name or mount path as long as the correct game folder is selected. These folders affect the **central's catalog and now-playing artwork**, not DuckStation or PCSX2's own artwork settings. Version 5.1.1 and earlier do not automatically read `Capas`. Covers are not downloaded or migrated automatically, and the personal cover collection used for testing is not distributed with this release.

## Validation and limits

The release passed **65 portable-cover assertions**, **55 cover-cache checks**, **127 launcher integration assertions** and **20 mounted-DMG checks**. Existing catalog, catalog-cache and now-playing tests also passed. A fresh-Mac simulation of the connected libraries resolved **11/11 PS1 and 18/18 PS2 covers** from the SSD without emulator artwork, a database, bundled fronts or old cache. The copied images were byte/hash-verified and visually reviewed. Regression fixtures cover moved roots, ambiguity, invalid images, symlinks, in-place changes, refresh and offline thumbnails.

The exact DMG passed checksum and HFS metadata validation. Mounted through Finder, its nested signatures validated and its launcher installed into an isolated temporary destination with developer-tool lookup unavailable. The setup assistant reached its ready-to-install screen. No real apps, games, BIOS or saves were replaced during these checks.

This release is **ad hoc signed, not Developer ID signed or Apple-notarized**. Security confirmations can still appear. Only if you trust this project's download, follow [Apple's first-open guidance](https://support.apple.com/en-us/102445) for the specific blocked app. Do not disable macOS security.

**A physical second Mac and a fresh-download Gatekeeper/App Translocation flow on a clean Mac have not been tested.** These checks do not guarantee every Mac or game; the other Mac still needs this update and a catalog refresh. Games and BIOS remain the user's responsibility.

SHA-256 of `PS1-2-Installer-5.2.0-arm64.dmg`:

```text
370f2bba3d79e7e95c8e6cb1ab17f606c442ab25e4c8ce38d3a64560cacb1a6b
```
