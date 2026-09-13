import AVFoundation
import Foundation
import Security

/// Contiguous speaker turn.
struct Turn {
    let speaker: String
    let start: Double
    let end: Double
    let text: String

    var displayName: String {
        if speaker.hasPrefix("speaker_") {
            if let idx = Int(speaker.dropFirst(8)) {
                return "Speaker \(idx + 1)"
            }
        }
        return speaker
    }

    var timestamp: String {
        let total = Int(start)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var line: String {
        "[\(timestamp)] \(displayName): \(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func toDict() -> [String: Any] {
        [
            "speaker": speaker,
            "start": start,
            "end": end,
            "text": text,
        ]
    }
}

struct TranscriptionResult {
    let turns: [Turn]
    let language: String
    let probability: Double
    let duration: Double

    var plainText: String {
        turns.map(\.line).joined(separator: "\n\n")
    }

    func toJSONString() -> String {
        let dict: [String: Any] = [
            "turns": turns.map { $0.toDict() },
            "language": language,
            "probability": probability,
            "duration": duration,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"Failed to encode transcription result\"}"
        }
        return str
    }
}

enum ScribeClient {
    static let endpoint = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
    static let keychainService = "app.transcribe.elevenlabs"
    static let keychainAccount = "api_key"

    enum ScribeError: LocalizedError {
        case missingApiKey
        case http(Int, String)
        case empty
        case media(String)
        case alreadyTranscribing

        var errorDescription: String? {
            switch self {
            case .missingApiKey:
                return "No ElevenLabs API key. Save one in the app first."
            case .http(_, let msg):
                return msg
            case .empty:
                return "Empty transcription."
            case .media(let msg):
                return msg
            case .alreadyTranscribing:
                return "Already transcribing"
            }
        }
    }

    // MARK: - Keychain

    static func apiKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ScribeError.missingApiKey
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func setApiKey(_ keyPtr: UnsafePointer<CChar>?) -> Int32 {
        guard let keyPtr, let key = String(validatingUTF8: keyPtr),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return errSecParam
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess ? 0 : status
    }

    static func sanitizeStem(_ name: String) -> String {
        var stem = name
        if let match = stem.range(
            of: #"^transcribe-(?:openin|audio)-[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}-"#,
            options: .regularExpression
        ) {
            stem.removeSubrange(match)
        }
        let sanitized = stem.replacingOccurrences(of: #"[^A-Za-z0-9._-]"#, with: "_", options: .regularExpression)
        let capped = String(sanitized.prefix(60))
        return capped.isEmpty ? "audio" : capped
    }

    // MARK: - Media Conversion

    /// Pass audio through; extract m4a from video/containers and uncompressed formats.
    static func ensureAudioFile(at url: URL) async throws -> URL {
        try Task.checkCancellation()
        let ext = url.pathExtension.lowercased()
        // Pass compressed audio formats through; transcode uncompressed audio (wav, aiff, caf, flac) to m4a to minimize upload size.
        let audioExts: Set<String> = ["m4a", "mp3", "aac", "ogg"]
        if audioExts.contains(ext) {
            return url
        }

        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        try Task.checkCancellation()
        guard !audioTracks.isEmpty else {
            throw ScribeError.media("No audio track in media")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ScribeError.media("Cannot create audio export session")
        }
        let stem = sanitizeStem(url.deletingPathExtension().lastPathComponent)
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcribe-audio-\(UUID().uuidString.lowercased())-\(stem).m4a")
        if FileManager.default.fileExists(atPath: out.path) {
            try? FileManager.default.removeItem(at: out)
        }
        session.shouldOptimizeForNetworkUse = true
        do {
            try await withTaskCancellationHandler {
                try await session.export(to: out, as: .m4a)
            } onCancel: {
                session.cancelExport()
            }
            try Task.checkCancellation()
            return out
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: out)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: out)
            if Task.isCancelled {
                throw CancellationError()
            }
            throw ScribeError.media(error.localizedDescription)
        }
    }

    // MARK: - Multipart Construction

