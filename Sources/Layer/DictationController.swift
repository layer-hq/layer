import AVFoundation
import Combine
import Foundation

enum DictationSurface: Equatable {
    case notch
    case chat(UUID)
}

enum DictationState: Equatable {
    case idle
    case recording
    case transcribing

    var label: String? {
        switch self {
        case .idle: nil
        case .recording: "Listening"
        case .transcribing: "Transcribing"
        }
    }
}

enum DictationError: LocalizedError, Equatable {
    case microphoneDenied
    case recordingFailed
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            "Microphone access is required. Enable Layer in System Settings → Privacy & Security → Microphone."
        case .recordingFailed:
            "Layer could not record audio."
        case .invalidResponse:
            "OpenAI returned an invalid transcription response."
        case .api(let message):
            message
        }
    }
}

@MainActor
final class DictationController: ObservableObject {
    private struct Recording {
        let recorder: AVAudioRecorder
        let url: URL
        let credential: String
    }

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var notice: Notice?
    @Published private(set) var surface: DictationSurface = .notch

    let transcripts = PassthroughSubject<String, Never>()

    private let providers: any ModelProviderProviding
    private var task: Task<Void, Never>?
    private var recording: Recording?
    private var transcribingURL: URL?

    init(
        providers: any ModelProviderProviding = StoredModelProviderAdapter()
    ) {
        self.providers = providers
    }

    var isActive: Bool { state != .idle }
    var isNotchActive: Bool { isActive && surface == .notch }
    var isChatActive: Bool {
        guard case .chat = surface else { return false }
        return isActive
    }

    func toggle(surface: DictationSurface) {
        switch state {
        case .idle:
            start(surface: surface)
        case .recording:
            stopAndTranscribe()
        case .transcribing:
            break
        }
    }

    func start(surface: DictationSurface) {
        guard state == .idle else { return }
        self.surface = surface
        guard let provider = providers.loadActiveProvider() else {
            notice = Notice(
                message: "Add and select a model provider in Settings before starting dictation.",
                recovery: .settings
            )
            return
        }
        guard provider.kind == .openAI else {
            notice = Notice(
                message: "Dictation currently requires an OpenAI connection. Select one in Settings.",
                recovery: .settings
            )
            return
        }

        notice = nil
        state = .recording
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let microphoneAllowed = await Self.microphoneAllowed()
                try Task.checkCancellation()
                guard microphoneAllowed else {
                    throw DictationError.microphoneDenied
                }
                try beginRecording(credential: provider.apiKey)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    func stopAndTranscribe() {
        guard state == .recording else { return }
        task?.cancel()
        task = nil

        guard let recording else {
            cancel()
            return
        }

        recording.recorder.stop()
        self.recording = nil
        transcribingURL = recording.url
        state = .transcribing
        task = Task { [weak self] in
            defer { Self.removeTemporaryFile(at: recording.url) }
            guard let self else { return }
            do {
                try Task.checkCancellation()
                let transcript = try await Self.transcribe(
                    recording.url,
                    credential: recording.credential
                )
                try Task.checkCancellation()
                guard state == .transcribing else { return }
                finish(with: transcript)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if let recording {
            recording.recorder.stop()
            Self.removeTemporaryFile(at: recording.url)
        }
        if let transcribingURL {
            Self.removeTemporaryFile(at: transcribingURL)
        }
        recording = nil
        transcribingURL = nil
        state = .idle
    }

    func dismissNotice() {
        notice = nil
    }

    private func beginRecording(credential: String) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("layer-dictation-\(UUID().uuidString).m4a")
        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000
            ]
        )
        guard recorder.prepareToRecord(), recorder.record() else {
            Self.removeTemporaryFile(at: url)
            throw DictationError.recordingFailed
        }
        recording = Recording(recorder: recorder, url: url, credential: credential)
    }

    private func finish(with transcript: String) {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        task = nil
        transcribingURL = nil
        state = .idle
        if !transcript.isEmpty {
            transcripts.send(transcript)
        }
    }

    private func fail(_ error: Error) {
        cancel()
        notice = Notice(
            message: error.localizedDescription,
            recovery: error is DictationError
                && (error as? DictationError) == .microphoneDenied
                ? .microphoneSettings
                : nil
        )
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        default:
            false
        }
    }

    nonisolated static func multipartBody(
        audio: Data,
        boundary: String
    ) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("gpt-transcribe\r\n")
        body.append("--\(boundary)\r\n")
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"dictation.m4a\"\r\n"
        )
        body.append("Content-Type: audio/mp4\r\n\r\n")
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    nonisolated static func transcript(
        from data: Data,
        response: URLResponse
    ) throws -> String {
        guard let response = response as? HTTPURLResponse else {
            throw DictationError.invalidResponse
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200..<300).contains(response.statusCode) else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw DictationError.api(message ?? "OpenAI transcription failed.")
        }
        guard let text = json?["text"] as? String else {
            throw DictationError.invalidResponse
        }
        return text
    }

    private nonisolated static func removeTemporaryFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private nonisolated static func transcribe(
        _ url: URL,
        credential: String
    ) async throws -> String {
        let audio = try Data(contentsOf: url)
        let boundary = "Layer-\(UUID().uuidString)"
        var request = URLRequest(
            url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = multipartBody(audio: audio, boundary: boundary)
        let (data, response) = try await URLSession.shared.data(for: request)
        return try transcript(from: data, response: response)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
