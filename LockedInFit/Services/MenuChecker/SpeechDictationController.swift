import Foundation
import Speech
import AVFoundation

/// Live speech-to-text for meal dictation, behind a small state machine so the
/// UI can react cleanly. Permission (mic + speech recognition) is requested only
/// when dictation is first used; if denied or unavailable, the caller keeps
/// typing — dictation is strictly additive to manual entry.
@MainActor
final class SpeechDictationController: ObservableObject {

    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case finished
        case denied
        case unavailable
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isListening: Bool { state == .listening }

    /// Request permissions if needed, then begin live transcription.
    func start() async {
        guard state != .listening else { return }
        transcript = ""
        state = .requestingPermission

        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable
            return
        }

        let speechOK = await requestSpeechAuthorization()
        guard speechOK else { state = .denied; return }
        let micOK = await requestMicPermission()
        guard micOK else { state = .denied; return }

        do {
            try beginSession()
            state = .listening
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Stop listening and settle on the final transcript.
    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if state == .listening { state = .finished }
    }

    func reset() {
        stop()
        transcript = ""
        state = .idle
    }

    // MARK: - Permissions

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        default: return false
        }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in cont.resume(returning: granted) }
            }
        }
    }

    // MARK: - Recognition session

    private func beginSession() throws {
        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.state = .finished }
                }
                if error != nil {
                    self.stop()
                }
            }
        }
    }
}