    static func createMultipartBodyFile(
        audioURL: URL,
        speakers: Int?,
        boundary: String
    ) throws -> URL {
        let tempBodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcribe-body-\(UUID().uuidString).tmp")
        if FileManager.default.fileExists(atPath: tempBodyURL.path) {
            try? FileManager.default.removeItem(at: tempBodyURL)
        }
        FileManager.default.createFile(atPath: tempBodyURL.path, contents: nil)

        guard let handle = FileHandle(forWritingAtPath: tempBodyURL.path) else {
            throw ScribeError.media("Cannot create temp body file")
        }
        defer {
            try? handle.close()
        }

        func writeString(_ str: String) throws {
            if let data = str.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        }

        func appendField(_ name: String, _ value: String) throws {
            try writeString("--\(boundary)\r\n")
            try writeString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            try writeString("\(value)\r\n")
        }

        try appendField("model_id", "scribe_v2")
        try appendField("diarize", "true")
        try appendField("timestamps_granularity", "word")
        if let speakers, speakers > 0 {
            try appendField("num_speakers", "\(speakers)")
        }

        let ext = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension.lowercased()
        let filename = "audio.\(ext)"
        try writeString("--\(boundary)\r\n")
        try writeString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        try writeString("Content-Type: application/octet-stream\r\n\r\n")

        let readHandle = try FileHandle(forReadingFrom: audioURL)
        defer {
            try? readHandle.close()
        }
        let chunkSize = 64 * 1024
        while true {
            let chunk = readHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            try handle.write(contentsOf: chunk)
        }

        try writeString("\r\n--\(boundary)--\r\n")
        return tempBodyURL
    }

    // MARK: - Parsing

    static func parseHttpError(code: Int, data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = json["detail"] as? [String: Any],
               let msg = detail["message"] as? String,
               !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let firstLine = msg.components(separatedBy: .newlines).first ?? msg
                return "ElevenLabs \(code): \(firstLine.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            if let detailStr = json["detail"] as? String,
               !detailStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let firstLine = detailStr.components(separatedBy: .newlines).first ?? detailStr
                return "ElevenLabs \(code): \(firstLine.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            if let msg = json["message"] as? String,
               !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let firstLine = msg.components(separatedBy: .newlines).first ?? msg
                return "ElevenLabs \(code): \(firstLine.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }
        return "ElevenLabs \(code)"
    }

    static func jsonError(_ message: String) -> String {
        let firstLine = message.components(separatedBy: .newlines).first ?? message
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let dict = ["error": trimmed]
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"error\":\"\(trimmed)\"}"
    }

    static func parseTurns(from words: [[String: Any]]) -> [Turn] {
        var turns: [Turn] = []
        var currentSpeaker: String?
        var start: Double = 0
        var end: Double = 0
        var buf = ""

        func flush() {
            let trimmed = buf.trimmingCharacters(in: .whitespacesAndNewlines)
            if let speaker = currentSpeaker, !trimmed.isEmpty {
                turns.append(Turn(speaker: speaker, start: start, end: end, text: trimmed))
            }
            buf = ""
        }

        for w in words {
            if (w["type"] as? String) == "spacing" {
                buf += (w["text"] as? String) ?? ""
                continue
            }
            let sid = (w["speaker_id"] as? String) ?? "unknown"
            if currentSpeaker == nil || sid != currentSpeaker {
                flush()
                currentSpeaker = sid
                start = (w["start"] as? NSNumber)?.doubleValue ?? (w["start"] as? Double) ?? 0
            }
            buf += (w["text"] as? String) ?? ""
            end = (w["end"] as? NSNumber)?.doubleValue ?? (w["end"] as? Double) ?? start
        }
        flush()
        return turns
    }

    static func parseResponse(data: Data) throws -> TranscriptionResult {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let words = json["words"] as? [[String: Any]]
        else {
            throw ScribeError.empty
        }

        let turns = parseTurns(from: words)
        if turns.isEmpty {
            throw ScribeError.empty
        }

        let language = json["language_code"] as? String ?? "?"
        let probability = (json["language_probability"] as? NSNumber)?.doubleValue
            ?? (json["language_probability"] as? Double)
            ?? 0.0
        let duration = turns.last?.end ?? 0.0

        return TranscriptionResult(
            turns: turns,
            language: language,
            probability: probability,
            duration: duration
        )
    }

    // MARK: - Background Session & Upload State

    private static let lock = NSLock()
    private static var isTranscribing = false
    private static var currentUploadTask: URLSessionUploadTask?
    private static var currentAsyncTask: Task<Void, Never>?
    private static var currentContinuation: CheckedContinuation<TranscriptionResult, Error>?
    private static var currentProgressHandler: ((Double) -> Void)?
    private static var responseData = Data()
    private static var backgroundCompletionHandlers: [String: () -> Void] = [:]

    private static let sessionIdentifier = "app.transcribe.elevenlabs.upload"
    private static let sessionDelegate = ScribeSessionDelegate()

