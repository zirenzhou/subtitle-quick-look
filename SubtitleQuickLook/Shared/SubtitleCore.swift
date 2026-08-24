import CoreFoundation
import Foundation

enum SubtitleFormat: String, CaseIterable, Sendable {
    case txt
    case vtt
    case srt
    case lrc
    case ass

    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "txt", "text": self = .txt
        case "vtt": self = .vtt
        case "srt": self = .srt
        case "lrc": self = .lrc
        case "ass", "ssa": self = .ass
        default: return nil
        }
    }

    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .txt: "Plain Text (.txt)"
        case .vtt: "WebVTT (.vtt)"
        case .srt: "SubRip (.srt)"
        case .lrc: "LRC (.lrc)"
        case .ass: "ASS / SSA (.ass)"
        }
    }

    var compactDisplayName: String {
        switch self {
        case .txt: "TXT"
        case .vtt: "VTT"
        case .srt: "SRT"
        case .lrc: "LRC"
        case .ass: "ASS"
        }
    }

    static let timedSubtitleCases: [SubtitleFormat] = [.vtt, .srt, .lrc, .ass]
}

struct LoadedText {
    let text: String
    let encoding: String.Encoding
    let wasTruncated: Bool
}

enum TextLoader {
    static let maximumPreviewBytes = 8 * 1_024 * 1_024
    static let maximumServiceBytes = 64 * 1_024 * 1_024

    static func loadPreview(from url: URL) throws -> LoadedText {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maximumPreviewBytes + 1) ?? Data()
        let wasTruncated = data.count > maximumPreviewBytes
        let previewData = wasTruncated ? Data(data.prefix(maximumPreviewBytes)) : data
        guard let decoded = decode(previewData) else {
            throw SubtitleCoreError.unsupportedEncoding
        }
        return LoadedText(text: decoded.text, encoding: decoded.encoding, wasTruncated: wasTruncated)
    }

    static func loadComplete(from url: URL) throws -> LoadedText {
        try load(from: url, maximumBytes: maximumServiceBytes)
    }

    private static func load(from url: URL, maximumBytes: Int) throws -> LoadedText {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else {
            throw SubtitleCoreError.fileTooLarge(maximumBytes: maximumBytes)
        }
        guard let decoded = decode(data) else {
            throw SubtitleCoreError.unsupportedEncoding
        }
        return LoadedText(text: decoded.text, encoding: decoded.encoding, wasTruncated: false)
    }

    private static func decode(_ data: Data) -> (text: String, encoding: String.Encoding)? {
        let byteOrderMarkedEncodings: [([UInt8], String.Encoding)] = [
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian),
            ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian),
            ([0xFE, 0xFF], .utf16BigEndian),
            ([0xFF, 0xFE], .utf16LittleEndian)
        ]
        for (marker, encoding) in byteOrderMarkedEncodings where data.starts(with: marker) {
            if let string = String(data: data, encoding: encoding) {
                return (string, encoding)
            }
        }

        if let string = String(data: data, encoding: .utf8) {
            return (string, .utf8)
        }

        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(0x0632)
            )
        )
        let shiftJIS = String(data: data, encoding: .shiftJIS)
        if let shiftJIS, containsJapaneseSyllabary(shiftJIS) {
            return (shiftJIS, .shiftJIS)
        }

        let japaneseEUC = String(data: data, encoding: .japaneseEUC)
        if let japaneseEUC, containsJapaneseSyllabary(japaneseEUC) {
            return (japaneseEUC, .japaneseEUC)
        }

        if let string = String(data: data, encoding: gb18030) {
            return (string, gb18030)
        }
        if let shiftJIS {
            return (shiftJIS, .shiftJIS)
        }
        if let japaneseEUC {
            return (japaneseEUC, .japaneseEUC)
        }
        for encoding in [String.Encoding.windowsCP1252, .isoLatin1] {
            if let string = String(data: data, encoding: encoding) {
                return (string, encoding)
            }
        }
        return nil
    }

    private static func containsJapaneseSyllabary(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value)
                || (0xFF66...0xFF9D).contains(scalar.value)
        }
    }
}

