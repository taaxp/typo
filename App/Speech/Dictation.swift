import Foundation
import AVFoundation
import Speech
import Observation

/// Live, on-device speech-to-text using the iOS/macOS 26 `SpeechAnalyzer` API.
///
/// Only the containing app can do this: iOS does not give keyboard extensions
/// microphone access, even with Full Access turned on.
@MainActor
@Observable
final class Dictation {
    enum State: Equatable { case idle, preparing, listening, failed(String) }

    private(set) var state: State = .idle
    /// Finalised text so far.
    private(set) var finalText = ""
    /// Text the recogniser may still revise.
    private(set) var volatileText = ""

    var transcript: String { (finalText + volatileText).trimmingCharacters(in: .whitespaces) }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private let engine = AVAudioEngine()

    func toggle() async {
        if state == .listening { await stop() } else { await start() }
    }

    func reset() {
        finalText = ""
        volatileText = ""
        if case .failed = state { state = .idle }
    }

    func start() async {
        guard state != .listening, state != .preparing else { return }
        state = .preparing
        do {
            guard await Self.requestMicrophone() else {
                state = .failed("Allow microphone access for Stash in Settings to dictate.")
                return
            }
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
                state = .failed("Dictation isn't available for your language yet.")
                return
            }
            let transcriber = SpeechTranscriber(locale: locale,
                                                transcriptionOptions: [],
                                                reportingOptions: [.volatileResults],
                                                attributeOptions: [])
            // Downloads the on-device model the first time for this language.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                state = .failed("No compatible audio format.")
                return
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (inputSequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
            self.analyzer = analyzer
            self.transcriber = transcriber
            self.inputBuilder = builder

            resultsTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        await MainActor.run {
                            guard let self else { return }
                            if result.isFinal {
                                self.finalText += text
                                self.volatileText = ""
                            } else {
                                self.volatileText = text
                            }
                        }
                    }
                } catch {
                    await MainActor.run { self?.state = .failed(error.localizedDescription) }
                }
            }

            try await analyzer.start(inputSequence: inputSequence)
            try startEngine(feeding: builder, analyzerFormat: analyzerFormat)
            state = .listening
        } catch {
            await stop()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputBuilder?.finish()
        inputBuilder = nil
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        if state == .listening || state == .preparing { state = .idle }
    }

    private func startEngine(feeding builder: AsyncStream<AnalyzerInput>.Continuation,
                             analyzerFormat: AVAudioFormat) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let input = engine.inputNode
        let micFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: micFormat, to: analyzerFormat) else {
            throw NSError(domain: "Stash.Dictation", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't convert microphone audio."])
        }
        Self.installTap(on: input, format: micFormat, converter: converter, analyzerFormat: analyzerFormat, builder: builder)
        engine.prepare()
        try engine.start()
    }

    /// Nonisolated so the tap closure isn't treated as main-actor code: Core Audio
    /// calls it on its own real-time thread.
    private nonisolated static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               converter: AVAudioConverter, analyzerFormat: AVAudioFormat,
                                               builder: AsyncStream<AnalyzerInput>.Continuation) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            if let converted = convert(buffer, with: converter, to: analyzerFormat) {
                builder.yield(AnalyzerInput(buffer: converted))
            }
        }
    }

    private nonisolated static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter,
                                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? out : nil
    }

    private static func requestMicrophone() async -> Bool {
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }
}
