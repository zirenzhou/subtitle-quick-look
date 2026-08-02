import AppKit
import Foundation
import NaturalLanguage
import SwiftUI
import Translation

@MainActor
final class SubtitleQuickLookAppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = SubtitleServiceProvider()
    private var terminationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppVisuals.applicationIcon
        NSApp.servicesProvider = serviceProvider
        NSApp.registerServicesMenuSendTypes([
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ], returnTypes: [])
        NSUpdateDynamicServices()

        serviceProvider.onActivity = { [weak self] in
            self?.terminationTask?.cancel()
        }
        serviceProvider.onFinished = { [weak self] in
            self?.scheduleTermination(after: .seconds(1))
        }

        if CommandLine.arguments.contains("--register-services") {
            scheduleTermination(after: .milliseconds(150))
        } else {
            scheduleTermination(after: .seconds(15))
        }
    }

    private func scheduleTermination(after duration: Duration) {
        terminationTask?.cancel()
        terminationTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            NSApp.terminate(nil)
        }
    }
}

@MainActor
final class SubtitleServiceProvider: NSObject {
    var onActivity: (() -> Void)?
    var onFinished: (() -> Void)?

    private var translationRunner: ServiceTranslationRunner?
    private var pendingTranslationTask: Task<Void, Never>?

    @objc func convertSubtitles(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        onActivity?()
        let urls = supportedURLs(from: pasteboard)
        guard !urls.isEmpty else {
            errorPointer.pointee = ServiceL10n.selectSubtitles as NSString
            onFinished?()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        guard let outputFormat = chooseOutputFormat() else {
            onFinished?()
            return
        }

        var failures: [String] = []
        for url in urls {
            do {
                let loaded = try TextLoader.loadComplete(from: url)
                guard let sourceFormat = SubtitleFormat(fileExtension: url.pathExtension) else {
                    throw SubtitleCoreError.unsupportedFormat
                }
                let output = try SubtitleTimeline(text: loaded.text, format: sourceFormat)
                    .render(as: outputFormat)
                let destination = uniqueConvertedURL(for: url, format: outputFormat)
                guard let data = output.data(using: .utf8) else {
                    throw SubtitleCoreError.unsupportedEncoding
                }
                try data.write(to: destination, options: .atomic)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            showError(title: ServiceL10n.convertFailed, details: failures)
        }
        onFinished?()
    }

    @objc func translateFiles(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        onActivity?()
        let urls = supportedURLs(from: pasteboard)
        guard !urls.isEmpty else {
            errorPointer.pointee = ServiceL10n.selectSubtitles as NSString
            onFinished?()
            return
        }

        pendingTranslationTask?.cancel()
        pendingTranslationTask = Task { [weak self] in
            let supported = await LanguageAvailability().supportedLanguages
            guard !Task.isCancelled, let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            guard let options = self.chooseTranslationOptions(
                for: urls,
                supportedLanguages: supported
            ) else {
                self.pendingTranslationTask = nil
                self.onFinished?()
                return
            }

            self.remember(target: options.targetIdentifier, for: urls.first)
            let runner = ServiceTranslationRunner(urls: urls, options: options)
            self.translationRunner = runner
            runner.onCompletion = { [weak self, weak runner] failures in
                guard let self else { return }
                if !failures.isEmpty {
                    self.showError(title: ServiceL10n.translateFailed, details: failures)
                }
                runner?.closeBridgeWindow()
                self.translationRunner = nil
                self.onFinished?()
            }
            self.pendingTranslationTask = nil
            runner.start()
        }
    }

    private func supportedURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let filenames = pasteboard.propertyList(forType: filenamesType) as? [String] {
            urls.append(contentsOf: filenames.map(URL.init(fileURLWithPath:)))
        }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            urls.append(contentsOf: objects)
        }

        var seen = Set<String>()
        return urls.filter { url in
            guard SubtitleFormat(fileExtension: url.pathExtension) != nil else { return false }
            return seen.insert(url.standardizedFileURL.path).inserted
        }
    }

