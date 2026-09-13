# Architecture

Minimal 5-file DartNative app with a C-ABI / FFI bridge to Swift.

```
lib/
  main.dart               # App entry, SystemChrome setup, logger
  home_screen.dart        # Single-screen state (idle, picked, running) + key sheet
  scribe.dart             # C-ABI FFI wrapper over Swift engine
  transcript_model.dart   # TranscriptResult and SpeakerTurn data models
  transcript_screen.dart  # Formatted transcript display
```

## FFI Contract

Dart communicates with Swift via C ABI exports (`@_cdecl`) using `DynamicLibrary.process()` and `NativeCallable.listener`:

- `transcribe_pick_audio(cb)`: Native document picker; returns sandboxed audio path or null.
- `transcribe_has_api_key()`: Returns 1 if ElevenLabs key exists in iOS Keychain, else 0.
- `transcribe_set_api_key(key)`: Saves key to iOS Keychain; returns 0 on success or OSStatus.
- `transcribe_start(path, speakers, progress, done)`: Starts transcription with progress (0.0..1.0) and done JSON callback (the UI has no speaker-count control; the FFI accepts 0 = auto).
- `transcribe_cancel()`: Cancels active transcription.
- `transcribe_set_open_file_cb(cb)`: Registers callback for files opened via iOS share sheet.

Swift is the sole reader/writer of the iOS Keychain and handles background network/audio processing.
strings passed to Dart callbacks are allocated by Swift and returned with `transcribe_free_string` after Dart has read them.
