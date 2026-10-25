import Foundation

public struct User: Codable, Sendable, Equatable {
    public let id: String
    public let email: String
    public let displayName: String
}

public struct ModelInfo: Codable, Sendable, Equatable {
    public let name: String
    public let ramGb: Double
    public let speedFactor: Double
    public let role: String
}

public struct Segment: Codable, Sendable, Equatable {
    public let idx: Int
    public let startSeconds: Double
    public let endSeconds: Double
    public let text: String
    public let speaker: String?
    public init(idx: Int, startSeconds: Double, endSeconds: Double, text: String, speaker: String? = nil) {
        self.idx = idx; self.startSeconds = startSeconds; self.endSeconds = endSeconds
        self.text = text; self.speaker = speaker
    }
}

public struct Job: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var originalFilename: String
    public var durationSeconds: Double?
    public var model: String
    public var language: String?
    public var detectedLanguage: String?
    public var status: String
    public var progress: Double
    public var stage: String?
    public var errorMessage: String?
    public var wordCount: Int?
    public var createdAt: Date
    public var segments: [Segment]
    public init(id: String = UUID().uuidString, originalFilename: String,
                durationSeconds: Double? = nil, model: String, language: String? = nil,
                detectedLanguage: String? = nil, status: String = "queued", progress: Double = 0,
                stage: String? = nil, errorMessage: String? = nil, wordCount: Int? = nil,
                createdAt: Date = Date(), segments: [Segment] = []) {
        self.id = id; self.originalFilename = originalFilename
        self.durationSeconds = durationSeconds; self.model = model; self.language = language
        self.detectedLanguage = detectedLanguage; self.status = status; self.progress = progress
        self.stage = stage; self.errorMessage = errorMessage; self.wordCount = wordCount
        self.createdAt = createdAt; self.segments = segments
    }
}

public struct ImportJobPayload: Codable, Sendable, Equatable {
    public let originalFilename: String
    public let durationSeconds: Double?
    public let language: String?
    public let model: String
    public let segments: [Segment]

    public init(originalFilename: String, durationSeconds: Double? = nil, language: String? = nil, model: String = "apple-speech", segments: [Segment] = []) {
        self.originalFilename = originalFilename
        self.durationSeconds = durationSeconds
        self.language = language
        self.model = model
        self.segments = segments
    }

    public init(job: Job) {
        self.originalFilename = job.originalFilename
        self.durationSeconds = job.durationSeconds
        self.language = job.language ?? job.detectedLanguage
        self.model = job.model
        self.segments = job.segments
    }
}

public enum APIJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
            guard let date = fractional.date(from: value) ?? whole.date(from: value) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Fecha ISO 8601 inválida: \(value)"))
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

public struct TranscriptionRequest: Sendable {
    public let fileURL: URL
    public let model: String?
    public let language: String?
    public let jobID: String
    public let resumeSeconds: Double
    public let existingSegments: [Segment]

    public init(fileURL: URL, model: String? = nil, language: String? = nil,
                jobID: String = UUID().uuidString, resumeSeconds: Double = 0,
                existingSegments: [Segment] = []) {
        self.fileURL = fileURL
        self.model = model
        self.language = language
        self.jobID = jobID
        self.resumeSeconds = resumeSeconds
        self.existingSegments = existingSegments
    }
}

public enum Stage: String, Sendable {
    case uploading, queued, normalizing, transcribing, diarizing
}

public enum TranscriptionEvent: Sendable {
    case progress(fraction: Double, stage: Stage)
    case segments([Segment])
    case finished(Job)
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(_ request: TranscriptionRequest) -> AsyncThrowingStream<TranscriptionEvent, Error>
}