    private static let backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }()

    static func reportProgress(_ fraction: Double) {
        lock.lock()
        let handler = currentProgressHandler
        lock.unlock()
        handler?(fraction)
    }

    static func appendResponseData(_ data: Data) {
        lock.lock()
        responseData.append(data)
        lock.unlock()
    }

    // ponytail: result delivered after a system relaunch is dropped (no continuation), upgrade path: persist the response to disk and surface it on next launch
    static func taskDidComplete(statusCode: Int, error: Error?) {
        lock.lock()
        let cont = currentContinuation
        currentContinuation = nil
        currentUploadTask = nil
        let data = responseData
        responseData = Data()
        lock.unlock()

        guard let cont else { return }

        if let error = error {
            let isCancelled = (error as? URLError)?.code == .cancelled ||
                              (error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled
            if isCancelled {
                cont.resume(throwing: CancellationError())
            } else {
                let firstLine = error.localizedDescription.components(separatedBy: .newlines).first ?? error.localizedDescription
                cont.resume(throwing: ScribeError.media(firstLine))
            }
            return
        }

        if (200..<300).contains(statusCode) {
            do {
                let result = try parseResponse(data: data)
                cont.resume(returning: result)
            } catch {
                cont.resume(throwing: error)
            }
        } else {
            let errMsg = parseHttpError(code: statusCode, data: data)
            cont.resume(throwing: ScribeError.http(statusCode, errMsg))
        }
    }

    static func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) {
        _ = backgroundSession
        lock.lock()
        backgroundCompletionHandlers[identifier] = completionHandler
        lock.unlock()
    }

    static func finishBackgroundEvents(for identifier: String?) {
        guard let identifier else { return }
        lock.lock()
        let handler = backgroundCompletionHandlers.removeValue(forKey: identifier)
        lock.unlock()
        DispatchQueue.main.async {
            handler?()
        }
    }

    private static func performTranscription(
        fileURL: URL,
        speakers: Int?,
        progress: ((Double) -> Void)?
    ) async throws -> (result: TranscriptionResult, cleanup: () -> Void) {
        lock.lock()
        if isTranscribing {
            lock.unlock()
            throw ScribeError.alreadyTranscribing
        }
        isTranscribing = true
        currentProgressHandler = progress
        responseData = Data()
        lock.unlock()

        var tempFiles: [URL] = []

        do {
            try Task.checkCancellation()

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                throw ScribeError.media("No such file: \(fileURL.path)")
            }

            if fileURL.path.hasPrefix(FileManager.default.temporaryDirectory.path),
               fileURL.lastPathComponent.hasPrefix("transcribe-") {
                tempFiles.append(fileURL)
            }

            let key = try apiKey()
            let audioURL = try await ensureAudioFile(at: fileURL)
            if Task.isCancelled {
                throw CancellationError()
            }
            if audioURL != fileURL {
                tempFiles.append(audioURL)
            }

            let boundary = "Boundary-\(UUID().uuidString)"
            let bodyURL = try createMultipartBodyFile(
                audioURL: audioURL,
                speakers: speakers,
                boundary: boundary
            )
            tempFiles.append(bodyURL)

            if Task.isCancelled {
                throw CancellationError()
            }

            // The API key header is persisted by nsurlsessiond for background sessions - accepted trade-off.
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue(key, forHTTPHeaderField: "xi-api-key")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 3600

            let result: TranscriptionResult = try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                currentContinuation = continuation
                let task = backgroundSession.uploadTask(with: request, fromFile: bodyURL)
                currentUploadTask = task
                lock.unlock()

                task.resume()
            }

            let cleanup: () -> Void = {
                cleanupTempFiles(tempFiles)
            }
            return (result, cleanup)
        } catch {
            lock.lock()
            isTranscribing = false
            currentUploadTask = nil
            currentContinuation = nil
            currentProgressHandler = nil
            lock.unlock()
            cleanupTempFiles(tempFiles)
            throw error
        }
    }

    static func cleanupTempFiles(_ files: [URL]) {
        lock.lock()
        isTranscribing = false
        currentUploadTask = nil
        currentAsyncTask = nil
        currentContinuation = nil
        currentProgressHandler = nil
        lock.unlock()

        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Public API (Shared between Intent and C export)

    static func transcribe(
        fileURL: URL,
        speakers: Int?,
        progress: ((Double) -> Void)? = nil
    ) async throws -> TranscriptionResult {
        let (result, cleanup) = try await performTranscription(
            fileURL: fileURL,
            speakers: speakers,
            progress: progress
        )
        defer { cleanup() }
        return result
    }

    static func start(
        fileURL: URL,
        speakers: Int?,
        progress: TranscribeProgressCallback?,
        done: TranscribeDoneCallback
    ) {
        lock.lock()
        if isTranscribing {
            lock.unlock()
            done(strdup("{\"error\":\"Already transcribing\"}"))
            return
        }

        let task = Task {
            var cleanupAction: (() -> Void)?
            do {
                let (result, cleanup) = try await performTranscription(
                    fileURL: fileURL,
                    speakers: speakers,
                    progress: { frac in progress?(frac) }
                )
                cleanupAction = cleanup
                let json = result.toJSONString()
                done(strdup(json))
            } catch is CancellationError {
                done(strdup("{\"cancelled\":true}"))
            } catch {
                let msg = error.localizedDescription.components(separatedBy: .newlines).first ?? error.localizedDescription
                let errJson = jsonError(msg)
                done(strdup(errJson))
            }
            cleanupAction?()
        }
        currentAsyncTask = task
        lock.unlock()
    }

    static func cancel() {
        lock.lock()
        let upload = currentUploadTask
        let asyncT = currentAsyncTask
        lock.unlock()

        upload?.cancel()
        asyncT?.cancel()
    }

    // MARK: - Open-in Support

    private static var openFileCallback: TranscribeOpenFileCallback?
    private static var pendingOpenFilePath: String?
    private static let openFileLock = NSLock()

    static func setOpenFileCallback(_ cb: TranscribeOpenFileCallback?) {
        openFileLock.lock()
        openFileCallback = cb
        let pending = pendingOpenFilePath
        pendingOpenFilePath = nil
        openFileLock.unlock()

        if let cb, let pending {
            cb(strdup(pending))
        }
    }

    static func handleOpenFile(at url: URL) {
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let stem = sanitizeStem(url.deletingPathExtension().lastPathComponent)
                let ext = url.pathExtension
                let openInName = ext.isEmpty ? stem : "\(stem).\(ext)"
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("transcribe-openin-\(UUID().uuidString.lowercased())-\(openInName)")
                if FileManager.default.fileExists(atPath: tempURL.path) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                try FileManager.default.copyItem(at: url, to: tempURL)
                if url.path.contains("/Documents/Inbox/") {
                    try? FileManager.default.removeItem(at: url)
                }
                let audioURL = try await ensureAudioFile(at: tempURL)
                if audioURL != tempURL {
                    try? FileManager.default.removeItem(at: tempURL)
                }
                let path = audioURL.path

                openFileLock.lock()
                if let cb = openFileCallback {
                    openFileLock.unlock()
                    cb(strdup(path))
                } else {
                    pendingOpenFilePath = path
                    openFileLock.unlock()
                }
            } catch {
                NSLog("[Transcribe] open-in failed: \(error.localizedDescription)")
            }
        }
    }

    static func purgeStaleTempFiles() {
        // ponytail: 24h threshold so a background upload body in flight is never removed, upgrade path: track the active body file explicitly.
        let tempDir = FileManager.default.temporaryDirectory
        let cutoff = Date().addingTimeInterval(-86400)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: tempDir.path) else { return }
        for file in files where file.hasPrefix("transcribe-") {
            let fileURL = tempDir.appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

final class ScribeSessionDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = min(max(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 0.0), 1.0)
        ScribeClient.reportProgress(fraction)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        ScribeClient.appendResponseData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        ScribeClient.taskDidComplete(statusCode: statusCode, error: error)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        ScribeClient.finishBackgroundEvents(for: session.configuration.identifier)
    }
}