    private func chooseOutputFormat() -> SubtitleFormat? {
        let alert = configuredAlert()
        alert.messageText = ServiceL10n.convertTitle
        alert.informativeText = ServiceL10n.convertExplanation
        alert.addButton(withTitle: ServiceL10n.convert)
        alert.addButton(withTitle: ServiceL10n.cancel)

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 148, height: 26))
        SubtitleFormat.allCases.forEach { popup.addItem(withTitle: $0.compactDisplayName) }
        if let srtIndex = SubtitleFormat.allCases.firstIndex(of: .srt) {
            popup.selectItem(at: srtIndex)
        }
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 226, height: 28))
        let formatLabel = NSTextField(labelWithString: ServiceL10n.outputFormat)
        formatLabel.alignment = .right
        formatLabel.frame = NSRect(x: 0, y: 3, width: 68, height: 22)
        popup.frame = NSRect(x: 78, y: 1, width: 148, height: 26)
        accessory.addSubview(formatLabel)
        accessory.addSubview(popup)
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return SubtitleFormat.allCases[max(0, popup.indexOfSelectedItem)]
    }

    private func chooseTranslationOptions(
        for urls: [URL],
        supportedLanguages: [Locale.Language]
    ) -> TranslationServiceOptions? {
        let languages = ServiceLanguageOption.make(from: supportedLanguages)
        guard !languages.isEmpty else {
            showError(title: ServiceL10n.translateFailed, details: [ServiceL10n.noLanguages])
            return nil
        }

        let detectedSource = urls.first.flatMap(detectedLanguage(at:))
        let defaultTarget = preferredTarget(
            sourceIdentifier: detectedSource,
            supportedLanguages: languages
        )

        let sourcePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 184, height: 26))
        sourcePopup.addItem(withTitle: ServiceL10n.autoDetect)
        languages.forEach { sourcePopup.addItem(withTitle: $0.name) }

        let targetPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 184, height: 26))
        languages.forEach { targetPopup.addItem(withTitle: $0.name) }
        if let targetIndex = languages.firstIndex(where: { $0.identifier == defaultTarget }) {
            targetPopup.selectItem(at: targetIndex)
        }

        let overwrite = NSButton(checkboxWithTitle: ServiceL10n.replaceOriginals, target: nil, action: nil)
        overwrite.state = .off
        overwrite.toolTip = ServiceL10n.replaceExplanation

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 294, height: 88))
        let sourceLabel = NSTextField(labelWithString: ServiceL10n.sourceLanguage)
        sourceLabel.alignment = .right
        sourceLabel.frame = NSRect(x: 0, y: 63, width: 92, height: 22)
        sourcePopup.frame = NSRect(x: 104, y: 61, width: 184, height: 26)

        let targetLabel = NSTextField(labelWithString: ServiceL10n.targetLanguage)
        targetLabel.alignment = .right
        targetLabel.frame = NSRect(x: 0, y: 33, width: 92, height: 22)
        targetPopup.frame = NSRect(x: 104, y: 31, width: 184, height: 26)
        overwrite.frame = NSRect(x: 104, y: 1, width: 190, height: 24)

        accessory.addSubview(sourceLabel)
        accessory.addSubview(sourcePopup)
        accessory.addSubview(targetLabel)
        accessory.addSubview(targetPopup)
        accessory.addSubview(overwrite)

        let alert = configuredAlert()
        alert.messageText = ServiceL10n.translateTitle
        alert.informativeText = ServiceL10n.translateExplanation
        alert.addButton(withTitle: ServiceL10n.translate)
        alert.addButton(withTitle: ServiceL10n.cancel)
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let sourceIndex = sourcePopup.indexOfSelectedItem
        let source = sourceIndex > 0 ? languages[sourceIndex - 1].identifier : nil
        let target = languages[max(0, targetPopup.indexOfSelectedItem)].identifier
        return TranslationServiceOptions(
            sourceIdentifier: source,
            targetIdentifier: target,
            outputPolicy: overwrite.state == .on ? .replaceOriginal : .saveCopy
        )
    }

    private func configuredAlert() -> NSAlert {
        let alert = NSAlert()
        alert.icon = AppVisuals.applicationIcon
        return alert
    }

    private func preferredTarget(
        sourceIdentifier: String?,
        supportedLanguages: [ServiceLanguageOption]
    ) -> String {
        let supported = Set(supportedLanguages.map(\.identifier))
        let primaryDevice = LanguageIdentity.identifier(Locale.preferredLanguages.first ?? "en")
        let defaults = UserDefaults(suiteName: "io.github.zirenzhou.subtitle-quick-look.preview")
        let primary = LanguageIdentity.identifier(
            defaults?.string(forKey: "translationTargetLanguage") ?? primaryDevice
        )
        let secondary = LanguageIdentity.identifier(
            defaults?.string(forKey: "translationSecondaryTargetLanguage")
                ?? defaultSecondaryTarget(excluding: primaryDevice)
        )
        let needsSecondary = sourceIdentifier.map {
            LanguageIdentity.matches($0, primaryDevice) || LanguageIdentity.matches($0, primary)
        } == true
        let preferred = needsSecondary ? secondary : primary
        if supported.contains(preferred) { return preferred }
        return supportedLanguages.first(where: { option in
            sourceIdentifier.map {
                !LanguageIdentity.matches($0, option.identifier)
            } ?? true
        })?.identifier ?? supportedLanguages[0].identifier
    }

    private func remember(target: String, for sourceURL: URL?) {
        let defaults = UserDefaults(suiteName: "io.github.zirenzhou.subtitle-quick-look.preview")
        let primaryDevice = LanguageIdentity.identifier(Locale.preferredLanguages.first ?? "en")
        let source = sourceURL.flatMap(detectedLanguage(at:))
        let key = source.map { LanguageIdentity.matches($0, primaryDevice) } == true
            ? "translationSecondaryTargetLanguage"
            : "translationTargetLanguage"
        defaults?.set(LanguageIdentity.identifier(target), forKey: key)
    }

    private func detectedLanguage(at url: URL) -> String? {
        guard
            let loaded = try? TextLoader.loadComplete(from: url),
            let format = SubtitleFormat(fileExtension: url.pathExtension)
        else { return nil }
        return ServiceLanguageDetector.detected(
            in: SubtitleDocument(text: loaded.text, fileExtension: format.fileExtension)
        )
    }

    private func defaultSecondaryTarget(excluding primary: String) -> String {
        for language in Locale.preferredLanguages.dropFirst() {
            let candidate = LanguageIdentity.identifier(language)
            if candidate != primary { return candidate }
        }
        return primary == "en" ? "zh-Hans" : "en"
    }

    private func uniqueConvertedURL(for sourceURL: URL, format: SubtitleFormat) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent("\(stem).\(format.fileExtension)")
        if candidate.standardizedFileURL == sourceURL.standardizedFileURL
            || FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-converted.\(format.fileExtension)")
        }
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem)-converted-\(suffix).\(format.fileExtension)")
            suffix += 1
        }
        return candidate
    }

    private func showError(title: String, details: [String]) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = configuredAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = details.joined(separator: "\n")
        alert.addButton(withTitle: ServiceL10n.ok)
        alert.runModal()
    }
}

