# Debugging a DartNative app

## VS Code: Ctrl+F5

Workspace is configured so **Ctrl+F5** (Run Without Debugging) launches via the DartNative SDK directory, not Homebrew Dart.

1. Open the **folder** `transcribe_app` in VS Code (not a parent).
2. **Developer: Reload Window** once after pulling these settings.
3. Status bar should show the Flutter SDK under `…/zero`.
4. Select a device in the status bar (simulator / iPhone).
5. Press **Ctrl+F5** (or F5 to debug with breakpoints).

Launch config: `.vscode/launch.json` → `transcribe_app`.

## Why `dart:ui is not available` happened

Plain `dart run` / wrong SDK. DartNative needs `flutter run` from the DartNative SDK directory (the `dn` toolchain). The pubspec includes `flutter: sdk: flutter` so Dart-Code treats the project as a Flutter/DN app.

## Terminal alternative

```bash
export PATH="$HOME/zero/bin:$PATH"
dn devices
dn run -d <id>
```

Hot reload: `r` · hot restart: `R`

## Logs

`main` wraps the app in `DartNativeLogger.run(..., verbose: true, saveToFile: true)`.
Plugin registration and DI run inside that zone so `dnLog` / `print` from tap handlers still reach the session file.

- **Debug Console / `dn run` stdout** - `[DN]` framework lines (when verbose) plus app `dnLog(...)` from the controller (`load` / `saveKey` / `pickAudio` / `transcribe`).
- **Session file** - path is printed at startup (temp dir `dartnative_session.log` unless overridden). Pull from simulator/device with `xcrun devicectl device copy from …` or the Xcode container browser.
- Never log the raw API key (the controller only logs presence / outcomes).

Look for lines starting with `transcribe:` for the user-intent flow.

## "Unable to launch Flutter project in a Dart-only workspace"

Dart-Code activated before it saw this as a Flutter/DN project (or with the wrong SDK). Launch then thinks you want Flutter while the workspace is still Dart-only.

Fix:

1. Confirm you opened the project folder (the folder with `pubspec.yaml`), not a parent or `lib/`.
2. Command Palette → **Developer: Reload Window**.
3. Status bar should show the SDK from the DartNative SDK directory (not Homebrew).
4. Run dropdown → select **`transcribe_app`**, then Ctrl+F5.

`dart.projectSearchDepth` is set to `10` in `.vscode/settings.json` in case a parent folder is ever opened.
