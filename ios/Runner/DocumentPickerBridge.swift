import AVFoundation
import Foundation
import UniformTypeIdentifiers
import UIKit

/// C ABI for Dart: open a document picker for audio **or** video.
/// Videos are exported to a temporary `.m4a` before the path is returned,
/// so ElevenLabs always receives audio.
public typealias TranscribePickAudioCallback = @convention(c) (UnsafePointer<CChar>?) -> Void

private final class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentPickerCoordinator()
    var callback: TranscribePickAudioCallback?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            finish(nil)
            return
        }
        Task {
            do {
                let audioURL = try await ScribeClient.ensureAudioFile(at: url)
                await MainActor.run { self.finish(audioURL.path) }
            } catch {
                await MainActor.run { self.finish(nil) }
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }

    private func finish(_ path: String?) {
        if let path {
            callback?(strdup(path))
        } else {
            callback?(nil)
        }
        callback = nil
    }
}

@_used @_cdecl("transcribe_pick_audio")
public func transcribe_pick_audio(_ cb: TranscribePickAudioCallback) {
    DispatchQueue.main.async {
        DocumentPickerCoordinator.shared.callback = cb
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene.windows.first?.rootViewController
        else {
            cb(nil)
            return
        }

        var types: [UTType] = [
            .audio, .mp3, .wav, .aiff, .mpeg4Audio,
            .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi,
        ]
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }
        if let caf = UTType(filenameExtension: "caf") { types.append(caf) }
        if let aac = UTType(filenameExtension: "aac") { types.append(aac) }
        if let mkv = UTType(filenameExtension: "mkv") { types.append(mkv) }
        if let webm = UTType(filenameExtension: "webm") { types.append(webm) }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = DocumentPickerCoordinator.shared

        var presenter = root
        while let shown = presenter.presentedViewController {
            presenter = shown
        }
        presenter.present(picker, animated: true)
    }
}