enum LanguageIdentity {
    static func identifier(_ rawIdentifier: String) -> String {
        let normalized = rawIdentifier.replacingOccurrences(of: "_", with: "-")
        let language = Locale.Language(identifier: normalized)
        guard let base = language.languageCode?.identifier else {
            return language.minimalIdentifier
        }

        if base == "zh" {
            let explicitScript = language.script?.identifier
            let maximal = language.maximalIdentifier
            return explicitScript == "Hant" || maximal.contains("-Hant-")
                ? "zh-Hant"
                : "zh-Hans"
        }

        return base
    }

    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        identifier(lhs) == identifier(rhs)
    }

    static func autonym(for rawIdentifier: String) -> String {
        let identifier = identifier(rawIdentifier)
        let autonymLocale = Locale(identifier: identifier)
        return autonymLocale.localizedString(forIdentifier: identifier)
            ?? Locale.Language(identifier: identifier).languageCode.flatMap {
                autonymLocale.localizedString(forLanguageCode: $0.identifier)
            }
            ?? identifier
    }
}

enum ChineseScriptConverter {
    static func translations(
        for units: [SubtitleUnit],
        sourceIdentifier: String,
        targetIdentifier: String
    ) -> [String: String]? {
        guard let transform = transform(
            sourceIdentifier: sourceIdentifier,
            targetIdentifier: targetIdentifier
        ) else { return nil }

        return Dictionary(uniqueKeysWithValues: units.map { unit in
            let translated = unit.sourceText.applyingTransform(transform, reverse: false)
                ?? unit.sourceText
            return (unit.id, translated)
        })
    }

    private static func transform(
        sourceIdentifier: String,
        targetIdentifier: String
    ) -> StringTransform? {
        switch (
            LanguageIdentity.identifier(sourceIdentifier),
            LanguageIdentity.identifier(targetIdentifier)
        ) {
        case ("zh-Hant", "zh-Hans"):
            StringTransform("Traditional-Simplified")
        case ("zh-Hans", "zh-Hant"):
            StringTransform("Simplified-Traditional")
        default:
            nil
        }
    }
}

struct SubtitleDocument {
    let lines: [String]
    let lineEnding: String
    let format: SubtitleFormat?
    let units: [SubtitleUnit]

    init(text: String, fileExtension: String) {
        lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        format = SubtitleFormat(fileExtension: fileExtension)

        switch format {
        case .txt:
            units = Self.parsePlainText(lines)
        case .lrc:
            units = Self.parseLRC(lines)
        case .vtt:
            units = Self.parseTimedCues(lines, skipsVTTBlocks: true)
        case .srt:
            units = Self.parseTimedCues(lines, skipsVTTBlocks: false)
        case .ass:
            units = Self.parseASS(lines)
        case nil:
            units = []
        }
    }

    func render(using translations: [String: String]) -> String {
        var rendered = lines
        for unit in units {
            guard var translation = translations[unit.id] else { continue }
            if unit.usesASSLineBreaks {
                translation = translation.replacingOccurrences(of: "\n", with: "\\N")
            }
            rendered[unit.lineIndex] = unit.prefix + translation + unit.suffix
        }
        return rendered.joined(separator: lineEnding)
    }

    func render(using translations: [String: String], as outputFormat: SubtitleFormat) throws -> String {
        let translatedSource = render(using: translations)
        guard outputFormat != format else { return translatedSource }
        guard let sourceFormat = format else { throw SubtitleCoreError.unsupportedFormat }
        return try SubtitleTimeline(text: translatedSource, format: sourceFormat)
            .render(as: outputFormat)
    }

    private static func parseTimedCues(_ lines: [String], skipsVTTBlocks: Bool) -> [SubtitleUnit] {
        var result: [SubtitleUnit] = []
        var insideCue = false
        var ignoredBlock = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                insideCue = false
                ignoredBlock = false
                continue
            }

            if skipsVTTBlocks && !insideCue {
                let upper = trimmed.uppercased()
                if upper == "STYLE" || upper == "REGION" || upper.hasPrefix("NOTE") {
                    ignoredBlock = true
                    continue
                }
            }

