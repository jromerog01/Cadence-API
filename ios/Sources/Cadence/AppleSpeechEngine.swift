import AVFoundation
import CadenceKit
import Speech

enum LocalSpeechError: LocalizedError {
    case unavailable, modelMissing, audioFormat, thermalPause
    var errorDescription: String? {
        switch self {
        case .unavailable: "Este dispositivo o idioma no admite la transcripción local."
        case .modelMissing: "Descarga primero el modelo del idioma en Ajustes."
        case .audioFormat: "Este audio no se puede leer en el iPhone. Puedes enviarlo al servidor."
        case .thermalPause: "El iPhone está caliente. La transcripción quedó pausada."
        }
    }
}

struct AppleSpeechEngine: TranscriptionEngine {
    static func downloadModel(language: String) async throws {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw LocalSpeechError.unavailable
        }
        let module = SpeechTranscriber(locale: locale, preset: .timeIndexedTranscriptionWithAlternatives)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    func transcribe(_ request: TranscriptionRequest) -> AsyncThrowingStream<TranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard SpeechTranscriber.isAvailable, let language = request.language,
                          let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
                        throw LocalSpeechError.unavailable
                    }
                    let installed = await SpeechTranscriber.installedLocales
                    guard installed.contains(locale) else { throw LocalSpeechError.modelMissing }
                    let module = SpeechTranscriber(locale: locale, preset: .timeIndexedTranscriptionWithAlternatives)
                    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
                        throw LocalSpeechError.audioFormat
                    }
                    let reader = try AudioReader(url: request.fileURL, sampleRate: format.sampleRate,
                                                 channels: format.channelCount, commonFormat: format.commonFormat,
                                                 interleaved: format.isInterleaved, offset: request.resumeSeconds)
                    let duration = reader.duration
                    let analyzer = SpeechAnalyzer(modules: [module])
                    let results = Task {
                        var segments = request.existingSegments
                        for try await result in module.results {
                            try Task.checkCancellation()
                            guard result.isFinal else { continue }
                            let start = request.resumeSeconds + result.range.start.seconds
                            let end = request.resumeSeconds + CMTimeRangeGetEnd(result.range).seconds
                            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard start.isFinite, end.isFinite, end >= start, !text.isEmpty else { continue }
                            let segment = Segment(idx: segments.count, startSeconds: start, endSeconds: end, text: text)
                            segments.append(segment)
                            continuation.yield(.segments([segment]))
                            continuation.yield(.progress(fraction: min(end / max(duration, 1), 1), stage: .transcribing))
                        }
                        return segments
                    }
                    do {
                        try await analyzer.start(inputSequence: AudioInputs(reader: reader))
                        try await analyzer.finalizeAndFinishThroughEndOfInput()
                        let segments = try await results.value
                        let job = Job(id: request.jobID, originalFilename: request.fileURL.lastPathComponent,
                                      durationSeconds: duration, model: "apple-speech", language: language,
                                      detectedLanguage: language, status: "done", progress: 1,
                                      wordCount: segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count },
                                      segments: segments)
                        continuation.yield(.finished(job))
                        continuation.finish()
                    } catch {
                        results.cancel()
                        await analyzer.cancelAndFinishNow()
                        throw error
                    }
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private struct AudioInputs: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput
    let reader: AudioReader
    struct AsyncIterator: AsyncIteratorProtocol {
        let reader: AudioReader
        mutating func next() async throws -> AnalyzerInput? { try await reader.next() }
    }
    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(reader: reader) }
}

private actor AudioReader {
    private let file: AVAudioFile
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private var outputFrames: Int64 = 0
    private var drained = false
    nonisolated let duration: Double

    init(url: URL, sampleRate: Double, channels: AVAudioChannelCount, commonFormat: AVAudioCommonFormat,
         interleaved: Bool, offset: Double) throws {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(commonFormat: commonFormat, sampleRate: sampleRate,
                                         channels: channels, interleaved: interleaved),
              let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw LocalSpeechError.audioFormat
        }
        self.file = file; self.target = target; self.converter = converter
        duration = Double(file.length) / file.processingFormat.sampleRate
        file.framePosition = min(file.length, AVAudioFramePosition(offset * file.processingFormat.sampleRate))
    }

    func next() throws -> AnalyzerInput? {
        try Task.checkCancellation()
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            throw LocalSpeechError.thermalPause
        }
        guard !drained else { return nil }
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192),
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(ceil(8192 * target.sampleRate / file.processingFormat.sampleRate)) + 512) else {
            throw LocalSpeechError.audioFormat
        }
        let endOfFile = file.framePosition >= file.length
        if !endOfFile { try file.read(into: input) }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if endOfFile { state.pointee = .endOfStream; return nil }
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true
            state.pointee = .haveData
            return input
        }
        if let error { throw error }
        if status == .endOfStream { drained = true }
        guard status != .error else { throw LocalSpeechError.audioFormat }
        if output.frameLength == 0 { return try next() }
        let time = CMTime(value: outputFrames, timescale: CMTimeScale(target.sampleRate))
        outputFrames += Int64(output.frameLength)
        return AnalyzerInput(buffer: output, bufferStartTime: time)
    }
}
