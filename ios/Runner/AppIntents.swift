import AppIntents
import Foundation

/// Transcribe audio or video with ElevenLabs Scribe (auto language + diarization).
/// Video is converted to m4a before upload. Uses ProgressReportingIntent on the
/// current iOS 26 SDK; LongRunningIntent when iOS 27 SDK is available.
struct TranscribeRecordingIntent: AppIntent, ProgressReportingIntent {
    static var title: LocalizedStringResource = "Transcribe Recording"
    static var description = IntentDescription(
        "Transcribes an audio or video file with automatic language detection and speaker labels."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Media File", description: "Audio or video. Video is converted to audio first.")
    var audioFile: IntentFile

    @Parameter(title: "Speakers", description: "Optional known speaker count.")
    var speakers: Int?

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        progress.totalUnitCount = 100
        progress.completedUnitCount = 0
        progress.localizedDescription = "Preparing media…"

        guard let url = audioFile.fileURL else {
            throw ScribeClient.ScribeError.empty
        }

        let result = try await ScribeClient.transcribe(fileURL: url, speakers: speakers) { fraction in
            let units = min(max(Int64(fraction * 100), 0), 99)
            if units > self.progress.completedUnitCount {
                self.progress.completedUnitCount = units
                self.progress.localizedDescription = "Uploading…"
            }
        }
        progress.completedUnitCount = 100
        progress.localizedDescription = "Done"

        return .result(value: result.plainText, dialog: IntentDialog("Transcription ready"))
    }
}

@available(iOS 17.0, *)
struct TranscribeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranscribeRecordingIntent(),
            phrases: [
                "Transcribe a recording in \(.applicationName)",
                "Transcribe audio in \(.applicationName)",
                "Transcribe video in \(.applicationName)",
            ],
            shortTitle: "Transcribe Recording",
            systemImageName: "waveform"
        )
    }
}
