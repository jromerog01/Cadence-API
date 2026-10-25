import Foundation

public enum TextExporter {
    private static func duration(_ value: Double?) -> String {
        guard let value else { return "--:--" }
        let total = Int(value.rounded(.toNearestOrEven))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func timestamp(_ value: Double, separator: String) -> String {
        let total = Int((value * 1000).rounded(.toNearestOrEven))
        return String(format: "%02d:%02d:%02d%@%03d", total / 3_600_000,
                      total / 60_000 % 60, total / 1000 % 60, separator, total % 1000)
    }

    public static func render(_ job: Job, format: String) throws -> String {
        let language = job.detectedLanguage ?? job.language ?? "desconocido"
        switch format {
        case "txt":
            return "\(job.originalFilename)\nDuración: \(duration(job.durationSeconds)) · Idioma: \(language) · Modelo: \(job.model)\n\n"
                + job.segments.map { "[\(duration($0.startSeconds))] \($0.text)" }.joined(separator: "\n\n")
        case "md":
            return "# \(job.originalFilename)\n\n> Duración: \(duration(job.durationSeconds)) · Idioma: `\(language)` · Modelo: `\(job.model)`\n\n---\n\n"
                + job.segments.map { segment in
                    let speaker = segment.speaker.map { "**\($0)** " } ?? ""
                    return "\(speaker)`\(duration(segment.startSeconds))`\n\n\(segment.text)"
                }.joined(separator: "\n\n")
        case "srt":
            return job.segments.enumerated().map { index, segment in
                "\(index + 1)\n\(timestamp(segment.startSeconds, separator: ",")) --> \(timestamp(segment.endSeconds, separator: ","))\n\(segment.text)\n"
            }.joined(separator: "\n")
        case "vtt":
            return (["WEBVTT\n"] + job.segments.map {
                "\(timestamp($0.startSeconds, separator: ".")) --> \(timestamp($0.endSeconds, separator: "."))\n\($0.text)\n"
            }).joined(separator: "\n")
        case "json": return try json(job)
        default: throw CocoaError(.fileWriteUnsupportedScheme)
        }
    }

    private static func quoted(_ value: String?) throws -> String {
        guard let value else { return "null" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func json(_ job: Job) throws -> String {
        let rows = try job.segments.map { s in
            """
                {
                  "idx": \(s.idx),
                  "start_seconds": \(s.startSeconds),
                  "end_seconds": \(s.endSeconds),
                  "text": \(try quoted(s.text)),
                  "speaker": \(try quoted(s.speaker))
                }
            """
        }.joined(separator: ",\n")
        let segments = rows.isEmpty ? "[]" : "[\n\(rows)\n  ]"
        let durationValue = job.durationSeconds.map { String($0) } ?? "null"
        return """
        {
          "original_filename": \(try quoted(job.originalFilename)),
          "model": \(try quoted(job.model)),
          "language": \(try quoted(job.language)),
          "detected_language": \(try quoted(job.detectedLanguage)),
          "duration_seconds": \(durationValue),
          "segments": \(segments)
        }
        """
    }
}