            if line.contains("-->") {
                insideCue = true
                ignoredBlock = false
                continue
            }

            guard insideCue, !ignoredBlock, let template = LineTemplate(line) else { continue }
            result.append(SubtitleUnit(
                id: String(index),
                lineIndex: index,
                sourceText: template.text,
                prefix: template.prefix,
                suffix: template.suffix
            ))
        }
        return result
    }

    private static func parsePlainText(_ lines: [String]) -> [SubtitleUnit] {
        lines.enumerated().compactMap { index, line in
            guard let template = LineTemplate(line) else { return nil }
            return SubtitleUnit(
                id: String(index),
                lineIndex: index,
                sourceText: template.text,
                prefix: template.prefix,
                suffix: template.suffix
            )
        }
    }

    private static func parseLRC(_ lines: [String]) -> [SubtitleUnit] {
        let expression = try! NSRegularExpression(
            pattern: "^((?:\\[\\d{1,3}:\\d{2}(?:[\\.:]\\d{1,3})?\\])+)(.*)$"
        )

        return lines.enumerated().compactMap { index, line in
            let range = NSRange(location: 0, length: (line as NSString).length)
            guard
                let match = expression.firstMatch(in: line, range: range),
                match.numberOfRanges == 3
            else { return nil }

            let string = line as NSString
            let timestamp = string.substring(with: match.range(at: 1))
            let content = string.substring(with: match.range(at: 2))
            guard let template = LineTemplate(content) else { return nil }

            return SubtitleUnit(
                id: String(index),
                lineIndex: index,
                sourceText: template.text,
                prefix: timestamp + template.prefix,
                suffix: template.suffix
            )
        }
    }

    private static func parseASS(_ lines: [String]) -> [SubtitleUnit] {
        var insideEvents = false
        var result: [SubtitleUnit] = []

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                insideEvents = trimmed.caseInsensitiveCompare("[Events]") == .orderedSame
                continue
            }
            guard insideEvents, let payloadRange = line.range(of: "Dialogue:", options: .caseInsensitive) else {
                continue
            }
            let payloadStart = payloadRange.upperBound
            let payload = String(line[payloadStart...])
            guard let textOffset = assTextOffset(in: payload) else { continue }
            let textStart = payload.index(payload.startIndex, offsetBy: textOffset)
            let content = String(payload[textStart...]).replacingOccurrences(of: "\\N", with: "\n")
            guard let template = LineTemplate(content) else { continue }
            let rawPrefix = String(line[..<payloadStart]) + String(payload[..<textStart])
            result.append(SubtitleUnit(
                id: String(index),
                lineIndex: index,
                sourceText: template.text,
                prefix: rawPrefix + template.prefix,
                suffix: template.suffix,
                usesASSLineBreaks: true
            ))
        }
        return result
    }
}

struct SubtitleUnit {
    let id: String
    let lineIndex: Int
    let sourceText: String
    let prefix: String
    let suffix: String
    var usesASSLineBreaks = false
}

private struct LineTemplate {
    let text: String
    let prefix: String
    let suffix: String

    init?(_ line: String) {
        let leading = String(line.prefix { $0.isWhitespace })
        let trailing = String(line.reversed().prefix { $0.isWhitespace }.reversed())
        var core = String(line.dropFirst(leading.count).dropLast(trailing.count))
        var prefix = leading
        var suffix = trailing
        var leadingTagCount = 0

        while core.first == "<", let end = core.firstIndex(of: ">") {
            let after = core.index(after: end)
            prefix += String(core[..<after])
            core = String(core[after...])
            leadingTagCount += 1
        }

        while core.first == "{", let end = core.firstIndex(of: "}") {
            let after = core.index(after: end)
            prefix += String(core[..<after])
            core = String(core[after...])
        }

        while leadingTagCount > 0, core.last == ">", let start = core.lastIndex(of: "<") {
            suffix = String(core[start...]) + suffix
            core = String(core[..<start])
            leadingTagCount -= 1
        }

        let visible = core
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{[^}]+\\}", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visible.isEmpty else { return nil }

        text = visible
        self.prefix = prefix
        self.suffix = suffix
    }
}