private struct TranslationServiceOptions {
    enum OutputPolicy {
        case saveCopy
        case replaceOriginal
    }

    let sourceIdentifier: String?
    let targetIdentifier: String
    let outputPolicy: OutputPolicy
}

private struct ServiceLanguageOption {
    let identifier: String
    let name: String

    static func make(from languages: [Locale.Language]) -> [ServiceLanguageOption] {
        var seen = Set<String>()
        return languages
            .map { LanguageIdentity.identifier($0.minimalIdentifier) }
            .filter { seen.insert($0).inserted }
            .map { ServiceLanguageOption(identifier: $0, name: LanguageIdentity.autonym(for: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private enum ServiceLanguageDetector {
    static func detected(in document: SubtitleDocument) -> String? {
        let sample = document.units.prefix(60).map(\.sourceText).joined(separator: "\n")
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let hypothesis = recognizer.languageHypotheses(withMaximum: 1).first,
              hypothesis.value >= 0.65 else { return nil }
        return LanguageIdentity.identifier(hypothesis.key.rawValue)
    }
}

@MainActor
private final class ServiceTranslationRunner: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?
    var onCompletion: (([String]) -> Void)?

    private struct Job {
        let url: URL
        let loadedText: LoadedText
        let document: SubtitleDocument
        let sourceIdentifier: String?
        let targetIdentifier: String
        let outputPolicy: TranslationServiceOptions.OutputPolicy
        let localTranslations: [String: String]?
    }

    private var jobs: [Job] = []
    private var currentJob: Job?
    private var failures: [String] = []
    private var bridgeWindow: NSWindow?

    init(urls: [URL], options: TranslationServiceOptions) {
        for url in urls {
            do {
                let loaded = try TextLoader.loadComplete(from: url)
                let document = SubtitleDocument(text: loaded.text, fileExtension: url.pathExtension)
                guard !document.units.isEmpty else { throw SubtitleCoreError.noTimedCues }
                let source = options.sourceIdentifier ?? ServiceLanguageDetector.detected(in: document)
                if let source, LanguageIdentity.matches(source, options.targetIdentifier) {
                    continue
                }
                jobs.append(Job(
                    url: url,
                    loadedText: loaded,
                    document: document,
                    sourceIdentifier: source,
                    targetIdentifier: options.targetIdentifier,
                    outputPolicy: options.outputPolicy,
                    localTranslations: source.flatMap {
                        ChineseScriptConverter.translations(
                            for: document.units,
                            sourceIdentifier: $0,
                            targetIdentifier: options.targetIdentifier
                        )
                    }
                ))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func start() {
        prepareNextJob()
    }

    private func ensureBridgeWindow() {
        guard bridgeWindow == nil else { return }
        let hostingView = NSHostingView(rootView: ServiceTranslationBridge(runner: self))
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 2, height: 2),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.contentView = hostingView
        bridgeWindow = window
        window.orderFront(nil)
    }

    func translate(using session: TranslationSession) async {
        guard let job = currentJob else { return }
        do {
            var translations: [String: String] = [:]
            let requests = job.document.units.map {
                TranslationSession.Request(sourceText: $0.sourceText, clientIdentifier: $0.id)
            }
            for start in stride(from: 0, to: requests.count, by: 50) {
                let end = min(start + 50, requests.count)
                let responses = try await session.translations(from: Array(requests[start..<end]))
                for response in responses {
                    if let identifier = response.clientIdentifier {
                        translations[identifier] = response.targetText
                    }
                }
            }

            try write(translations, for: job)
        } catch {
            failures.append("\(job.url.lastPathComponent): \(error.localizedDescription)")
        }

        currentJob = nil
        try? await Task.sleep(for: .milliseconds(80))
        prepareNextJob()
    }

    func closeBridgeWindow() {
        bridgeWindow?.orderOut(nil)
        bridgeWindow?.close()
        bridgeWindow = nil
    }

    private func prepareNextJob() {
        while !jobs.isEmpty {
            let job = jobs.removeFirst()

            if let localTranslations = job.localTranslations {
                do {
                    try write(localTranslations, for: job)
                } catch {
                    failures.append("\(job.url.lastPathComponent): \(error.localizedDescription)")
                }
                continue
            }

            currentJob = job
            ensureBridgeWindow()
            let source = job.sourceIdentifier.map(Locale.Language.init(identifier:))
            let target = Locale.Language(identifier: job.targetIdentifier)
            if var existing = configuration {
                existing.source = source
                existing.target = target
                existing.invalidate()
                configuration = existing
            } else {
                configuration = TranslationSession.Configuration(source: source, target: target)
            }
            return
        }

        onCompletion?(failures)
    }

    private func write(_ translations: [String: String], for job: Job) throws {
        let output = job.document.render(using: translations)
        guard let data = output.data(
            using: job.loadedText.encoding,
            allowLossyConversion: false
        ) ?? output.data(using: .utf8) else {
            throw SubtitleCoreError.unsupportedEncoding
        }
        let destination: URL
        switch job.outputPolicy {
        case .replaceOriginal:
            destination = job.url
        case .saveCopy:
            destination = uniqueTranslatedURL(for: job.url, targetIdentifier: job.targetIdentifier)
        }
        try data.write(to: destination, options: .atomic)
    }

    private func uniqueTranslatedURL(for sourceURL: URL, targetIdentifier: String) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        let safeTarget = LanguageIdentity.identifier(targetIdentifier)
            .replacingOccurrences(of: "/", with: "-")
        var candidate = directory.appendingPathComponent("\(stem).\(safeTarget).\(fileExtension)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent(
                "\(stem).\(safeTarget)-\(suffix).\(fileExtension)"
            )
            suffix += 1
        }
        return candidate
    }
}

private struct ServiceTranslationBridge: View {
    @ObservedObject var runner: ServiceTranslationRunner

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(runner.configuration) { session in
                await runner.translate(using: session)
            }
    }
}

private enum AppVisuals {
    static var applicationIcon: NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        return NSImage(
            systemSymbolName: "captions.bubble.fill",
            accessibilityDescription: "Subtitle Quick Look"
        )?.withSymbolConfiguration(configuration)
    }
}

private enum ServiceL10n {
    private enum Language {
        case english
        case simplifiedChinese
        case traditionalChinese
        case japanese
        case korean
    }

    private static var language: Language {
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if identifier.hasPrefix("zh-hant") || identifier.contains("-tw")
            || identifier.contains("-hk") || identifier.contains("-mo") {
            return .traditionalChinese
        }
        if identifier.hasPrefix("zh") { return .simplifiedChinese }
        if identifier.hasPrefix("ja") { return .japanese }
        if identifier.hasPrefix("ko") { return .korean }
        return .english
    }

    static var convertTitle: String { localized("Convert Subtitles", "转换字幕", "轉換字幕", "字幕を変換", "자막 변환") }
    static var convertExplanation: String { localized(
        "Creates new files beside the originals. Only the subtitle format changes; the language stays the same.",
        "在原文件旁生成新文件。这里只转换字幕格式，不改变语言。",
        "在原檔案旁產生新檔案。這裡只轉換字幕格式，不改變語言。",
        "元のファイルの隣に新しいファイルを作成します。字幕形式のみを変換し、言語は変更しません。",
        "원본 옆에 새 파일을 만듭니다. 자막 형식만 변환하며 언어는 변경하지 않습니다."
    ) }
    static var translateTitle: String { localized("Translate Files", "翻译文件", "翻譯檔案", "ファイルを翻訳", "파일 번역") }
    static var translateExplanation: String { localized(
        "Choose the languages and how the translated files should be saved.",
        "选择语言，以及译文文件的保存方式。",
        "選擇語言，以及譯文檔案的儲存方式。",
        "言語と翻訳済みファイルの保存方法を選択します。",
        "언어와 번역된 파일의 저장 방식을 선택하세요."
    ) }
    static var selectSubtitles: String { localized(
        "Select one or more VTT, SRT, LRC, ASS, or SSA files.",
        "请选择一个或多个 VTT、SRT、LRC、ASS 或 SSA 文件。",
        "請選擇一個或多個 VTT、SRT、LRC、ASS 或 SSA 檔案。",
        "VTT、SRT、LRC、ASS、SSA ファイルを1つ以上選択してください。",
        "VTT, SRT, LRC, ASS 또는 SSA 파일을 하나 이상 선택하세요."
    ) }
    static var convertFailed: String { localized("Some subtitles could not be converted", "部分字幕无法转换", "部分字幕無法轉換", "一部の字幕を変換できませんでした", "일부 자막을 변환하지 못했습니다") }
    static var translateFailed: String { localized("Some subtitles could not be translated", "部分字幕无法翻译", "部分字幕無法翻譯", "一部の字幕を翻訳できませんでした", "일부 자막을 번역하지 못했습니다") }
    static var noLanguages: String { localized("No supported translation languages are available.", "没有可用的翻译语言。", "沒有可用的翻譯語言。", "利用可能な翻訳言語がありません。", "사용 가능한 번역 언어가 없습니다.") }
    static var outputFormat: String { localized("Format", "格式", "格式", "形式", "형식") }
    static var sourceLanguage: String { localized("From", "源语言", "來源語言", "翻訳元", "원본 언어") }
    static var targetLanguage: String { localized("To", "目标语言", "目標語言", "翻訳先", "대상 언어") }
    static var autoDetect: String { localized("Auto Detect", "自动检测", "自動偵測", "自動検出", "자동 감지") }
    static var replaceOriginals: String { localized("Replace original files", "替换原文件", "取代原檔案", "元のファイルを置き換える", "원본 파일 대체") }
    static var replaceExplanation: String { localized(
        "When off, translated copies use a language suffix and the originals stay unchanged.",
        "关闭时，译文会以语言后缀另存副本，原文件保持不变。",
        "關閉時，譯文會以語言後綴另存副本，原檔案保持不變。",
        "オフの場合、言語サフィックス付きのコピーを保存し、元のファイルは変更しません。",
        "끄면 언어 접미사가 붙은 사본을 저장하고 원본은 변경하지 않습니다."
    ) }
    static var convert: String { localized("Convert", "转换", "轉換", "変換", "변환") }
    static var translate: String { localized("Translate", "翻译", "翻譯", "翻訳", "번역") }
    static var cancel: String { localized("Cancel", "取消", "取消", "キャンセル", "취소") }
    static var ok: String { localized("OK", "好", "好", "OK", "확인") }

    private static func localized(
        _ english: String,
        _ simplifiedChinese: String,
        _ traditionalChinese: String,
        _ japanese: String,
        _ korean: String
    ) -> String {
        switch language {
        case .english: english
        case .simplifiedChinese: simplifiedChinese
        case .traditionalChinese: traditionalChinese
        case .japanese: japanese
        case .korean: korean
        }
    }
}
