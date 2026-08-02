import Foundation
import NaturalLanguage

@main
private enum SubtitleCoreTests {
    static func main() throws {
        testLanguageIdentity()
        testChineseScriptConversion()
        testStructurePreservingTranslation()
        try testFormatConversion()
        try testTraditionalChineseFixture()
        print("Subtitle core tests passed")
    }

    private static func testLanguageIdentity() {
        precondition(LanguageIdentity.identifier("en-US") == "en")
        precondition(LanguageIdentity.identifier("en-GB") == "en")
        precondition(LanguageIdentity.identifier("zh-CN") == "zh-Hans")
        precondition(LanguageIdentity.identifier("zh-TW") == "zh-Hant")
        precondition(LanguageIdentity.identifier("zh-HK") == "zh-Hant")
        precondition(LanguageIdentity.matches("zh-Hant-TW", "zh-Hant-HK"))
        precondition(LanguageIdentity.autonym(for: "en-GB") == "English")
        precondition(LanguageIdentity.autonym(for: "zh-Hant-HK") == "繁體中文")
    }

    private static func testChineseScriptConversion() {
        let unit = SubtitleUnit(
            id: "0",
            lineIndex: 0,
            sourceText: "安靜的港口被晨霧籠罩。",
            prefix: "",
            suffix: ""
        )
        let translations = ChineseScriptConverter.translations(
            for: [unit],
            sourceIdentifier: "zh-Hant",
            targetIdentifier: "zh-Hans"
        )
        precondition(translations?["0"] == "安静的港口被晨雾笼罩。")
        precondition(ChineseScriptConverter.translations(
            for: [unit],
            sourceIdentifier: "zh-Hant",
            targetIdentifier: "en"
        ) == nil)
    }

    private static func testStructurePreservingTranslation() {
        let vtt = SubtitleDocument(
            text: "WEBVTT\n\nNOTE this is metadata\ndo not translate\n\n00:00:00.000 --> 00:00:02.000\n<i>Hello world</i>\nHello <b>again</b>\n\n",
            fileExtension: "vtt"
        )
        precondition(vtt.units.map(\.sourceText) == ["Hello world", "Hello again"])
        let vttRendered = vtt.render(using: ["6": "你好，世界", "7": "再次你好"])
        precondition(vttRendered.hasPrefix("WEBVTT\n\nNOTE this is metadata"))
        precondition(vttRendered.contains("00:00:00.000 --> 00:00:02.000"))
        precondition(vttRendered.contains("<i>你好，世界</i>"))
        precondition(vttRendered.contains("再次你好"))
        precondition(!vttRendered.contains("再次你好</b>"))

        let lrc = SubtitleDocument(
            text: "[ar:Artist]\n[00:01.00]First line\n[00:02.00][00:03.00]Second line",
            fileExtension: "lrc"
        )
        precondition(lrc.units.map(\.sourceText) == ["First line", "Second line"])
        let lrcRendered = lrc.render(using: ["1": "第一行", "2": "第二行"])
        precondition(lrcRendered.contains("[00:01.00]第一行"))
        precondition(lrcRendered.contains("[00:02.00][00:03.00]第二行"))

        let srt = SubtitleDocument(
            text: "1\n00:00:00,000 --> 00:00:02,000\nHello\nworld\n\n",
            fileExtension: "srt"
        )
        precondition(srt.units.map(\.sourceText) == ["Hello", "world"])
        precondition(srt.render(using: ["2": "你好", "3": "世界"])
            == "1\n00:00:00,000 --> 00:00:02,000\n你好\n世界\n\n")

        let ass = SubtitleDocument(
            text: "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\i1}Hello\\Nworld",
            fileExtension: "ass"
        )
        precondition(ass.units.map(\.sourceText) == ["Hello\nworld"])
        let assID = ass.units[0].id
        precondition(ass.render(using: [assID: "你好\n世界"])
            .contains("{\\i1}你好\\N世界"))
    }

    private static func testFormatConversion() throws {
        let srt = "1\n00:00:01,250 --> 00:00:03,500\nHello world\n\n2\n00:01:05,000 --> 00:01:07,000\nSecond line\n"
        let timeline = try SubtitleTimeline(text: srt, format: .srt)
        precondition(timeline.cues.count == 2)

        let vtt = timeline.render(as: .vtt)
        precondition(vtt.hasPrefix("WEBVTT\n\n"))
        precondition(vtt.contains("00:00:01.250 --> 00:00:03.500"))

        let lrc = timeline.render(as: .lrc)
        precondition(lrc.contains("[00:01.25]Hello world"))
        precondition(lrc.contains("[01:05.00]Second line"))

        let ass = timeline.render(as: .ass)
        precondition(ass.contains("[V4+ Styles]"))
        precondition(ass.contains("Dialogue: 0,0:00:01.25,0:00:03.50"))

        let roundTrip = try SubtitleTimeline(text: ass, format: .ass).render(as: .srt)
        precondition(roundTrip.contains("00:00:01,250 --> 00:00:03,500"))
        precondition(roundTrip.contains("Hello world"))
    }

    private static func testTraditionalChineseFixture() throws {
        guard CommandLine.arguments.count > 1 else {
            preconditionFailure("Traditional Chinese fixture path is required")
        }
        let text = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
        let document = SubtitleDocument(text: text, fileExtension: "srt")
        precondition(document.units.count == 3)

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(document.units.map(\.sourceText).joined(separator: "\n"))
        guard let language = recognizer.dominantLanguage else {
            preconditionFailure("Traditional Chinese language was not detected")
        }
        precondition(LanguageIdentity.identifier(language.rawValue) == "zh-Hant")
    }
}