struct SubtitleCue: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

struct SubtitleTimeline: Sendable {
    let cues: [SubtitleCue]

    init(text: String, format: SubtitleFormat) throws {
        let parsed: [SubtitleCue]
        switch format {
        case .txt:
            throw SubtitleCoreError.unsupportedFormat
        case .vtt:
            parsed = Self.parseTimed(text, skipsVTTBlocks: true)
        case .srt:
            parsed = Self.parseTimed(text, skipsVTTBlocks: false)
        case .lrc:
            parsed = Self.parseLRC(text)
        case .ass:
            parsed = Self.parseASS(text)
        }
        guard !parsed.isEmpty else { throw SubtitleCoreError.noTimedCues }
        cues = parsed.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
    }

    func render(as format: SubtitleFormat) -> String {
        switch format {
        case .txt:
            return cues.map(\.text).joined(separator: "\n") + "\n"
        case .vtt:
            return "WEBVTT\n\n" + cues.enumerated().map { index, cue in
                "\(index + 1)\n\(Self.webVTTTime(cue.start)) --> \(Self.webVTTTime(cue.end))\n\(cue.text)"
            }.joined(separator: "\n\n") + "\n"
        case .srt:
            return cues.enumerated().map { index, cue in
                "\(index + 1)\n\(Self.srtTime(cue.start)) --> \(Self.srtTime(cue.end))\n\(cue.text)"
            }.joined(separator: "\n\n") + "\n"
        case .lrc:
            return cues.map { cue in
                "[\(Self.lrcTime(cue.start))]\(cue.text.replacingOccurrences(of: "\n", with: " "))"
            }.joined(separator: "\n") + "\n"
        case .ass:
            let header = """
            [Script Info]
            ScriptType: v4.00+
            WrapStyle: 0
            ScaledBorderAndShadow: yes
            PlayResX: 1920
            PlayResY: 1080

            [V4+ Styles]
            Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
            Style: Default,-apple-system,48,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,0,2,40,40,40,1

            [Events]
            Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            """
            let events = cues.map { cue in
                let text = cue.text.replacingOccurrences(of: "\n", with: "\\N")
                return "Dialogue: 0,\(Self.assTime(cue.start)),\(Self.assTime(cue.end)),Default,,0,0,0,,\(text)"
            }.joined(separator: "\n")
            return header + "\n" + events + "\n"
        }
    }

    private static func parseTimed(_ text: String, skipsVTTBlocks: Bool) -> [SubtitleCue] {
        let lines = normalizedLines(text)
        var cues: [SubtitleCue] = []
        var index = 0
        var ignoredBlock = false

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                ignoredBlock = false
                index += 1
                continue
            }
            if skipsVTTBlocks {
                let upper = trimmed.uppercased()
                if upper == "STYLE" || upper == "REGION" || upper.hasPrefix("NOTE") {
                    ignoredBlock = true
                    index += 1
                    continue
                }
            }
            guard !ignoredBlock, let arrow = lines[index].range(of: "-->") else {
                index += 1
                continue
            }

            let startText = String(lines[index][..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
            let endAndSettings = String(lines[index][arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            let endText = endAndSettings.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
            guard let start = parseTime(startText), let end = parseTime(endText) else {
                index += 1
                continue
            }

            index += 1
            var textLines: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textLines.append(cleanText(lines[index]))
                index += 1
            }
            let cueText = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cueText.isEmpty {
                cues.append(SubtitleCue(start: start, end: max(end, start + 0.01), text: cueText))
            }
        }
        return cues
    }

    private static func parseLRC(_ text: String) -> [SubtitleCue] {
        let expression = try! NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{2})(?:[\\.:](\\d{1,3}))?\\]")
        var cues: [SubtitleCue] = []

