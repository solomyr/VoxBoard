# VoxBoard

An open-source, on-device voice-to-message app for iPhone and iPad, built from [AltBoard](https://github.com/Altboard/Altboard).

Speak → transcribe locally → polish with a local language model → review → copy, share, or insert through the keyboard. VoxBoard never sends a message automatically.

## Implemented

- Native SwiftUI Compose screen with editable output, automatic polishing, copy/share, and original-transcript restore.
- On-device speech recognition through WhisperKit, Parakeet, and Moonshine. Whisper supports 100 language codes; coverage depends on the selected engine. Translation is optional and off by default.
- Local llama.cpp text cleanup. **Ready to send** asks the model to preserve meaning, names, numbers, and the original languages, including mixed-language text.
- Bundled Whisper tokenizers avoid a first-load tokenizer download.
- Model downloads with SHA-256 verification, cancellation, retry, and storage checks. Suggested setup: Whisper Small plus Qwen 3.5 0.8B.
- Draft persistence using iOS complete file protection. Clear removes the draft and its stored original. Recording history defaults to 24 hours and is configurable.
- Typing keyboard with English QWERTY, Bulgarian phonetic/BDS, and 9 other language layouts; shift/caps lock, numbers/symbols, accent menus, repeat delete, and space-bar cursor movement. A small microphone sits above the keys.
- Swipe typing on the letter keys for all 11 typing layouts, with a suggestion bar; delete right after a swipe removes the whole word. One-handed mode (left or right) from the language menu. Word lists: [FrequencyWords](https://github.com/hermitdave/FrequencyWords) by Hermit Dave, CC BY-SA 4.0 (top 30,000 words per language, filtered), in `Shared/SwipeLexicons`.
- Optional keyboard voice input and local text cleanup. The alternative Voice + Symbols layout retains upstream snippets and writing styles. Failed, incomplete, or numerically altered cleanup preserves the original text.
- In-place keyboard dictation: tap to start and tap to stop, or hold to talk and release. The first recording briefly opens VoxBoard to turn the microphone on (iOS keyboards cannot use the microphone themselves). With **Instant keyboard dictation** on (the default), VoxBoard keeps the microphone ready afterwards, so later recordings are transcribed, polished, and inserted without leaving the app you are typing in. The session ends after a chosen idle time (15 minutes by default), from the keyboard's mic-off button, or in Settings; iOS shows the orange indicator while it is ready. Compose recordings always release the microphone right away. A **Dictate with VoxBoard** App Shortcut also opens Compose.
- Independent identity: `app.voxboard`, `app.voxboard.keyboard`, `group.app.voxboard.shared`, and the `voxboard` URL scheme.
- Normal builds and archives have no purchase requirement.

Review messages before sending: local models can make mistakes. Device memory, model choice, language, and message length affect speed and quality. New Compose UI currently falls back to English; upstream screens retain their translations.

## Build

Requires macOS, compatible Xcode with Swift 6.1+, the iOS SDK, and XcodeGen. Deployment target: iOS/iPadOS 17.

```sh
brew install xcodegen swiftformat swiftlint
./scripts/bootstrap-llama.sh
xcodegen generate
open VoxBoard.xcodeproj
```

Choose the **VoxBoard** scheme. Internal source directories and targets retain `Sayboard` names to simplify upstream merges. Edit `project.yml` and regenerate instead of editing the generated project.

For physical devices, configure your own `DEVELOPMENT_TEAM`, bundle IDs, and App Group. Update both entitlements files and `Shared/Constants.swift` consistently. Checked-in identifiers are development defaults, not Apple account registrations.

For repeatable USB installation, connect and unlock your paired iPhone, enable Developer Mode, then run:

```sh
./scripts/install-iphone.sh DEVICE_UDID APPLE_TEAM_ID
python3 scripts/preload-iphone-models.py DEVICE_UDID
```

The preload command installs checksummed Whisper Small and Qwen 3.5 2B weights (about 2.1 GB expanded), suitable for recent Pro devices. It needs internet on the Mac for the first download; speech and cleanup then run locally on the phone. Pass `--text qwen35-0.8b-q4km` for a smaller text model. Quit VoxBoard before preloading and relaunch afterward. It does not replace a selected model or edit existing drafts.

To remember a signing team without committing account details, create git-ignored `signing.local.yml`:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: YOUR_TEAM_ID
```

If automatic signing initially reports missing App Groups, open both application targets' **Signing & Capabilities** panes in Xcode. Let Xcode register `group.app.voxboard.shared` and regenerate their profiles, then retry. No distribution certificate or App Store upload is needed for this development installation.

The inherited **VoxBoard StoreKit** scheme is for upstream source compatibility; it is not the normal release scheme and has no configured VoxBoard App Store product.

## First use

1. Download speech and text models from Compose, or choose alternatives under Models. Allow roughly 3 GB free for downloading/extracting the suggested pair with a safety reserve.
2. Tap **Tap to speak**, grant microphone access, then tap **Stop and prepare text**.
3. Review the message, restore the original if needed, then copy or share. You can also type/paste text and tap **Polish**.

After setup, inference requires no network connection. Model weights are downloaded separately from the app binary.

## Keyboard and microphone

Add VoxBoard in **Settings → General → Keyboard → Keyboards**. Normal typing works without microphone permission or Full Access. Use the language chooser above the keys for English, Bulgarian phonetic/BDS, or another layout. Enable Full Access once for communication between the app and keyboard, and grant microphone permission in VoxBoard. Preview the keyboard under **Settings → Keyboard → Try the keyboard**.

**Tap the keyboard mic to start; tap again to stop.** Each recording briefly opens VoxBoard to activate the microphone, then returns to the app where you are typing. Audio is captured only after that explicit tap. Stopping immediately releases microphone access, then local transcription and text cleanup run and insert the result. There is no background session to enable, renew after a restart, or manually end between recordings. Opening Compose, Models, or the keyboard preview does not start the microphone.

The small sparkle button cleans up text before the cursor. It wakes VoxBoard on demand without activating the microphone. Compose remains available for longer drafts, review, copy/share, and the **Dictate with VoxBoard** App Shortcut.

**Implementation constraint:** iOS does not give keyboard extensions direct microphone access. Automatic opening/return uses AltBoard's existing responder-chain, keyboard-host discovery, and Launch Services integration, including undocumented iOS APIs. These compatibility paths are explicit in the source and were tested on the connected iPhone; they are not guaranteed across future iOS versions or App Store review. If automatic return fails, the app shows a return hint. App Store distribution needs a separate review of this integration.

## Model downloads

`Sayboard/Resources/model-manifest.json` pins the upstream catalog retrieved on 2026-11-06. The catalog itself loads locally. Archive URLs still use **models.sayboard.app**, an upstream development dependency, not VoxBoard-controlled hosting. No voice or message text is uploaded there.

Before public distribution, arrange reliable, permitted model hosting, review each model's redistribution license, and update the URLs/checksums. Model weights have separate licenses. For your own remote catalog, set `VoxBoardModelManifestURL` in the app Info.plist to an HTTPS URL using the same schema.

## Verification

```sh
xcodegen generate
./scripts/lint-strings.sh
xcodebuild -project VoxBoard.xcodeproj -scheme VoxBoard \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

Tests include upstream regressions plus VoxBoard defaults, protected draft persistence, numeric-fact protection, keyboard layouts/casing, and catalog integrity. `MicrophoneSessionTests` run only when the test host already has microphone permission; they never display a permission prompt. `LocalModelIntegrationTests` use real Qwen 3.5 0.8B weights installed in the test host's Application Support/LLMModels directory. The speech-to-cleanup test also needs Whisper Tiny and `Documents/voxboard-test-dictation.aiff` in that simulator app container. These integration tests skip when optional fixtures are absent; regular tests need no model downloads.

Real-model tests also cover Qwen 3.5 2B and prefer Whisper Small when installed. `OnDemandDictationUITests` require the separate **VoxBoardKeyboardFixture** app installed on the test phone plus the VoxBoard keyboard already enabled. Explicitly install the current main-app build before running these tests: they start in the separate fixture, so Xcode may leave the previous target app and extension installed. These tests record briefly into an isolated field and never send a message; remove the fixture after testing. **VoxBoard Device Tests** also includes a Compose UI test for polishing, copy/share, and draft persistence. Run that Compose test only on a fresh development install: it creates and clears a sample draft, and opens the share sheet without choosing a recipient or sending anything.

Verified on an iPhone 17 Pro running iOS 27.3: 432 tests passed, including real local speech/text inference and the Compose UI flow; one optional small-model test was skipped. The 0.3.0 update also tests cold-app, automatic keyboard handoff and consecutive recordings with the microphone off between them, along with text cleanup from a separate app. See `docs/verification.txt` for details and remaining manual checks.

Regenerate the icon with `swift scripts/generate-icon.swift Sayboard/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Provenance and license

Forked from AltBoard commit `f4e77949cb891f26cf234a0a074d78d14a3450dd`. Original documentation is in `docs/UPSTREAM.md`. Copyright/license notices are preserved. VoxBoard is independent, not an official AltBoard release.

GNU GPL v3; see [LICENSE](LICENSE). Preserve notices and provide corresponding source as required when distributing a derivative build. Review dependency/model licenses and distribution-channel terms before release.
