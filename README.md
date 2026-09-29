<p align="center">
  <img src="docs/images/icon.png" width="112" alt="PS1/2 icon">
</p>

<h1 align="center">PS1/2</h1>

<p align="center">
  The PlayStation 1 and PlayStation 2 launcher for Mac.<br>
  A console-style menu that opens your games in DuckStation and PCSX2.
</p>

<p align="center">
  <a href="#download-and-install"><strong>Download and install</strong></a>
  &nbsp;·&nbsp;
  <a href="#a-look-at-the-app">See the app</a>
  &nbsp;·&nbsp;
  <a href="#full-guide">Full guide</a>
</p>

<p align="center"><strong>Version 4.12</strong> · Apple Silicon Mac · macOS 14 or later</p>

<p align="center">
  <img src="docs/images/menu.png" width="920" alt="Main menu: PlayStation 2 selected, with preview, controls and DualSense">
</p>

**PS1/2** is the app you open day to day. It shows both consoles, the preview, the catalog with covers, and the shortcut to play. The game itself runs in [DuckStation](https://www.duckstation.org/) (PS1) and [PCSX2](https://pcsx2.net/) (PS2). The installer puts the launcher in Applications and downloads those official emulators if they are not already on the Mac.

You bring the games and the BIOS. They stay in the folder you choose, on the Mac or on an external disk.

## A look at the app

The menu above is the home screen. PlayStation 2 is selected, the preview plays without opening the emulator, and the bar at the bottom shows keyboard and controller.

<table>
  <tr>
    <td width="50%" align="center">
      <img src="docs/images/catalog.png" alt="PS2 game catalog with FIFA Street 2, Need for Speed Underground 2 and Surf's Up">
    </td>
    <td width="50%" align="center">
      <img src="docs/images/folders.png" alt="Game folders panel, with one folder for PS1 and one for PS2">
    </td>
  </tr>
  <tr>
    <td align="center"><strong>Catalog</strong><br>Covers, game name and <em>Open in PCSX2</em>. Mouse, keyboard or controller.</td>
    <td align="center"><strong>Game folders</strong><br>One folder per console. It can be on the Mac or on an external disk.</td>
  </tr>
</table>

The three covers are a sample included in the project, so the catalog can look like this. The games themselves remain yours.

## Download and install

Private repository: the GitHub account needs access. On an Apple Silicon Mac with macOS 14 or later:

```bash
git clone https://github.com/rafaelferreiram/ps1-2-emulator.git
cd ps1-2-emulator
bash install.sh
open /Applications/PS1-2.app
```

Without Git: on GitHub, use **Code → Download ZIP**, unzip it and double-click **Instalar.command**.

The script asks for confirmation, installs the launcher, and adds DuckStation and PCSX2 only if they are missing. No Homebrew and no `sudo`.

1. Open each emulator once, provide your BIOS and try a game in it.
2. In the launcher, open **Game folders** and point at the PS1 folder and the PS2 folder.
3. Choose the console and press **T** or **△** to see the games. When the folder is available, that open already rereads the files, so new games show up immediately. **Reload**, **R** or **R2 + L2** repeat that read.

If the Mac asks for the compiler tools, run `xcode-select --install` and run the installer again. The step by step, the options, and what to do without write permission for `/Applications` are in the [full guide](#full-guide).

## In short

- PS1 and PS2 menu, with an animated preview that does not start the emulator.
- Catalog with covers, using the mouse, the keyboard or the controller.
- A separate folder for each console, on the Mac or on an external disk.
- The window follows the screen: on a MacBook and on another monitor, maximizing fills the available area.
- The Dock icon uses the current logo, with the rounded macOS shape, and stays visible after you quit the app.

| Action | Keyboard | Controller |
|---|---|---|
| Choose a console or game | Arrows | D-pad or left stick |
| Confirm | Enter | Cross |
| Back | Esc | Circle |
| Full screen | F | Square |
| See the games | T | Triangle |
| Reload games and covers | R, or the Reload button | R2 + L2, or Triangle inside the catalog |
| A–Z or Z–A order | A or Z, in the catalog | L1 or R1 |
| Folders, Reload and Disk | ↑ on the first game, then ←→ and Enter | ↑ on the first game, then ←→ and Cross. ↓ returns to the games |
| Catalog folders | P. C collapses the marked game's folder | Options opens. ↑↓ chooses the folder, ←→ the action, Cross confirms, Circle closes |

---

## Full guide

The repository is named `ps1-2-emulator`. The app is named **PS1/2** and the installed file is `PS1-2.app`, because `/` is a folder separator on macOS. Current version: **4.12, build 25**.

## Start here: clone, install and open

On an **Apple Silicon Mac with macOS 14 or later**, open Terminal. This repository is private: your GitHub account needs access and must be signed in for the clone.

```bash
git clone https://github.com/rafaelferreiram/ps1-2-emulator.git
cd ps1-2-emulator
bash install.sh
open /Applications/PS1-2.app
```

**Already cloned?** Enter the `ps1-2-emulator` folder and run only the last two commands. You can also open the folder in Finder and double-click **Instalar.command**, which runs the same installer in Terminal.

**Prefer a download without Git?** On GitHub, use **Code → Download ZIP**, unzip it in Finder, read this README and run **Instalar.command** in the extracted folder. The Command Line Tools are still required to compile. Because the repository is private, only accounts with access can download it. The installer does not depend on a `.git` folder being present.

If Git or the compiler tools are missing, run `xcode-select --install`, finish Apple's installer and try again. If `/Applications` is not writable, use [installing in your home folder](#install-without-write-permission-for-applications).

The script asks for confirmation, installs the launcher and downloads **DuckStation (PS1) and PCSX2 (PS2) only if they are missing**. It does not need Homebrew, does not use `sudo`, does not restart the Mac and does not open apps automatically. Then:

1. Open DuckStation and PCSX2 once, provide your BIOS and set up the controller and libraries in each wizard. If macOS asks for Rosetta for PCSX2, installing and accepting it is up to you.
2. Try a game directly in each emulator. The installer **does not download BIOS or games** and does not configure the emulators for you.
3. In the launcher, open **Game folders** (or **⌘,**) and choose the PS1 folder and the PS2 folder on the Mac or on an external disk. That choice loads that catalog. Select the console and press **T / △** to see the games. Inside the catalog, **T / △** reloads the list when you add or remove files. See [Libraries and covers](#libraries-and-covers).

**On another machine:** cloning or downloading the repository does not copy the catalog, cached covers, games, BIOS, saves or personal settings. You do not edit code to choose the library. The launcher opens without the SSD, but a new machine has an offline catalog only after a first load with the folder available. Besides the games, you provide the BIOS and finish the emulators' first setup. The installer does not skip that step.

## Features

- PS1/PS2 menu, matching controls and the PlayStation logo.
- **P1** (Player 1) marker on the preselected console, with a light-blue arcade look. It follows the mouse, keyboard and stick. It is only a visual cursor and does not change the controller port in the emulators. Local vector drawing, with no new images, fonts or downloads.
- Animated preview of the preselected console: a looping GIF, with no sound and **without starting the emulator**. It follows the mouse, keyboard and controller, and continues when the pointer leaves the card. The preview pauses when the launcher loses focus and respects macOS Reduce Motion.
- Startup GIF for the console before the emulator is opened or focused.
- A catalog per console, front covers, and navigation by mouse, keyboard and a compatible controller. The **Reload** button, the **R** key and **R2 + L2** reload games and covers. On the first game, ↑ marks A–Z, Folders, Reload and Disk; Cross confirms and ↓ returns to the games.
- Virtual folders, such as Football or Fighting, only group the list. The files stay where they are. Each group opens and closes on the same screen. Without folders, the catalog is one list.
- **Game folders**: an independent library per console, local or external, saved on this Mac. The original SSD stays the default and can be restored without moving files.
- A local cache of the catalog and thumbnails, shared with the loaded game's cover, to avoid rereading the SSD.
- Saved PS1 and PS2 catalogs restored at launch, including without the SSD, and a console-style notice when you try to play offline. The subtitle is “Playstation Retro Emulator”, without a “MAIN MENU” label.
- On/off indicator, time since the emulator opened, and the loaded game when it can be identified.
- Cover thumbnail beside the loaded game on the main menu: 36 px tall, keeping each console's aspect ratio. It uses the same covers as the catalog. If there is no safe match, it shows a disc icon. The lookup runs in the background when the game changes, without rereading the library every second.
- A normal request to quit the emulator, with confirmation. It does not force the app to close.
- The interface follows the size of the window and of the screen it is on. On a 14-inch MacBook and on other monitors, maximizing or using full screen enlarges the menu, the preview and the catalog to fill the available area.
- The Dock icon uses the current logo, with the rounded macOS shape, and stays after you quit the launcher. The install registers that copy and stops using an icon from backups or the Trash.

## Launcher requirements

| Dependency | Why it is needed |
|---|---|
| Apple Silicon Mac — M1 or later | The script compiles for `arm64`. Intel is not a target of this build. |
| macOS 14 or later | Minimum set in `Info.plist` and in the compiler. |
| Xcode Command Line Tools | Provides `swiftc`, the macOS SDK and the build tools. |
| Git | To clone the repository. Usually included with the Command Line Tools. |
| DuckStation and PCSX2 | External apps that run the games. |
| BIOS and images of your games | Configure them in the emulators, following their official documentation. |

It does not use Node.js, npm, Python, Homebrew, CocoaPods or external Swift packages. AppKit, SwiftUI, Foundation, Combine, GameController, ImageIO and CryptoKit are system frameworks. `build.sh` also uses macOS tools: `sips`, `ditto`, `xattr`, `codesign` and `plutil`.

The code was compiled and tested with Swift 6.4 on Apple Silicon. The declared minimum is macOS 14. Not every macOS or SDK version has been tested.

## Detailed installation

### 1. Prepare the environment

If you do not have the developer tools yet:

```bash
xcode-select --install
```

Finish the install on macOS. Then check:

```bash
xcode-select -p
xcrun --find swiftc
xcrun swiftc --version
git --version
```

Reference: [installing the Command Line Tools from Apple](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools).

### 2. Clone the private repository

You need to be signed in to GitHub with an account that has access. HTTPS example:

```bash
mkdir -p /Users/"$(whoami)"/Workspace/Personal
cd /Users/"$(whoami)"/Workspace/Personal
git clone https://github.com/rafaelferreiram/ps1-2-emulator.git
cd ps1-2-emulator
```

You can also use SSH if your key is already set up. Do not put tokens or passwords in the command, in the code or in the repository. The suggested local folder is `~/Workspace/Personal/ps1-2-emulator`.

### 3. Run the installer

From the repository root:

```bash
bash install.sh
```

The installer checks macOS, architecture and the Command Line Tools, shows the plan and asks for confirmation. It then builds the launcher with `build.sh` and installs it in `/Applications`. If the emulators are missing, it looks up the official releases of [DuckStation](https://github.com/stenzek/duckstation/releases/tag/latest) and [PCSX2](https://github.com/PCSX2/pcsx2/releases/latest), downloads the macOS packages and installs them in the same destination. For PCSX2 it uses the stable release, not a prerelease or Nightly.

Before installing a download, it checks the **SHA-256 reported by the official GitHub API**, the bundle identity and the signature. If the check fails or the required hash is not available, that install stops. There is no option to skip those checks. That does not replace macOS security warnings or the first launch.

The signature check confirms the app's integrity. It does not mean notarization or approval by Apple. DuckStation may use an ad hoc signature, and the launcher is built with a local ad hoc signature. Downloaded emulators keep quarantine so macOS can check them on first open.

- Existing DuckStation and PCSX2 apps in `/Applications`, `~/Applications` or the chosen destination are kept when they have the expected app name and bundle ID. The installer **does not update or overwrite them**. An install with another name may need a manual check.
- If the launcher is already installed, quit it before continuing. The previous version is stored in a hidden `.ps12-backup.*` folder at the destination. The backup path is printed in Terminal. It is not a backup of your saves.
- To return to the previous version, quit the launcher and move the `PS1-2.app` from the printed backup path back to the install destination. The emulators and saves do not need to be replaced.
- Games, BIOS, saves, memory cards, emulator settings and the SSD are not modified. You can run it again to reinstall the launcher and fill in missing dependencies.
- No app is opened automatically. There is no reboot, no automatic acceptance of licenses or Rosetta, no Homebrew install and no automatic removal of quarantine from downloads.
- On failure, Terminal prints the temporary diagnosis folder. On success, temporary downloads are removed. Launcher backups stay at the destination. If a copy fails for lack of space or permission, apps that were already installed successfully may remain: fix the cause and run it again.

Available options:

| Command | What it does |
|---|---|
| `bash install.sh` | Builds and installs the launcher and downloads missing emulators, after confirmation. |
| `bash install.sh --check` | Diagnosis without building, downloading or changing files. |
| `bash install.sh --no-emulators` | Builds and installs only the launcher. It does not download emulators. |
| `bash install.sh --destination "$HOME/Applications"` | Uses the home Applications folder, which must already exist. |
| `bash install.sh --yes` | Skips the script's confirmation. It does not accept licenses or macOS warnings. |

#### Install without write permission for Applications

Do not run the installer with `sudo`. Create your home Applications folder and choose that destination:

```bash
mkdir -p "$HOME/Applications"
bash install.sh --destination "$HOME/Applications"
open "$HOME/Applications/PS1-2.app"
```

Do not move the repository folder inside `PS1-2.app`. The installed app contains the executable and the resources needed to open the launcher. The library and the emulators stay outside it.

### 4. Open and prepare the emulators

For the default destination, open **Applications → PS1-2**, or run:

```bash
open /Applications/PS1-2.app
```

If you want, keep the icon in the Dock. After install, that icon stays the current logo even when the launcher is quit. See [the emulator guide](docs/EMULADORES.md) to set up BIOS, libraries, the controller and the first launch. At the default destination, the emulators are at:

```text
/Applications/DuckStation.app
/Applications/PCSX2.app
```

Try a game directly in the emulator first. The launcher does not configure BIOS, renderer, memory or controller mapping automatically.

### Build manually, without installing

For development or to inspect the bundle:

```bash
bash build.sh
```

The script generates the icon, copies the resources, compiles the native executable, applies a **local ad hoc signature** and validates the bundle. It does not download emulators or install the launcher in Applications. When it finishes, it prints a path similar to `/private/tmp/ps12-build.ABC123/PS1-2.app`. Use the real printed path to open or copy the app yourself. An Apple Developer certificate is not required for the local build. An ad hoc signature is not Apple notarization.

The default build uses a local temporary folder to avoid Finder or iCloud metadata that can interfere with signing. `cache/`, `MakeIcon` and `AppIcon.iconset/` are generated locally and ignored by Git. The app is not run with `swift run`: this project builds a macOS bundle directly with `build.sh`.

## Libraries and covers

The default folders remain these, outside the repository:

```text
/Volumes/Extreme SSD/Emulacao/
├── PS1/Jogos/
└── PS2/Jogos/
```

### Choose another folder, without editing code

1. Open **Game folders** in the launcher header or in the catalog. It is also in the **PS1/2 → Game folders…** menu, with the shortcut **⌘,**.
2. On the **PS1** or **PS2** card, click **Choose folder…**. Select any readable folder on internal storage or on an external disk and confirm **Use this folder**. The file picker is the native macOS one. Use the mouse or keyboard in it.
3. The launcher saves the choice and does a full load **of that console only**. It accepts one folder per console, including subfolders. It does not search the whole Mac. Choose the folder dedicated to the games, not the root of a disk.
4. Click **Done** and open the catalog. After adding games or covers, press **T / △** inside it to reload.

Cancelling the picker leaves everything as it was. **Restore default** returns to the original `Extreme SSD` folder and tries to recover its saved catalog, including while the disk is disconnected. If needed, reload with **T / △** when it is connected.

The choices stay in the app's local preferences, separate for PS1 and PS2, and survive quitting, reopening and updating the app. The launcher does not move or copy games and does not change BIOS, saves, memory cards or emulator settings. If you want the same library listed inside DuckStation or PCSX2, set the folder in their preferences too. `--destination` on the installer only changes where the apps are installed.

Official covers come from `~/Library/Application Support/DuckStation/covers` and `~/Library/Application Support/PCSX2/covers`, matched by the disc serial. An image in the game folder is used when the catalog does not have an official cover that belongs only to that game: PNG, JPG, JPEG or WebP. It can be named `capa`, `cover` or `front`, or it can be the only image beside the disc. If the game is inside a `GAME` subfolder, the image can sit in the folder above. Two discs that share a serial do not share the same art: the official cover stays with the game that matches the original name, and the other uses the image in its own folder.

On PS2, the cover shown is the front, in portrait. A single unfolded case image, with back, spine and front, is shown as the front only. If a `capa` file is also there, that file is the cover the catalog uses. Three front covers included in `assets/Covers/PS2` keep the presentation of those titles consistent.

The listing does not copy games. ZIP, RAR and 7z do not appear. Valid CUE/BIN sets are grouped, without listing each track as a game. A folder of BIN tracks with no CUE appears as one game: track 1. Later tracks stay part of the same disc and do not become separate games. Incomplete descriptors are left out, with a warning.

If macOS asks for access to the external volume, choose **Allow** to finish a full load or to open a game. While that prompt is waiting, “Loading the catalog…” may appear. No permission is bypassed automatically.

## Controls

| Action | Keyboard | Compatible controller |
|---|---|---|
| Select a console or game | Arrows | D-pad or left stick |
| Confirm / open | Enter | Cross |
| Back / cancel the launch | Esc | Circle |
| Full screen / window | F | Square |
| List the console's games | T | Triangle |
| Reload games and covers | R, or the Reload button | R2 + L2. Inside the catalog, Triangle also reloads |
| Catalog order | A for A–Z, Z for Z–A | L1 for A–Z, R1 for Z–A |
| Folders, Reload and Disk | ↑ on the first game, then ←→ and Enter. ↓ returns to the games | ↑ on the first game, then ←→ and Cross. ↓ returns to the games. L1, R1, Options and △ remain shortcuts |
| Catalog folders | P opens. C collapses or shows the marked game's folder | Options opens the panel. ↑↓ chooses the folder, ←→ the action, Cross confirms, Circle closes |
| Set game folders | ⌘, or the header button | Open it with the button, then the D-pad or stick chooses PS1/PS2, Cross opens the picker and Circle goes back |
| Quit the launcher | ⌘Q | — |

With the mouse, hovering PS1 or PS2 preselects the console. Clicking starts the launch. The preview of the preselected console continues even without hover and also follows the keyboard or controller arrows. It is silent, uses the local GIFs and does not download anything. Controller mapping inside the games remains each emulator's job.

The left stick selects in four directions. On the menu, each tilt changes the console once: return it to center before repeating in the same direction. In the catalog, left and right move one game and up and down move one row. At the end of a folder, the selection continues in the open folder beside it. Holding repeats after 450 ms, every 140 ms. The dead zone and diagonal settling avoid moves from small wobble. After changing screens, using a button or returning from another app, return the stick to center to arm it again. The right stick does not navigate.

A–Z and Z–A reorder the same list. On the controller, ↑ on the first game marks A–Z, Folders, Reload and Disk. ←→ changes the option, Cross confirms and ↓ returns to the games. L1, R1, OPTIONS and △ remain shortcuts. **Folders** creates groups such as Football or Fighting and only organizes the catalog: no file is moved. Without folders, the screen stays one list. With folders, each group has a line that collapses and shows the games, and anything left out appears in Library.

The **Reload** button reloads the list and the covers of the console in focus. The **R** key and **R2 + L2** do the same, on the menu or in the catalog. Inside the catalog, **T / △** also reloads. R2 and L2 must be held together. Releasing only one trigger does not fire it again.

Cross, Circle, Square, Triangle, R2, L2, the D-pad and the stick act only while the launcher is focused. Controller mapping inside the games remains each emulator's job.

## Sessions and limits

- “On” means the emulator app is open. It does not guarantee that a game is running.
- The counter measures time since the emulator opened, including pauses and time spent in its menu.
- “Game loaded” is inferred from disc images the process has open. The launcher does not tell playing from paused and does not use old logs to guess.
- Images outside the library, files held entirely in memory, or denied access can prevent identification.
- Switching games while another session is loaded is blocked. Finish the session in the emulator itself.
- If DuckStation is open with no identified game, the launcher asks for confirmation to quit it normally and reopen it with the chosen game. It never force-quits.
- Quitting the launcher does not save games and does not quit the emulators automatically.

## Game and cover cache

The cache lives in `~/Library/Caches/local.rafael.centraldejogos/`, on the Mac's internal storage. It stores only the game index and cover thumbnails. It does not copy ISOs, BINs, BIOS or saves and does not use extra space on the games SSD.

- `Catalog/`: saves the **last successful full load**, with titles, paths, covers and the CUE/CCD/M3U disc grouping. With the disk disconnected, opening the catalog reuses that index, from memory or from the local disk, without scanning the library. It keeps up to eight indexes in memory and up to eight files / 16 MiB on disk (4 MiB maximum per file).
- When the launcher starts, both catalogs are restored from the local cache, even without the SSD. If there is no saved cache yet, that restore does not scan. You need to connect the SSD and open or reload the catalog once. Do not delete the cache if you want to keep offline browsing.
- A full load happens when you open the catalog with the folder available, on the first open without a valid cache, when you confirm a different folder, or when you use **Reload**, **R**, **R2 + L2** or **△ / T**. Games and covers added since the last visit are included in that read. Merely returning to the app, or connecting and disconnecting the disk without opening the catalog, does not start a scan. If the update fails, the last saved list for that library stays visible, with a warning.
- The index is separate per **console and library path**. Changing folders removes the previous list from the screen immediately. An old task cannot put it back. Returning to the default library can recover its cache, within the limits above. No choice deletes game or cover files.
- `Thumbnails/`: 320 px thumbnails for the catalog and 108 px for the menu, tied to the same saved load. RAM and disk hits do not consult the original cover. The catalog prepares both sizes in the background. If a thumbnail does not exist yet or was removed by the cache limit, it tries to read only that cover, without rereading the games. Without access to the cover, it shows a placeholder.
- The cover cache budget is 32 MiB of images kept in memory and 64 MiB / 256 files on disk. Visible views may keep extra images. That budget is not the app's total memory use. Automatic cleanup removes only files from this cache.
- With the external disk disconnected, you can browse the last list and the covers already saved. **Only when you choose “Open game”** does the launcher check the selected files. If the volume is disconnected, it shows a notice with the volume name and the game title, without starting the emulator. Cross/Enter or Circle/Esc closes the notice and keeps the catalog. After reconnecting, choose the game again: there is no automatic launch. Games in a local folder do not depend on another console's SSD. The cache does not contain the games. Removed files or files without permission get their own message.
- Corrupt or unavailable cache files are ignored and recreated. If you need to clear it by hand, quit the launcher and move only that cache folder to the Trash. Never delete the game, BIOS or save folders.

This optimization is for the launcher and the catalog. It does not change speed, FPS, settings, saves or the internal behavior of DuckStation and PCSX2.

## Tests

From the project root:

```bash
bash tests/run-monitor-tests.sh
bash tests/run-catalog-tests.sh
bash tests/run-catalog-organization-tests.sh
bash tests/run-hover-animation-tests.sh
bash tests/run-now-playing-tests.sh
bash tests/run-launcher-preview-tests.sh
bash tests/run-controller-input-tests.sh
bash tests/run-launch-check-tests.sh
bash tests/run-cache-tests.sh
bash tests/run-cover-cache-tests.sh
bash tests/run-installer-tests.sh
bash tests/run-library-settings-tests.sh
bash tests/run-responsive-layout-tests.sh
```

These tests use local fixtures and the included GIFs. They do not need to download games or BIOS, and they do not start emulators. The suites cover the session monitor, animations, the catalog, snapshots without a scan, offline browsing, a failed update that keeps the saved list, validation of the chosen game, an exact match between the open disc and the cover (including CUE/CCD/M3U) and six compact thumbnail layouts. The layout test writes a temporary preview with fake data for visual inspection.

The folder tests use temporary preferences and directories. They cover persistence, validation, offline restore, isolation between consoles and libraries, and late results from earlier loads. The installer tests use isolated scenarios, without installing real emulators or replacing apps in `/Applications`. `bash install.sh --check` can check your machine's prerequisites before you install.

Optional, only on a machine with the emulators and SSD set up: a read inventory of the real libraries:

```bash
bash tests/run-catalog-tests.sh --installed --front-covers "$PWD/assets/Covers"
```

That prints game paths in Terminal. Do not share the output if it contains data you do not want to publish. The tests do not prove that every title is playable and do not replace a physical controller test.

To compare a full read, the in-memory cache and the persistent cache against the installed library:

```bash
bash tests/run-cache-benchmark.sh
```

The benchmark does not start emulators or change games. It writes its test cache in a temporary folder, removed when it finishes. Times vary with the SSD, the library and macOS's own cache.

Local measurement of version 4.6 on 29/09/2026 (catalog lookup, not total interface time; average of five in-memory lookups):

| Library | Full read | In-memory cache | Cache after recreating the loader |
|---|---:|---:|---:|
| PS1, 5 games | 885 ms | 0.3 ms | 1.9 ms |
| PS2, 14 games | 416 ms | 0.5 ms | 2.2 ms |

The 19 covers, saved at both sizes (38 thumbnails), used 3.3 MB in the test disk cache and about 6.7 MB decoded in the memory cache. In-memory lookups and reopening from the persistent cache made **zero new scans and zero library metadata checks**. The first read still builds the index. The gain is in later reuse. No game was copied.

## Layout

```text
PS12.swift                 Menu, windows, state and emulator launch
ResponsiveLayout.swift     Interface scale for the window and the screen
ControllerInput.swift      Controller input
EmulatorMonitor.swift      Process monitor and loaded game
GameCatalog.swift          Library scan and cover selection
CatalogOrganization.swift  A–Z/Z–A order and virtual catalog folders
GameLaunchCheck.swift      Validation of only the chosen game and its disc files
StorageNoticeView.swift    Disconnected-disk notice with a console-inspired look
LibrarySettings.swift      Persistent PS1/PS2 folders and volume metadata
LibrarySettingsView.swift  Panel to choose or restore the libraries
CatalogCache.swift         Last successful full load and lookups that do not scan the SSD
CoverImageCache.swift      Shared thumbnails with RAM and disk limits
GameCatalogView.swift      Catalog interface
NowPlayingGameView.swift   Async thumbnail of the loaded game
StartupAnimation.swift     GIF before the emulator opens
HoverAnimation.swift       Looping decorative preview
MakeIcon.swift             App icon generation
Info.plist                 Bundle identity and version
build.sh                   Compile and local signature
install.sh                 Install the launcher and missing official dependencies
Instalar.command           Finder shortcut that runs the installer in Terminal
scripts/installer-lib.sh   Official downloads, validation and publishing the apps
scripts/MoveApp.swift      Exclusive, safe rename during install
assets/                    Logo, photos, GIFs and three front covers
tests/                     Automated tests
docs/EMULADORES.md         Downloads and first setup
Creditos.txt               Sources and attribution for the visual assets
```

## Credits and use

A personal project, with no official link to Sony, DuckStation or PCSX2. Third-party assets keep their own rights. Keeping the repository private does not change those rights. See [Creditos.txt](Creditos.txt) for the origin of the controllers, logo, GIFs and covers. No open redistribution license was assigned to the third-party assets.

Do not include ROMs, BIOS, saves, credentials, personal backups or emulator builds in this repository. `.gitignore` helps avoid accidental additions, but it does not replace reviewing the files before a commit.
