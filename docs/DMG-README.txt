PS1/2 — PlayStation Retro Emulator

GET STARTED

1. Open Install PS1-2.app from this disk image.
2. Review the Mac check and installation folder, then click Install.
3. Wait for the launcher and any missing official emulators to be installed.
4. Use the completion buttons to configure DuckStation (PS1) and PCSX2 (PS2).
5. Open PS1/2 and choose your game folders on the Mac or an external disk.
6. Quit the installer and eject this disk image when finished.

The assistant's interface is currently in Portuguese. The Install button is
labelled "Instalar" and Choose folder is labelled "Escolher pasta".

REQUIREMENTS

Apple Silicon (M1 or later), macOS 14 or later, and internet access to download
missing emulators. This DMG contains the compiled launcher and installer; you
do not need Terminal, Git, Homebrew, Xcode or Command Line Tools to use it.
The installer does not support Intel Macs. macOS may request Rosetta for an
Intel emulator; any Apple license acceptance remains your decision.

SECURITY NOTICE

This build has a local ad hoc signature, not a Developer ID signature or Apple
notarization. The DMG does not remove macOS security warnings. If macOS blocks
the installer, verify that you obtained it from the project's official GitHub
release and trust it before using System Settings > Privacy & Security > Open
Anyway for that app. Never disable Gatekeeper or clear quarantine globally.
Installed apps may require their own first-open confirmation.

Apple's guidance: https://support.apple.com/en-us/102445
Project: https://github.com/rafaelferreiram/ps1-2-emulator

WHAT IS AND IS NOT INSTALLED

PS1/2 is a launcher/catalog; games run in DuckStation or PCSX2. Missing emulators
are downloaded from their official releases and checked before installation.
Existing emulators are preserved. Updating the launcher keeps a backup of the
previous app, with its location shown in the details. Games, saves, BIOS and
emulator settings are not moved, replaced or included in the DMG.

Supply your own authorized BIOS and game files and finish the initial emulator
configuration. The installer does not download games or BIOS, accept licenses,
restart the Mac, or open other apps without a button click.

If the default Applications folder is not writable, use the folder picker to
choose a writable folder or create Applications inside your personal folder.
Keep this disk image mounted until installation finishes. If anything fails,
use the assistant's details and Copy log action; review personal paths before
sharing a log. Retry after fixing the reported cause.

UPGRADING FROM INSTALLER 5.1.0

Version 5.1.1 fixes a disk-image packaging defect that could report
"InspectMachO: resource fork, Finder information, or similar detritus not allowed".
Quit the old installer and eject its image before opening the new DMG.
You do not need to clear quarantine or disable macOS security for this fix.