        for line in normalizedLines(text) {
            let nsLine = line as NSString
            let matches = expression.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }
            let lastEnd = matches.map { NSMaxRange($0.range) }.max() ?? 0
            let content = cleanText(nsLine.substring(from: lastEnd))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }

            for match in matches {
                let minutes = Double(nsLine.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(nsLine.substring(with: match.range(at: 2))) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound {
                    let value = nsLine.substring(with: match.range(at: 3))
                    fraction = (Double(value) ?? 0) / pow(10, Double(value.count))
                }
                cues.append(SubtitleCue(start: minutes * 60 + seconds + fraction, end: 0, text: content))
            }
        }

        cues.sort { $0.start < $1.start }
        for index in cues.indices {
            let nextStart = index + 1 < cues.count ? cues[index + 1].start : cues[index].start + 3
            cues[index].end = max(cues[index].start + 0.01, nextStart)
        }
        return cues
    }

    private static func parseASS(_ text: String) -> [SubtitleCue] {
        var insideEvents = false
        var cues: [SubtitleCue] = []

        for line in normalizedLines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                insideEvents = trimmed.caseInsensitiveCompare("[Events]") == .orderedSame
                continue
            }
            guard insideEvents, let colon = line.firstIndex(of: ":") else { continue }
            let kind = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard kind.caseInsensitiveCompare("Dialogue") == .orderedSame else { continue }
            let payload = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard let fields = splitASSFields(payload), fields.count == 10,
                  let start = parseTime(fields[1]), let end = parseTime(fields[2]) else { continue }
            let content = cleanText(fields[9].replacingOccurrences(of: "\\N", with: "\n"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: max(end, start + 0.01), text: content))
        }
        return cues
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{[^}]+\\}", with: "", options: .regularExpression)
    }

    private static func parseTime(_ raw: String) -> TimeInterval? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let hours = parts.count == 3 ? Double(parts[0]) ?? 0 : 0
        let minutesIndex = parts.count == 3 ? 1 : 0
        guard let minutes = Double(parts[minutesIndex]), let seconds = Double(parts[minutesIndex + 1]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func srtTime(_ seconds: TimeInterval) -> String {
        formatMilliseconds(seconds, separator: ",")
    }

    private static func webVTTTime(_ seconds: TimeInterval) -> String {
        formatMilliseconds(seconds, separator: ".")
    }

    private static func formatMilliseconds(_ seconds: TimeInterval, separator: Character) -> String {
        let total = max(0, Int((seconds * 1_000).rounded()))
        let hours = total / 3_600_000
        let minutes = (total / 60_000) % 60
        let secs = (total / 1_000) % 60
        let milliseconds = total % 1_000
        return String(format: "%02d:%02d:%02d%c%03d", hours, minutes, secs, separator.asciiValue ?? 46, milliseconds)
    }

    private static func lrcTime(_ seconds: TimeInterval) -> String {
        let totalHundredths = max(0, Int((seconds * 100).rounded()))
        return String(format: "%02d:%02d.%02d", totalHundredths / 6_000, (totalHundredths / 100) % 60, totalHundredths % 100)
    }

    private static func assTime(_ seconds: TimeInterval) -> String {
        let totalHundredths = max(0, Int((seconds * 100).rounded()))
        return String(format: "%d:%02d:%02d.%02d", totalHundredths / 360_000, (totalHundredths / 6_000) % 60, (totalHundredths / 100) % 60, totalHundredths % 100)
    }
}

private func assTextOffset(in payload: String) -> Int? {
    var commas = 0
    for (offset, character) in payload.enumerated() where character == "," {
        commas += 1
        if commas == 9 { return offset + 1 }
    }
    return nil
}

private func splitASSFields(_ payload: String) -> [String]? {
    guard let offset = assTextOffset(in: payload) else { return nil }
    let textStart = payload.index(payload.startIndex, offsetBy: offset)
    var fields = payload[..<textStart].dropLast().split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    fields.append(String(payload[textStart...]))
    return fields
}

enum SubtitleCoreError: LocalizedError {
    case unsupportedEncoding
    case unsupportedFormat
    case noTimedCues
    case fileTooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding: "The file's text encoding isn't supported."
        case .unsupportedFormat: "The subtitle format isn't supported."
        case .noTimedCues: "No timed subtitle cues were found."
        case let .fileTooLarge(maximumBytes): "The file exceeds the \(maximumBytes / 1_024 / 1_024) MiB processing limit."
        }
    }
}
