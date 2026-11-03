# Preparing for TestFlight

The project is configured for distribution, but nothing has been uploaded. These steps need an Apple Developer account.

## Already done

- Bundle ID `io.howcan.emojimatch`, version 1.0, build 1 (change the bundle ID if you prefer another)
- iPhone only, portrait only, iOS 17+
- 1024×1024 opaque app icon (regenerate with `swift scripts/generate_app_icon.swift`)
- `ITSAppUsesNonExemptEncryption = NO`, so no export compliance prompt per build
- `PrivacyInfo.xcprivacy` declares UserDefaults use (reason CA92.1), no tracking, no data collected
- Debug-only UI test launch options are compiled out of Release

## You need to do

1. In Xcode, select the EmojiMatch target → *Signing & Capabilities* → choose your **Team**. Signing is automatic; `DEVELOPMENT_TEAM` is intentionally blank in the repo.
2. In [App Store Connect](https://appstoreconnect.apple.com), create the app record with the bundle ID above.
3. Choose **Any iOS Device**, then *Product → Archive*.
4. In the Organizer, choose *Distribute App → TestFlight*, and upload.
5. Bump `CURRENT_PROJECT_VERSION` for every later upload.

## App Store Connect details

- **Privacy:** "Data Not Collected." Scores and settings stay on the device.
- **Category:** Games → Puzzle.
- **Age rating:** expected 4+, with no objectionable content.
- **Before external testers:** beta description, feedback email, and privacy policy URL are required by Apple.

## Before wider release

- Complete [QA_CHECKLIST.md](QA_CHECKLIST.md) on real devices.
- Have someone with authority review the use of system emoji as gameplay art. Rendering them at runtime with the system font is the conservative approach taken here, and the app icon uses custom-drawn art rather than an emoji bitmap for the same reason. Don't use bitmap emoji in App Store screenshots or marketing without checking first.
