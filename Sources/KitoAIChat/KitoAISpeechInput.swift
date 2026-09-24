//
//  KitoAISpeechInput.swift
//  KitoAIChat
//
//  Created by Wycliff on 9/24/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation
import AVFoundation
import Speech

/// Live dictation with the Speech framework. Needs `NSSpeechRecognitionUsageDescription` and
/// `NSMicrophoneUsageDescription`; without them, without permission, or without a usable
/// microphone (some simulators), `start()` reports why instead of crashing.
@MainActor
@Observable
final class KitoAISpeechInput {
    enum Phase: Equatable {
        case idle
        case requesting
        case listening
    }

    private(set) var phase: Phase = .idle
    /// What has been heard so far in this session.
    private(set) var transcript = ""
    /// Input loudness, 0…1, for the level rings.
    private(set) var level: Float = 0

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?

    var isListening: Bool { phase == .listening }

    static var hasUsageDescriptions: Bool {
        let bundle = Bundle.main
        return bundle.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
            && bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
    }

    /// Starts listening. Returns a message to show when voice input isn't available.
    func start() async -> String? {
        guard phase == .idle else { return nil }
        guard Self.hasUsageDescriptions else {
            return "Voice input needs speech and microphone usage descriptions in Info.plist."
        }
        phase = .requesting
        let speechAllowed = await Self.requestSpeechAuthorization()
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard speechAllowed, micAllowed else {
            phase = .idle
            return "Allow microphone and speech recognition in Settings to dictate."
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            phase = .idle
            return "Speech recognition isn't available right now."
        }
        do {
            try beginSession(with: recognizer)
            transcript = ""
            phase = .listening
            return nil
        } catch {
            teardown()
            phase = .idle
            return "No microphone is available for dictation."
        }
    }

    func stop() {
        guard phase != .idle else { return }
        request?.endAudio()
        teardown()
        phase = .idle
        level = 0
    }

    private func beginSession(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw KitoAIStreamError("No audio input") }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(for: request) { [weak self] level in
            Task { @MainActor [weak self] in self?.level = level }
        })
        engine.prepare()
        try engine.start()

        recognitionTask = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, isDone in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text { self.transcript = text }
                if isDone { self.stop() }
            }
        })
        self.engine = engine
        self.request = request
    }

    private func teardown() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        engine = nil
        request = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Built outside the main actor: the audio engine calls it on its own thread.
    nonisolated private static func tap(for request: SFSpeechAudioBufferRecognitionRequest, onLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            onLevel(level(of: buffer))
        }
    }

    /// Built outside the main actor: Speech calls it on its own queue.
    nonisolated private static func resultHandler(_ onUpdate: @escaping @Sendable (String?, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            onUpdate(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }

    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let rms = (sum / Float(count)).squareRoot()
        return min(1, rms * 12)
    }

    nonisolated private static func requestSpeechAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        guard status == .notDetermined else { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
