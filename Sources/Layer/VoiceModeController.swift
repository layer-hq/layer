@preconcurrency import WebRTC
import AVFoundation
import Combine
import Foundation

enum VoiceModeState: Equatable {
    case idle
    case connecting
    case listening
    case speaking

    var label: String? {
        switch self {
        case .idle: return nil
        case .connecting: return "Connecting"
        case .listening: return "Listening"
        case .speaking: return "Speaking"
        }
    }
}

@MainActor
final class VoiceModeController: NSObject, ObservableObject {
    @Published private(set) var state: VoiceModeState = .idle
    @Published private(set) var notice: Notice?

    private let credentials: any ChatCredentialProviding
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var remoteAudioTrack: RTCAudioTrack?
    private var sessionTask: Task<Void, Never>?

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()

    init(
        credentials: any ChatCredentialProviding = StoredChatCredentialAdapter()
    ) {
        self.credentials = credentials
        super.init()
    }

    var isActive: Bool { state != .idle }

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard state == .idle else { return }
        guard let apiKey = credentials.loadCredential(), !apiKey.isEmpty else {
            notice = Notice(
                message: "Add an OpenAI API key in Settings before starting voice mode.",
                recovery: .settings
            )
            return
        }

        notice = nil
        state = .connecting
        sessionTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard await Self.microphoneAllowed() else {
                    throw VoiceModeError.microphoneDenied
                }
                try await connect(apiKey: apiKey)
                try Task.checkCancellation()
                state = .listening
            } catch is CancellationError {
                return
            } catch {
                fail(error)
            }
        }
    }

    func stop() {
        sessionTask?.cancel()
        sessionTask = nil
        dataChannel?.delegate = nil
        dataChannel?.close()
        dataChannel = nil
        remoteAudioTrack?.isEnabled = false
        remoteAudioTrack = nil
        peerConnection?.delegate = nil
        peerConnection?.close()
        peerConnection = nil
        state = .idle
    }

    func dismissNotice() {
        notice = nil
    }

    private func connect(apiKey: String) async throws {
        let ephemeralKey = try await createClientSecret(apiKey: apiKey)
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        guard let peerConnection = Self.factory.peerConnection(
            with: configuration,
            constraints: RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: nil
            ),
            delegate: self
        ) else {
            throw VoiceModeError.connection("Layer could not create a WebRTC connection.")
        }

        let audioSource = Self.factory.audioSource(
            with: RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: [
                    "googEchoCancellation": "true",
                    "googAutoGainControl": "true",
                    "googNoiseSuppression": "true"
                ]
            )
        )
        let audioTrack = Self.factory.audioTrack(
            with: audioSource,
            trackId: "layer-microphone"
        )
        guard peerConnection.add(audioTrack, streamIds: ["layer"]) != nil else {
            throw VoiceModeError.connection(
                "Layer could not add microphone audio to WebRTC."
            )
        }

        guard let dataChannel = peerConnection.dataChannel(
            forLabel: "oai-events",
            configuration: RTCDataChannelConfiguration()
        ) else {
            throw VoiceModeError.connection(
                "Layer could not create the Realtime event channel."
            )
        }

        self.peerConnection = peerConnection
        self.dataChannel = dataChannel
        dataChannel.delegate = self

        let offer = try await offer(from: peerConnection)
        try await setDescription(offer, on: peerConnection, local: true)
        let answerSDP = try await exchangeSDP(offer.sdp, ephemeralKey: ephemeralKey)
        try await setDescription(
            RTCSessionDescription(type: .answer, sdp: answerSDP),
            on: peerConnection,
            local: false
        )
    }

    private func createClientSecret(apiKey: String) async throws -> String {
        let json = try await postJSON(
            url: "https://api.openai.com/v1/realtime/client_secrets",
            apiKey: apiKey,
            body: JSONSerialization.data(withJSONObject: [
                "session": [
                    "type": "realtime",
                    "model": "gpt-realtime-2.1",
                    "output_modalities": ["audio"],
                    "instructions": "You are Layer. Answer clearly and concisely.",
                    "audio": [
                        "input": [
                            "noise_reduction": ["type": "far_field"],
                            "turn_detection": [
                                "type": "server_vad",
                                "threshold": 0.5,
                                "prefix_padding_ms": 300,
                                "silence_duration_ms": 500,
                                "create_response": true,
                                "interrupt_response": true
                            ]
                        ],
                        "output": ["voice": "shimmer"]
                    ]
                ]
            ])
        )
        guard let value = json["value"] as? String else {
            throw VoiceModeError.connection(
                "OpenAI Realtime returned an invalid response."
            )
        }
        return value
    }

    private func offer(
        from peerConnection: RTCPeerConnection
    ) async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio:
                    kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo:
                    kRTCMediaConstraintsValueFalse
            ],
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { offer, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let offer {
                    continuation.resume(returning: offer)
                } else {
                    continuation.resume(
                        throwing: VoiceModeError.connection(
                            "OpenAI Realtime returned an invalid response."
                        )
                    )
                }
            }
        }
    }

    private func setDescription(
        _ description: RTCSessionDescription,
        on peerConnection: RTCPeerConnection,
        local: Bool
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let finish: @Sendable (Error?) -> Void = { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
            if local {
                peerConnection.setLocalDescription(description, completionHandler: finish)
            } else {
                peerConnection.setRemoteDescription(description, completionHandler: finish)
            }
        }
    }

    private func exchangeSDP(
        _ offerSDP: String,
        ephemeralKey: String
    ) async throws -> String {
        let (data, status) = try await post(
            url: "https://api.openai.com/v1/realtime/calls",
            apiKey: ephemeralKey,
            contentType: "application/sdp",
            body: Data(offerSDP.utf8)
        )
        guard (200..<300).contains(status),
              let answer = String(data: data, encoding: .utf8),
              !answer.isEmpty else {
            throw apiError(from: data, status: status)
        }
        return answer
    }

    private func postJSON(
        url: String,
        apiKey: String,
        body: Data
    ) async throws -> [String: Any] {
        let (data, status) = try await post(
            url: url,
            apiKey: apiKey,
            contentType: "application/json",
            body: body
        )
        guard (200..<300).contains(status),
              let json = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw apiError(from: data, status: status)
        }
        return json
    }

    private func post(
        url: String,
        apiKey: String,
        contentType: String,
        body: Data
    ) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceModeError.connection(
                "OpenAI Realtime returned an invalid response."
            )
        }
        return (data, http.statusCode)
    }

    private func fail(_ error: Error) {
        let recovery: NoticeRecovery?
        if let voiceError = error as? VoiceModeError,
           case .microphoneDenied = voiceError {
            recovery = .microphoneSettings
        } else {
            recovery = nil
        }
        stop()
        notice = Notice(message: error.localizedDescription, recovery: recovery)
    }

    private func apiError(from data: Data, status: Int) -> Error {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = (json?["error"] as? [String: Any])?["message"] as? String
        return VoiceModeError.connection(
            message ?? "OpenAI Realtime failed (HTTP \(status))."
        )
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
}

