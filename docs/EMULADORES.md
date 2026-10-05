# Install DuckStation and PCSX2 on macOS

The PS1/2 app in this repository is only the launcher and catalog. DuckStation and PCSX2 are separate applications. The installer downloads official dependencies that are missing, but you still provide BIOS and games and finish each emulator's setup. Links and requirements were checked on **29/09/2026**; confirm the official sources when you update, because packages and requirements can change.

## Recommended path: use the launcher installer

After downloading the ZIP and extracting the whole folder, double-click **Instalar.command**. Or, after cloning, open Terminal in the `ps1-2-emulator` folder:

```bash
bash Instalar.command
```

This opens the native **PS1/2** setup window with a PS2-inspired theme. If Apple's Command Line Tools are missing, the startup first explains them in Terminal and offers to open Apple's installer with your consent. Complete that installation, then continue. In the setup window, check the destination, wait for the prerequisite check and click **Instalar**. It builds the launcher and downloads **only the emulators it does not find**. At the end, use the explicit buttons to open each app and finish its first setup.

For text-only installation use `bash install.sh`. For diagnosis without downloading, compiling or installing, use `bash install.sh --check`.

- Default destination: `/Applications`; the graphical assistant prefers an existing writable `~/Applications` if the system folder is not writable. The setup window lets you select another writable folder or create a personal **Applications** folder using **Nova Pasta**. The text-only equivalent is `mkdir -p "$HOME/Applications"` and then `bash install.sh --destination "$HOME/Applications"`.
- Sources: the official `latest` release of `stenzek/duckstation` and the latest stable release of `PCSX2/pcsx2`, through the GitHub API. The installer checks the SHA-256 from the API, the bundle ID and the signature before installing. It does not skip a failed check.
- Apps with the expected name and identity in `/Applications`, `~/Applications` or the chosen destination are kept. The script does not update existing emulators or change their settings.
- It does not install Homebrew, does not use `sudo`, does not restart the Mac, does not accept licenses or Rosetta, does not download games or BIOS, and does not clear quarantine on downloads. Apps open only when you choose their buttons or open them yourself. It does not clear the system icon cache or restart the Dock.