// MARK: - C ABI Exports

typealias TranscribeProgressCallback = @convention(c) (Double) -> Void
typealias TranscribeDoneCallback = @convention(c) (UnsafePointer<CChar>?) -> Void
typealias TranscribeOpenFileCallback = @convention(c) (UnsafePointer<CChar>?) -> Void

@_cdecl("transcribe_has_api_key")
func transcribe_has_api_key() -> Int32 {
    return (try? ScribeClient.apiKey()) != nil ? 1 : 0
}

@_cdecl("transcribe_set_api_key")
func transcribe_set_api_key(_ key: UnsafePointer<CChar>?) -> Int32 {
    return ScribeClient.setApiKey(key)
}

@_cdecl("transcribe_start")
func transcribe_start(
    _ path: UnsafePointer<CChar>?,
    _ speakers: Int32,
    _ progress: TranscribeProgressCallback?,
    _ done: TranscribeDoneCallback?
) {
    guard let done else { return }
    guard let path, let pathString = String(validatingUTF8: path), !pathString.isEmpty else {
        done(strdup("{\"error\":\"Invalid or missing file path\"}"))
        return
    }
    let fileURL = URL(fileURLWithPath: pathString)
    ScribeClient.start(
        fileURL: fileURL,
        speakers: speakers > 0 ? Int(speakers) : nil,
        progress: progress,
        done: done
    )
}

@_cdecl("transcribe_cancel")
func transcribe_cancel() {
    ScribeClient.cancel()
}

@_cdecl("transcribe_set_open_file_cb")
func transcribe_set_open_file_cb(_ cb: TranscribeOpenFileCallback?) {
    ScribeClient.setOpenFileCallback(cb)
}
