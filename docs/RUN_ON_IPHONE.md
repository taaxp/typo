# Run Typo on your iPhone

Typo is an iPhone and iPad app (iOS 26). It builds and launches in the iPhone simulator on GitHub's build machines. These steps put it on your own phone. You need a Mac with Xcode 26 and an Apple Developer account (paid), because Typo uses iCloud, an App Group (so the keyboard and share sheet see your library) and Keychain sharing.

## 1. One-time setup on your Mac

```bash
brew install xcodegen
```

Unzip the project (or `git clone https://github.com/taaxp/typo`), then open `project.yml` in a text editor and change these:

| Setting | What to put | Example |
|---|---|---|
| `DEVELOPMENT_TEAM` | Your Team ID (developer.apple.com › Membership details) | `ABCDE12345` |
| `BUNDLE_ID_PREFIX` | An ID you own. The app uses it as is; the extensions add `.keyboard`, `.share`, `.widgets`. | `com.yourname.typo` |
| `APP_GROUP_ID` | `group.` plus the same ID | `group.com.yourname.typo` |
| `ICLOUD_CONTAINER` | `iCloud.` plus the same ID | `iCloud.com.yourname.typo` |

## 2. Generate and open

```bash
cd Typo && xcodegen generate && open Typo.xcodeproj
```

## 3. Prepare the iPhone

1. Plug it in and tap **Trust**.
2. Settings › Privacy & Security › **Developer Mode** › on. The phone restarts.

## 4. Sign and run

1. In Xcode, pick the **Typo** scheme and your iPhone at the top.
2. Click the project, then for **each of the four targets** (Typo, TypoKeyboard, TypoShare, TypoWidgets) open **Signing & Capabilities** and choose your team. Leave "Automatically manage signing" on. Xcode creates the App Group and iCloud container for you.
3. Check the Typo target lists **App Groups**, **iCloud (CloudKit)**, **Keychain Sharing** and **Push Notifications**. Add any that are missing with **+ Capability**.
4. Press **⌘R**.
5. If iOS says "Untrusted Developer": Settings › General › VPN & Device Management › your name › Trust.

## 5. Turn on the keyboard

Settings › General › Keyboard › Keyboards › Add New Keyboard › **Typo**, then tap it and turn on **Allow Full Access** (needed so it can read your library and copy files).

## If something goes wrong

- **Signing error:** copy the red message from Xcode (the Issue navigator, ⌘5) and send it to me.
- **App closes on launch:** note what you tapped, and send me the crash text from Xcode's console.
- **iCloud sync shows "Not signed in":** sign in to iCloud on the phone, and make sure the iCloud container in `project.yml` matches the one Xcode created.

## What is and isn't tested

Tested: it builds with Xcode 26 and runs in the simulator (see the screenshots in the README). **Not yet tested on a real phone:** camera scanning, Face ID for the card vault, the keyboard with Full Access, Apple Intelligence, iCloud sync, Siri shortcuts, Spotlight and widgets. If one misbehaves, tell me which, and I'll fix it or remove it.

The Apple Watch app and the Mac app were removed to keep this simple.
