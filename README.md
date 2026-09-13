# Transcribe

A DartNative iOS app for diarized transcription powered by ElevenLabs Scribe v2.

## What it does

- Diarized transcription with automatic language detection
- Audio or video input (videos are converted to audio before upload)
- Open-in support from Files or Voice Memos
- Siri Shortcut integration via App Intents ("Transcribe Recording")
- Clean speaker-turn transcript display with share export

## Requirements

- iOS only
- Paid DartNative licence and the `dn` toolchain
- Xcode with the iOS 26.5 SDK
- An ElevenLabs API key (entered in the app)

## Build and run

```bash
dn pub get
dn devices
dn run -d <id>
```

Before running on a physical device, set your own bundle identifier and Apple development team in Xcode (`ios/Runner.xcodeproj`).

## Privacy

- Audio is uploaded to ElevenLabs for transcription.
- The API key is stored securely in the iOS Keychain.

## Layout

See [docs/architecture.md](docs/architecture.md) for architecture and FFI bridge details.

## Licence

This repository is licensed under the [BSD 3-Clause License](LICENSE). DartNative is a commercial SDK and is licensed separately.