After installing, open **DuckStation** and **PCSX2** from Finder, finish the steps below and try one game in each. For clone instructions, launcher requirements, options and restoring a previous version, see [Detailed installation in the README](../README.md#detailed-installation).

If you prefer to install the emulators yourself, use the official sources below and run `bash install.sh --no-emulators` to install only the launcher.

## PS1 — DuckStation

### Manual download (skip if the installer already installed it)

1. Open the [official site](https://www.duckstation.org/) or the [official stable GitHub distribution](https://github.com/stenzek/duckstation/releases/tag/latest).
2. Download `duckstation-mac-release.zip` for macOS.
3. Unzip it in Finder and move **DuckStation.app** to **Applications**, so it lives at `/Applications/DuckStation.app`.

### First setup (also required after the installer)

1. Open the emulator once and finish the wizard. Point it at your BIOS and your PS1 library folder.
2. In the controller settings, select and map your controller. Mapping inside DuckStation is separate from the launcher buttons.
3. Open a game directly in DuckStation to confirm the setup, then use the launcher catalog.

The documented build is universal, for Intel and Apple Silicon, and requires **macOS Ventura 13.3 or later**. The BIOS does not come with the emulator and must be dumped from your own console. BIN/CUE, CHD, CCD and unencrypted PBP are among the documented formats. Keep every file that belongs to the same disc. [macOS install and requirements in the official README](https://github.com/stenzek/duckstation#macos).

DuckStation's minimum does not change the launcher's minimum: this repository's build requires **macOS 14+ and Apple Silicon**.

## PS2 — PCSX2

### Manual download (skip if the installer already installed it)

1. Open the [official downloads page](https://pcsx2.net/downloads/) and choose **macOS**. To start, prefer **Stable**. Nightly changes more often.
2. Extract the `.tar.xz` in Finder and move the app to **Applications**.
3. If the package name includes a version, use **PCSX2.app** so the path is `/Applications/PCSX2.app`, which is what the launcher expects.

### First setup (also required after the installer)

1. Open PCSX2 and finish the wizard: BIOS folder, PS2 library and controls.
2. If macOS asks for **Rosetta**, read and accept the installer the system shows, if you agree. This repository's script does not accept it for you.
3. Try a game directly in PCSX2 before using the launcher.

These steps follow the [official macOS install guide](https://pcsx2.net/docs/setup/running/). The documentation lists **macOS 11 and 8 GB of RAM as minimums**; higher tiers suggest 16 GB. The documented Mac build for M-series uses Rosetta 2. Performance depends on the game, the resolution and the settings: meeting the minimum does not guarantee full speed in every title. [Official PCSX2 requirements](https://pcsx2.net/docs/setup/requirements/).

Rosetta is an Apple component for running Intel apps on Apple Silicon. The launcher's ARM64 binary does not need it. Check [Apple's current guidance on Rosetta](https://support.apple.com/102527) before updating the system, especially on future macOS versions.

## BIOS and games

This repository contains no games or BIOS. Use files you are allowed to use, such as a BIOS dumped from your own console, copies of your own discs where that is permitted, and authorized homebrew.

- PS1: follow the BIOS notes in the [official DuckStation project](https://github.com/stenzek/duckstation).
- PS2: follow the [official BIOS dump guide](https://pcsx2.net/docs/setup/bios/) and the [disc guide](https://pcsx2.net/docs/setup/discs/), which includes notes for CDs and DVDs on macOS.

You do not need to reformat the SSD to install the launcher. Keep BIOS, memory cards, saves and games outside the Git folder. Neither the launcher nor the installer downloads or supplies a ready-made library. The installer does not change those files, and the launcher backup does not include them either: keep your own backup of your saves.

## Catalog folders and formats

The default folders are:

```text
/Volumes/Extreme SSD/Emulacao/PS1/Jogos
/Volumes/Extreme SSD/Emulacao/PS2/Jogos
```

To keep those folders, connect the SSD and allow access when macOS asks. To use another location, open **Game folders** in the launcher (or **⌘,**) and choose one folder for PS1 and one for PS2, on the Mac or on any external disk. The choice is saved on this Mac and loads only that console's catalog, including subfolders. You do not edit code or reinstall. **Restore default** returns to the original path above, including while offline. See [Libraries and covers in the README](../README.md#libraries-and-covers).

`--destination` changes where the apps are installed, not where the games are. The launcher reads the files where they are, without copying your library, and it does not change the library configured inside DuckStation or PCSX2. Configure the emulators as well if you want their own lists to use the same folder.

On a new machine the cache starts empty; cloning Git does not import another Mac's catalog. With the folder available, select PS1 or PS2 and press **T / △** to open the catalog. Inside the catalog, press **T / △** to reload the list and the covers. A local list for offline browsing exists only after the first successful load. To play, the files must be available. Games on the internal disk do not need an external SSD.

| Console | Extensions the launcher catalog considers |
|---|---|
| PS1 | `.cue`, `.ccd`, `.chd`, `.iso`, `.pbp`, `.img`, `.bin`, `.m3u` |
| PS2 | `.iso`, `.chd`, `.cso`, `.zso`, `.gz`, `.bin`, `.img`, `.mdf` |

This table describes the launcher's scanner, not a compatibility guarantee from the emulator. Showing up in the catalog does not prove that a file is intact or playable.

- ZIP, RAR and 7z must be extracted first and do not appear as games.
- CUE, CCD and M3U are included only when their parts exist inside the library.
- For PS1, keep the CUE and BIN tracks together. Use the disc or playlist entry, not a lone audio track. A folder of BIN tracks with no CUE still appears as one game: track 1.
- For PS2, PCSX2 does not read CUE/TOC directly. See the [official disc guide](https://pcsx2.net/docs/setup/discs/) for the right files for each dump method.
- For a cover, put a PNG, JPG or WebP in the game folder. The name `capa` works, and so does the only image in the folder. If the disc is inside `GAME`, the image can sit in the folder above. **Reload**, **R** or **R2 + L2** rereads games and covers. Folders such as Football or Fighting, created in the catalog, only organize the list: no file is moved.

## Common problems

- **`swiftc` or the SDK was not found:** open `Instalar.command` and follow the Apple tools guidance, or run `xcode-select --install`, finish the install and run `bash install.sh --check` again. Apple setup and any license confirmation remain your responsibility.
- **No permission to install in `/Applications`:** select another writable folder in the setup window, or use your home folder with `--destination "$HOME/Applications"` after creating it. Do not use `sudo` as a shortcut.
- **The Finder shortcut does not start:** keep it inside the complete extracted project folder. If macOS says Apple cannot verify it, confirm you downloaded this repository and trust the copy before using **System Settings → Privacy & Security → Open Anyway** for that file. Do not disable system protections. See [Apple's procedure](https://support.apple.com/102445).
- **“No such file or directory”:** do not reuse another person's absolute path. Open the actual extracted folder in Finder. For a trusted copy, you can type `bash` followed by a space in Terminal, drag the real `Instalar.command` file into that window and press Enter. The installer now checks all required inputs and names missing files before requesting tools or compiling; an incomplete ZIP must be downloaded and extracted again.
- **The setup reports an error:** open its details, review the log and use the retry action after fixing the cause. Avoid closing the installer mid-install; it prevents a normal close while files are being published. The log can contain local paths, so review it before sharing.
- **Download, SHA-256 or signature failure:** do not bypass the check. Confirm your connection, look at the official release and try again. A changed package may require an installer update. If the GitHub API rate-limits you, wait or install manually from the official source.
- **"Could not find DuckStation/PCSX2":** check the names and paths beside `PS1-2.app`, in `/Applications` or in `~/Applications`. The launcher searches those locations in that order, then checks the app registered with macOS, validating its identity and executable. Open each emulator once from Finder to finish its setup.
- **"Reading games and covers…" for a long time:** check whether macOS is waiting for you to allow access to the SSD.
- **Empty or stale library:** check the path in **Game folders**, disk access, and whether the games were extracted into that folder. If you moved the games or renamed the volume, choose the folder again. Open the catalog and press **T / △** for a full load. A new machine has no previous cache to show offline.
- **A game does not start in the emulator itself:** check the BIOS, the disc files and the setup in that emulator first. The launcher does not fix those problems.
- **The controller works in the launcher but not in the game:** configure it separately inside DuckStation or PCSX2.
- **An unexpected security warning:** confirm where the file came from. Do not turn off macOS protections or clear warnings on files from an unknown source as a general fix.

To build or install the launcher and run the tests, go back to the [README](../README.md).
