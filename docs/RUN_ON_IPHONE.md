# Run Typo on your iPhone (free Apple ID)

This is the **simple version** of Typo, and you don't need a paid developer account. It's the default `project.yml`: one app, no iCloud.

**What works:** saving snippets, links, photos, GIFs, videos and files; one-tap copy; tags; collections; search; templates and shortcuts; QR codes and guest Wi-Fi; scanning; the card vault; member cards; dictation; Apple Intelligence tools where your phone supports them. Everything is stored on the phone.

**What doesn't (needs a paid account):** the Typo keyboard, the share sheet, widgets and iCloud sync.

**Apple's free-account limits:** the app stops opening after **7 days** and you reinstall it from Xcode (plug in, press Run). You can have up to 3 apps installed this way.

## Steps

1. **Install the tools** on your Mac: Xcode 26 from the Mac App Store (open it once and accept the licence), then in Terminal:

   ```bash
   brew install xcodegen
   ```

2. **Add your Apple ID to Xcode:** Xcode › Settings › Accounts › **+** › Apple ID. A free "Personal Team" appears.
3. **Generate the project:**

   ```bash
   cd Typo && xcodegen generate && open Typo.xcodeproj
   ```

4. **Prepare the iPhone:** plug it in and tap **Trust**. Then Settings › Privacy & Security › **Developer Mode** › on. The phone restarts.
5. **Sign:** in Xcode click the blue **Typo** project at the top of the left list, choose the **Typo** target, open **Signing & Capabilities**, and set **Team** to your name (Personal Team).
6. **Run:** choose your iPhone at the top of the window and press **⌘R**.
7. **Trust the app:** if the phone says "Untrusted Developer", go to Settings › General › VPN & Device Management › your Apple ID › **Trust**.

The bundle ID is `com.asifazad.typo`. If Xcode says it can't register it or it's unavailable, change `BUNDLE_ID_PREFIX` in `project.yml` (for example `com.asifazad.typo2`), run `xcodegen generate` again, and press ⌘R.

## If something goes wrong

- **Any red error in Xcode:** open the Issue navigator (⌘5), copy the message, and send it to me.
- **App closes on launch:** note what you tapped, and send me the text from Xcode's console.

## Not yet tested on a real phone

It builds with Xcode 26 and runs in the simulator (see the README screenshots). I haven't been able to test a free-account install, camera scanning, Face ID, Apple Intelligence or Siri on a real device. If one misbehaves, tell me which, and I'll fix it or remove it.

## Later: the full version

When you join the paid Apple Developer Program, use the full project. It adds the keyboard, share sheet, widgets and iCloud sync.

1. In `project-full.yml`, set `DEVELOPMENT_TEAM` to your Team ID (developer.apple.com › Account › Membership details).
2. Generate it: `xcodegen generate --spec project-full.yml`.
3. In Xcode, choose your team for all four targets (Typo, TypoKeyboard, TypoShare, TypoWidgets) and check that App Groups, iCloud (CloudKit), Keychain Sharing and Push Notifications are listed. Run with ⌘R.
4. Turn on the keyboard: Settings › General › Keyboard › Keyboards › Add New Keyboard › Typo, then Allow Full Access.

The Apple Watch app and the Mac app were removed to keep Typo simple.
