import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'transcript_model.dart';

typedef _PickCbNative = Void Function(Pointer<Utf8>);
typedef _PickAudioNative = Void Function(Pointer<NativeFunction<_PickCbNative>>);
typedef _PickAudioDart = void Function(Pointer<NativeFunction<_PickCbNative>>);

typedef _HasApiKeyNative = Int32 Function();
typedef _HasApiKeyDart = int Function();

typedef _SetApiKeyNative = Int32 Function(Pointer<Utf8>);
typedef _SetApiKeyDart = int Function(Pointer<Utf8>);

typedef _ProgressCbNative = Void Function(Double);
typedef _DoneCbNative = Void Function(Pointer<Utf8>);

typedef _TranscribeStartNative = Void Function(
  Pointer<Utf8>,
  Int32,
  Pointer<NativeFunction<_ProgressCbNative>>,
  Pointer<NativeFunction<_DoneCbNative>>,
);
typedef _TranscribeStartDart = void Function(
  Pointer<Utf8>,
  int,
  Pointer<NativeFunction<_ProgressCbNative>>,
  Pointer<NativeFunction<_DoneCbNative>>,
);

typedef _TranscribeCancelNative = Void Function();
typedef _TranscribeCancelDart = void Function();

typedef _OpenFileCbNative = Void Function(Pointer<Utf8>);
typedef _SetOpenFileCbNative = Void Function(Pointer<NativeFunction<_OpenFileCbNative>>);
typedef _SetOpenFileCbDart = void Function(Pointer<NativeFunction<_OpenFileCbNative>>);

typedef _TranscribeFreeStringNative = Void Function(Pointer<Utf8>);
typedef _TranscribeFreeStringDart = void Function(Pointer<Utf8>);

final DynamicLibrary _dylib = DynamicLibrary.process();

final _pickAudioNative =
    _dylib.lookupFunction<_PickAudioNative, _PickAudioDart>('transcribe_pick_audio');
final _hasApiKeyNative =
    _dylib.lookupFunction<_HasApiKeyNative, _HasApiKeyDart>('transcribe_has_api_key');
final _setApiKeyNative =
    _dylib.lookupFunction<_SetApiKeyNative, _SetApiKeyDart>('transcribe_set_api_key');
final _transcribeStartNative =
    _dylib.lookupFunction<_TranscribeStartNative, _TranscribeStartDart>('transcribe_start');
final _transcribeCancelNative =
    _dylib.lookupFunction<_TranscribeCancelNative, _TranscribeCancelDart>('transcribe_cancel');
final _setOpenFileCbNative =
    _dylib.lookupFunction<_SetOpenFileCbNative, _SetOpenFileCbDart>('transcribe_set_open_file_cb');
final _transcribeFreeString =
    _dylib.lookupFunction<_TranscribeFreeStringNative, _TranscribeFreeStringDart>(
  'transcribe_free_string',
);

NativeCallable<_OpenFileCbNative>? _openFileCallable;

/// Opens the native document picker to select an audio or video file.
Future<String?> pickAudio() {
  final completer = Completer<String?>();
  late final NativeCallable<_PickCbNative> callable;
  callable = NativeCallable<_PickCbNative>.listener((Pointer<Utf8> ptr) {
    try {
      if (ptr == nullptr) {
        completer.complete(null);
      } else {
        try {
          completer.complete(ptr.toDartString());
        } finally {
          _transcribeFreeString(ptr);
        }
      }
    } catch (e, st) {
      completer.completeError(e, st);
    } finally {
      callable.close();
    }
  });

  try {
    _pickAudioNative(callable.nativeFunction);
  } catch (e) {
    callable.close();
    rethrow;
  }
  return completer.future;
}

/// Checks whether an ElevenLabs API key is present in the iOS Keychain.
bool hasApiKey() => _hasApiKeyNative() == 1;

/// Saves the ElevenLabs API key to the iOS Keychain.
void setApiKey(String key) {
  final ptr = key.toNativeUtf8();
  try {
    final status = _setApiKeyNative(ptr);
    if (status != 0) {
      throw TranscribeError('Failed to save API key (status: $status)');
    }
  } finally {
    malloc.free(ptr);
  }
}

/// Transcribes an audio file at [path] with an optional progress callback.
Future<TranscriptResult> transcribe(
  String path, {
  void Function(double)? onProgress,
}) {
  final completer = Completer<TranscriptResult>();
  late final NativeCallable<_ProgressCbNative> progressCallable;
  late final NativeCallable<_DoneCbNative> doneCallable;

  progressCallable = NativeCallable<_ProgressCbNative>.listener((double fraction) {
    onProgress?.call(fraction);
  });

  doneCallable = NativeCallable<_DoneCbNative>.listener((Pointer<Utf8> jsonPtr) {
    try {
      if (jsonPtr == nullptr) {
        completer.completeError(const TranscribeError('Empty transcription response'));
        return;
      }
      try {
        final jsonStr = jsonPtr.toDartString();
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          if (decoded['cancelled'] == true) {
            completer.completeError(const TranscribeCancelled());
            return;
          }
          if (decoded['error'] != null) {
            completer.completeError(TranscribeError(decoded['error'] as String));
            return;
          }
          completer.complete(TranscriptResult.fromJson(decoded));
        } else {
          completer.completeError(const TranscribeError('Invalid response format'));
        }
      } finally {
        _transcribeFreeString(jsonPtr);
      }
    } catch (e, st) {
      completer.completeError(e, st);
    } finally {
      progressCallable.close();
      doneCallable.close();
    }
  });

  final pathPtr = path.toNativeUtf8();
  try {
    _transcribeStartNative(
      pathPtr,
      0,
      progressCallable.nativeFunction,
      doneCallable.nativeFunction,
    );
  } catch (e) {
    progressCallable.close();
    doneCallable.close();
    rethrow;
  } finally {
    malloc.free(pathPtr);
  }

  return completer.future;
}

/// Cancels the running transcription.
void cancel() => _transcribeCancelNative();

/// Registers a callback for files opened into the app from share sheet or Files.
void onOpenFile(void Function(String path) cb) {
  _openFileCallable?.close();
  _openFileCallable = NativeCallable<_OpenFileCbNative>.listener((Pointer<Utf8> ptr) {
    if (ptr != nullptr) {
      try {
        cb(ptr.toDartString());
      } finally {
        _transcribeFreeString(ptr);
      }
    }
  });
  _setOpenFileCbNative(_openFileCallable!.nativeFunction);
}

/// Thrown when transcription is cancelled.
class TranscribeCancelled implements Exception {
  const TranscribeCancelled();

  @override
  String toString() => 'Transcription was cancelled';
}

/// Thrown when transcription or key storage encounters an error.
class TranscribeError implements Exception {
  const TranscribeError(this.message);

  final String message;

  @override
  String toString() => message;
}