private enum VoiceModeError: LocalizedError {
    case microphoneDenied
    case connection(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is required. Enable Layer in System Settings → Privacy & Security → Microphone."
        case .connection(let message):
            return message
        }
    }
}

extension VoiceModeController: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}

    nonisolated func dataChannel(
        _ dataChannel: RTCDataChannel,
        didReceiveMessageWith buffer: RTCDataBuffer
    ) {
        guard let json = try? JSONSerialization.jsonObject(with: buffer.data)
                as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "input_audio_buffer.speech_started":
            Task { @MainActor [weak self] in self?.state = .listening }
        case "response.created":
            Task { @MainActor [weak self] in self?.state = .speaking }
        case "response.done":
            Task { @MainActor [weak self] in self?.state = .listening }
        case "error":
            let message = (json["error"] as? [String: Any])?["message"] as? String
                ?? "OpenAI Realtime failed."
            Task { @MainActor [weak self] in
                self?.fail(VoiceModeError.connection(message))
            }
        default:
            break
        }
    }
}

extension VoiceModeController: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange stateChanged: RTCSignalingState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd stream: RTCMediaStream
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove stream: RTCMediaStream
    ) {}

    nonisolated func peerConnectionShouldNegotiate(
        _ peerConnection: RTCPeerConnection
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceConnectionState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceGatheringState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove candidates: [RTCIceCandidate]
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didOpen dataChannel: RTCDataChannel
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCPeerConnectionState
    ) {
        guard newState == .failed else { return }
        Task { @MainActor [weak self] in
            self?.fail(
                VoiceModeError.connection("The Realtime WebRTC connection failed.")
            )
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {
        guard let audioTrack = rtpReceiver.track as? RTCAudioTrack else { return }
        Task { @MainActor [weak self] in
            self?.remoteAudioTrack = audioTrack
            audioTrack.isEnabled = true
        }
    }
}
