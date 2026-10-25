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
}

public struct Job: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let originalFilename: String
    public let durationSeconds: Double?
    public let model: String
    public let language: String?
    public let detectedLanguage: String?
    public let status: String
    public let progress: Double
    public let stage: String?
    public let errorMessage: String?
    public let wordCount: Int?
    public let createdAt: Date
    public let segments: [Segment]
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

    public init(fileURL: URL, model: String? = nil, language: String? = nil) {
        self.fileURL = fileURL
        self.model = model
        self.language = language
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
