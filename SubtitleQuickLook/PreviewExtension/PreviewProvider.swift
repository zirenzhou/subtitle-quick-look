import AppKit
import Carbon
import CoreFoundation
import Foundation
import NaturalLanguage
import QuickLookUI
import SwiftUI
import Translation
import UniformTypeIdentifiers

final class PreviewProvider: NSViewController, QLPreviewingController {
    private let model = PreviewModel()

    override func loadView() {
        view = NSHostingView(rootView: PreviewRootView(model: model))
        preferredContentSize = NSSize(width: 800, height: 1_000)
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        Task {
            do {
                let payload = try await Task.detached {
                    let didAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if didAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }

                    let loaded = try TextLoader.loadPreview(from: url)
                    return PreviewPayload(
                        url: url,
                        loadedText: loaded,
                        document: SubtitleDocument(text: loaded.text, fileExtension: url.pathExtension)
                    )
                }.value

                model.load(payload)
                handler(nil)
            } catch {
                handler(error)
            }
        }
    }
}

@MainActor
private final class PreviewModel: ObservableObject {
    @Published private(set) var originalText = ""
    @Published private(set) var translatedText = ""
    @Published private(set) var filename = ""
    @Published private(set) var isTranslating = false
    @Published private(set) var translationProgress = 0.0
    @Published private(set) var isSaving = false
    @Published private(set) var didSave = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var noticeMessage: String?
    @Published private(set) var commonLanguages: [LanguageOption] = []
    @Published private(set) var otherLanguages: [LanguageOption] = []
    @Published var configuration: TranslationSession.Configuration?
    @Published private(set) var translationIsOpen: Bool

    weak var hostWindow: NSWindow?

    private var fileURL: URL?
    private var loadedText: LoadedText?
    private var document: SubtitleDocument?
    private var allLanguages: [LanguageOption] = []
    private var detectedDocumentLanguageIdentifier: String?
    private var usingSecondaryTarget = false
    private var translations: [String: String] = [:]
    private var translationRevision = UUID()
    private var noticeRevision = UUID()
    private var progressTask: Task<Void, Never>?
    private var recentLanguageIdentifiers: [String]

    private let defaults = UserDefaults.standard
    private let enabledKey = "translationEnabled"
    private let sourceKey = "translationSourceLanguage"
    private let targetKey = "translationTargetLanguage"
    private let secondaryTargetKey = "translationSecondaryTargetLanguage"
    private let recentLanguagesKey = "translationRecentLanguages"
    private let maximumCommonLanguages = 6
    private let primaryDeviceLanguageIdentifier: String
    private var primaryTargetIdentifier: String
    private var secondaryTargetIdentifier: String

    private(set) var sourceIdentifier: String?
    private(set) var targetIdentifier: String

    init() {
        let primaryDeviceLanguage = LanguageIdentity.identifier(Self.systemLanguageIdentifier)
        let storedPrimaryTarget = defaults.string(forKey: targetKey) ?? primaryDeviceLanguage
        let storedSecondaryTarget = defaults.string(forKey: secondaryTargetKey)
            ?? Self.defaultSecondaryTarget(excluding: primaryDeviceLanguage)

        primaryDeviceLanguageIdentifier = primaryDeviceLanguage
        primaryTargetIdentifier = LanguageIdentity.identifier(storedPrimaryTarget)
        secondaryTargetIdentifier = LanguageIdentity.identifier(storedSecondaryTarget)
        translationIsOpen = defaults.bool(forKey: enabledKey)
        sourceIdentifier = defaults.string(forKey: sourceKey).map(LanguageIdentity.identifier)
        targetIdentifier = primaryTargetIdentifier
        recentLanguageIdentifiers = defaults.stringArray(forKey: recentLanguagesKey)?
            .map(LanguageIdentity.identifier) ?? []
    }

    var visibleText: String {
        translationIsOpen && !translatedText.isEmpty ? translatedText : originalText
    }

    var canSave: Bool {
        translationIsOpen
            && !isTranslating
            && !isSaving
            && !translations.isEmpty
            && loadedText?.wasTruncated == false
    }

    var autoLabel: String { L10n.auto }

    var sourceLanguageName: String {
        guard let sourceIdentifier else { return autoLabel }
        return languageName(for: sourceIdentifier)
    }

    var targetLanguageName: String {
        languageName(for: targetIdentifier)
    }

    func load(_ payload: PreviewPayload) {
        fileURL = payload.url
        loadedText = payload.loadedText
        document = payload.document
        filename = payload.url.lastPathComponent
        originalText = payload.loadedText.wasTruncated
            ? payload.loadedText.text + "\n\n" + L10n.truncated
            : payload.loadedText.text
        translatedText = ""
        translations = [:]
        errorMessage = nil
        noticeMessage = nil
        progressTask?.cancel()
        translationProgress = 0
        detectedDocumentLanguageIdentifier = Self.detectedSourceLanguage(in: payload.document)
        usingSecondaryTarget = false
        targetIdentifier = primaryTargetIdentifier
        translationIsOpen = defaults.bool(forKey: enabledKey)
            && !isPrimaryDeviceLanguageDocument

        if translationIsOpen {
            beginTranslation()
        }
        Task { await loadSupportedLanguages() }
    }

    func setHostWindow(_ window: NSWindow?) {
        hostWindow = window
    }

    func openTranslation() {
        noticeMessage = nil
        usingSecondaryTarget = shouldUseSecondaryForManualTranslation
        if usingSecondaryTarget {
            targetIdentifier = secondaryTargetIdentifier
        } else {
            targetIdentifier = primaryTargetIdentifier
        }
        translationIsOpen = true
        defaults.set(true, forKey: enabledKey)
        rebuildLanguageMenus()
        beginTranslation()
    }

    func closeTranslation() {
        translationIsOpen = false
        defaults.set(false, forKey: enabledKey)
        translationRevision = UUID()
        progressTask?.cancel()
        translationProgress = 0
        isTranslating = false
        errorMessage = nil
    }

    func setSource(_ identifier: String?) {
        sourceIdentifier = identifier.map(LanguageIdentity.identifier)
        if let sourceIdentifier {
            defaults.set(sourceIdentifier, forKey: sourceKey)
            rememberLanguage(sourceIdentifier)
        } else {
            defaults.removeObject(forKey: sourceKey)
        }
        rebuildLanguageMenus()
        beginTranslation()
    }

    func setTarget(_ identifier: String) {
        targetIdentifier = LanguageIdentity.identifier(identifier)
        if usingSecondaryTarget {
            if detectedDocumentLanguageIdentifier.map({
                LanguageIdentity.matches($0, targetIdentifier)
            }) != true {
                secondaryTargetIdentifier = targetIdentifier
                defaults.set(targetIdentifier, forKey: secondaryTargetKey)
            }
        } else {
            primaryTargetIdentifier = targetIdentifier
            defaults.set(targetIdentifier, forKey: targetKey)
        }
        rememberLanguage(targetIdentifier)
        rebuildLanguageMenus()
        beginTranslation()
    }

    func translate(using session: TranslationSession) async {
        guard translationIsOpen, let document else { return }
        let revision = translationRevision
        let units = document.units

        guard !units.isEmpty else {
            progressTask?.cancel()
            translationProgress = 0
            isTranslating = false
            errorMessage = L10n.noSubtitleText
            return
        }

        do {
            var translated: [String: String] = [:]
            let requests = units.map {
                TranslationSession.Request(sourceText: $0.sourceText, clientIdentifier: $0.id)
            }

            for start in stride(from: 0, to: requests.count, by: 50) {
                guard translationIsOpen, translationRevision == revision else { return }
                let end = min(start + 50, requests.count)
                let responses = try await session.translations(from: Array(requests[start..<end]))
                guard translationIsOpen, translationRevision == revision else { return }
                if let detectedSource = responses.first?.sourceLanguage,
                   LanguageIdentity.matches(
                    detectedSource.minimalIdentifier,
                    targetIdentifier
                   ) {
                    finishWithoutTranslation()
                    return
                }
                for response in responses {
                    if let identifier = response.clientIdentifier {
                        translated[identifier] = response.targetText
                    }
                }
                let completedFraction = Double(end) / Double(requests.count)
                translationProgress = max(translationProgress, completedFraction * 0.9)
            }

            guard translationIsOpen, translationRevision == revision else { return }
            translations = translated
            progressTask?.cancel()
            translationProgress = 1
            try? await Task.sleep(for: .milliseconds(240))
            guard translationIsOpen, translationRevision == revision else { return }
            translatedText = document.render(using: translated)
            isTranslating = false
        } catch {
            guard translationRevision == revision else { return }
            if TranslationError.unsupportedLanguagePairing ~= error {
                finishWithoutTranslation()
                return
            }
            progressTask?.cancel()
            translationProgress = 0
            isTranslating = false
            errorMessage = error.localizedDescription
        }
    }

    func requestSaveAs() {
        guard canSave, let fileURL, let sourceFormat = document?.format else { return }
        guard let window = hostWindow else {
            errorMessage = L10n.cannotShowSavePanel
            return
        }

        let panel = NSSavePanel()
        panel.title = L10n.saveTranslatedSubtitle
        panel.prompt = L10n.saveAs
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = fileURL.deletingLastPathComponent()
        panel.nameFieldStringValue = suggestedFilename(for: fileURL, outputFormat: sourceFormat)
        panel.allowedContentTypes = [contentType(for: sourceFormat)]

        let accessory = SaveFormatAccessoryController(originalFormat: sourceFormat)
        accessory.onChange = { [weak panel, weak self] format in
            guard let panel, let self else { return }
            panel.allowedContentTypes = [self.contentType(for: format)]
            panel.nameFieldStringValue = self.suggestedFilename(
                for: fileURL,
                outputFormat: format
            )
        }
        panel.accessoryView = accessory.view

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destinationURL = panel.url else { return }
            let outputFormat = accessory.selectedFormat
            Task { @MainActor in
                self?.saveTranslatedCopy(to: destinationURL, outputFormat: outputFormat)
            }
        }
    }

    private func beginTranslation() {
        guard translationIsOpen, let document else { return }
        let effectiveSource = sourceIdentifier
            ?? detectedDocumentLanguageIdentifier
            ?? Self.detectedSourceLanguage(in: document)
        if let effectiveSource,
           LanguageIdentity.matches(effectiveSource, targetIdentifier) {
            finishWithoutTranslation()
            return
        }
        isTranslating = true
        errorMessage = nil
        translatedText = ""
        translations = [:]
        translationRevision = UUID()
        translationProgress = 0
        startProgressAnimation(for: translationRevision)

        if let effectiveSource,
           let localTranslations = ChineseScriptConverter.translations(
               for: document.units,
               sourceIdentifier: effectiveSource,
               targetIdentifier: targetIdentifier
           ) {
            configuration = nil
            completeLocalTranslation(
                localTranslations,
                document: document,
                revision: translationRevision
            )
            return
        }

        let source = sourceIdentifier.map(Locale.Language.init(identifier:))
        let target = Locale.Language(identifier: targetIdentifier)
        if var existing = configuration {
            existing.source = source
            existing.target = target
            existing.invalidate()
            configuration = existing
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    private func completeLocalTranslation(
        _ translated: [String: String],
        document: SubtitleDocument,
        revision: UUID
    ) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self,
                  self.translationIsOpen,
                  self.translationRevision == revision else { return }
            self.translations = translated
            self.progressTask?.cancel()
            self.translationProgress = 1
            try? await Task.sleep(for: .milliseconds(180))
            guard self.translationIsOpen,
                  self.translationRevision == revision else { return }
            self.translatedText = document.render(using: translated)
            self.isTranslating = false
        }
    }

    private func startProgressAnimation(for revision: UUID) {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }

                guard
                    let self,
                    self.translationIsOpen,
                    self.isTranslating,
                    self.translationRevision == revision
                else { return }

                let remaining = 0.88 - self.translationProgress
                guard remaining > 0 else { continue }
                self.translationProgress += max(0.004, remaining * 0.035)
            }
        }
    }

    private func finishWithoutTranslation() {
        translationRevision = UUID()
        progressTask?.cancel()
        translationProgress = 0
        isTranslating = false
        translatedText = ""
        translations = [:]
        errorMessage = nil
        translationIsOpen = false

        let revision = UUID()
        noticeRevision = revision
        noticeMessage = L10n.noTranslationNeeded
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, self.noticeRevision == revision else { return }
            self.noticeMessage = nil
        }
    }

    private static func detectedSourceLanguage(in document: SubtitleDocument) -> String? {
        let sample = document.units
            .prefix(40)
            .map(\.sourceText)
            .joined(separator: "\n")
        guard !sample.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard
            let hypothesis = recognizer.languageHypotheses(withMaximum: 1).first,
            hypothesis.value >= 0.8
        else { return nil }
        return hypothesis.key.rawValue
    }

    private var isPrimaryDeviceLanguageDocument: Bool {
        detectedDocumentLanguageIdentifier.map {
            LanguageIdentity.matches($0, primaryDeviceLanguageIdentifier)
        } == true
    }

    private var shouldUseSecondaryForManualTranslation: Bool {
        guard let detectedDocumentLanguageIdentifier else { return false }
        return LanguageIdentity.matches(
            detectedDocumentLanguageIdentifier,
            primaryDeviceLanguageIdentifier
        ) || LanguageIdentity.matches(
            detectedDocumentLanguageIdentifier,
            primaryTargetIdentifier
        )
    }

    private func suggestedFilename(for fileURL: URL, outputFormat: SubtitleFormat) -> String {
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let language = targetIdentifier.replacingOccurrences(of: "/", with: "-")
        return "\(stem).\(language).\(outputFormat.fileExtension)"
    }

    private func contentType(for format: SubtitleFormat) -> UTType {
        UTType(filenameExtension: format.fileExtension) ?? .plainText
    }

    private func saveTranslatedCopy(to destinationURL: URL, outputFormat: SubtitleFormat) {
        guard
            let loadedText,
            let document,
            canSave
        else { return }

        let output: String
        do {
            output = try document.render(using: translations, as: outputFormat)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let outputEncoding = outputFormat == document.format ? loadedText.encoding : .utf8
        guard let data = output.data(using: outputEncoding, allowLossyConversion: false)
            ?? output.data(using: .utf8)
        else {
            errorMessage = L10n.cannotEncode
            return
        }

        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await Task.detached {
                    let didAccess = destinationURL.startAccessingSecurityScopedResource()
                    defer {
                        if didAccess {
                            destinationURL.stopAccessingSecurityScopedResource()
                        }
                    }
                    try data.write(to: destinationURL, options: .atomic)
                }.value
                isSaving = false
                didSave = true
                try? await Task.sleep(for: .seconds(1.5))
                didSave = false
            } catch {
                isSaving = false
                errorMessage = L10n.saveFailed
            }
        }
    }

    private func loadSupportedLanguages() async {
        let supported = await LanguageAvailability().supportedLanguages
        var optionsByIdentifier: [String: LanguageOption] = [:]
        for language in supported {
            let identifier = LanguageIdentity.identifier(language.minimalIdentifier)
            optionsByIdentifier[identifier] = LanguageOption(
                id: identifier,
                name: LanguageIdentity.autonym(for: identifier)
            )
        }
        allLanguages = optionsByIdentifier.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        guard !allLanguages.isEmpty else { return }
        let previousTarget = targetIdentifier
        primaryTargetIdentifier = resolvedTarget(
            preferred: [primaryTargetIdentifier, primaryDeviceLanguageIdentifier, "en"]
        )
        secondaryTargetIdentifier = resolvedTarget(
            preferred: [
                secondaryTargetIdentifier,
                Self.defaultSecondaryTarget(excluding: primaryDeviceLanguageIdentifier),
                "en"
            ],
            excluding: primaryDeviceLanguageIdentifier
        )
        targetIdentifier = usingSecondaryTarget
            ? secondaryTargetIdentifier
            : primaryTargetIdentifier
        defaults.set(primaryTargetIdentifier, forKey: targetKey)
        defaults.set(secondaryTargetIdentifier, forKey: secondaryTargetKey)
        if let sourceIdentifier,
           !allLanguages.contains(where: { $0.id == sourceIdentifier }) {
            self.sourceIdentifier = nil
            defaults.removeObject(forKey: sourceKey)
        }
        recentLanguageIdentifiers = Self.uniqueLanguageIdentifiers(recentLanguageIdentifiers)
        defaults.set(recentLanguageIdentifiers, forKey: recentLanguagesKey)
        rebuildLanguageMenus()
        if translationIsOpen, previousTarget != targetIdentifier {
            beginTranslation()
        }
    }

    private func resolvedTarget(
        preferred: [String],
        excluding excludedIdentifier: String? = nil
    ) -> String {
        let excludedIdentity = excludedIdentifier.map(LanguageIdentity.identifier)
        for candidate in preferred.map(LanguageIdentity.identifier) {
            guard candidate != excludedIdentity else { continue }
            if allLanguages.contains(where: { $0.id == candidate }) {
                return candidate
            }
        }
        return allLanguages.first(where: { $0.id != excludedIdentity })?.id
            ?? allLanguages.first?.id
            ?? "en"
    }

    private func languageName(for identifier: String) -> String {
        commonLanguages.first(where: { $0.id == identifier })?.name
            ?? otherLanguages.first(where: { $0.id == identifier })?.name
            ?? LanguageIdentity.autonym(for: identifier)
    }

    private func rememberLanguage(_ identifier: String) {
        let identity = LanguageIdentity.identifier(identifier)
        recentLanguageIdentifiers.removeAll { $0 == identity }
        recentLanguageIdentifiers.insert(identity, at: 0)
        recentLanguageIdentifiers = Array(recentLanguageIdentifiers.prefix(maximumCommonLanguages))
        defaults.set(recentLanguageIdentifiers, forKey: recentLanguagesKey)
    }

    private func rebuildLanguageMenus() {
        guard !allLanguages.isEmpty else { return }
        let supportedIDs = Set(allLanguages.map(\.id))
        let deviceIDs = Self.deviceLanguageIdentifiers(supported: allLanguages)
        let selected = [sourceIdentifier, targetIdentifier].compactMap { $0 }
        var commonIDs: [String] = []

        func appendIfNeeded(_ identifier: String) {
            guard
                commonIDs.count < maximumCommonLanguages,
                supportedIDs.contains(identifier),
                !commonIDs.contains(identifier)
            else { return }
            commonIDs.append(identifier)
        }

        selected.forEach(appendIfNeeded)
        deviceIDs.prefix(4).forEach(appendIfNeeded)
        recentLanguageIdentifiers.forEach(appendIfNeeded)
        deviceIDs.forEach(appendIfNeeded)

        if commonIDs.count < maximumCommonLanguages {
            allLanguages.map(\.id).prefix(1).forEach(appendIfNeeded)
        }

        let rank = Dictionary(uniqueKeysWithValues: commonIDs.enumerated().map { ($1, $0) })
        commonLanguages = allLanguages
            .filter { rank[$0.id] != nil }
            .sorted { rank[$0.id, default: Int.max] < rank[$1.id, default: Int.max] }
        otherLanguages = allLanguages.filter { rank[$0.id] == nil }
    }

    private static func deviceLanguageIdentifiers(
        supported: [LanguageOption]
    ) -> [String] {
        var signals = Locale.preferredLanguages
        signals.append(Locale.current.identifier)
        signals.append(contentsOf: keyboardLanguageIdentifiers())
        signals.append(contentsOf: timeZoneLanguageIdentifiers())
        signals.append("en")

        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ identifier: String) {
            guard seen.insert(identifier).inserted else { return }
            ordered.append(identifier)
        }

        for signal in signals {
            let identity = LanguageIdentity.identifier(signal)
            if let exact = supported.first(where: { $0.id == identity }) {
                append(exact.id)
            }

            if identity == "zh-Hans" || identity == "zh-Hant" {
                for relatedIdentity in ["zh-Hans", "zh-Hant"] {
                    if let related = supported.first(where: { $0.id == relatedIdentity }) {
                        append(related.id)
                    }
                }
            }
        }

        return ordered
    }

    private static func uniqueLanguageIdentifiers(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        return identifiers
            .map(LanguageIdentity.identifier)
            .filter { seen.insert($0).inserted }
    }

    private static func keyboardLanguageIdentifiers() -> [String] {
        let filter = [
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String
        ] as CFDictionary
        guard let sourceList = TISCreateInputSourceList(filter, false) else { return [] }
        let inputSources = sourceList.takeRetainedValue() as NSArray
        var identifiers: [String] = []

        for case let inputSource as TISInputSource in inputSources {
            guard
                let rawLanguages = TISGetInputSourceProperty(
                    inputSource,
                    kTISPropertyInputSourceLanguages
                )
            else { continue }
            let languages = Unmanaged<CFArray>
                .fromOpaque(rawLanguages)
                .takeUnretainedValue() as? [String]
            if let primaryLanguage = languages?.first {
                identifiers.append(primaryLanguage)
            }
        }

        return identifiers
    }

    private static func timeZoneLanguageIdentifiers() -> [String] {
        let identifier = TimeZone.current.identifier

        switch identifier {
        case "Asia/Tokyo": return ["ja"]
        case "Asia/Seoul": return ["ko"]
        case "Asia/Shanghai", "Asia/Chongqing", "Asia/Urumqi": return ["zh-Hans"]
        case "Asia/Hong_Kong", "Asia/Macau", "Asia/Taipei": return ["zh-Hant"]
        case "Asia/Singapore": return ["en", "zh-Hans"]
        case "Asia/Bangkok": return ["th"]
        case "Asia/Jakarta", "Asia/Makassar", "Asia/Jayapura": return ["id"]
        case "Asia/Kuala_Lumpur", "Asia/Kuching": return ["ms", "en"]
        case "Asia/Manila": return ["fil", "en"]
        case "Asia/Kolkata", "Asia/Calcutta": return ["hi", "en"]
        case "Europe/London": return ["en"]
        case "Europe/Paris": return ["fr"]
        case "Europe/Berlin", "Europe/Vienna", "Europe/Zurich": return ["de"]
        case "Europe/Madrid": return ["es"]
        case "Europe/Rome": return ["it"]
        case "Europe/Lisbon": return ["pt"]
        case "Europe/Amsterdam": return ["nl"]
        case "Europe/Warsaw": return ["pl"]
        case "Europe/Moscow": return ["ru"]
        default:
            if identifier.hasPrefix("America/") { return ["en", "es"] }
            if identifier.hasPrefix("Australia/") || identifier.hasPrefix("Pacific/Auckland") {
                return ["en"]
            }
            return []
        }
    }

    private static func defaultSecondaryTarget(excluding primaryIdentifier: String) -> String {
        var candidates = Array(Locale.preferredLanguages.dropFirst())
        candidates.append(contentsOf: keyboardLanguageIdentifiers())
        candidates.append(contentsOf: timeZoneLanguageIdentifiers())
        candidates.append("en")
        candidates.append("zh-Hans")

        let primaryIdentity = LanguageIdentity.identifier(primaryIdentifier)
        return candidates
            .map(LanguageIdentity.identifier)
            .first(where: { $0 != primaryIdentity }) ?? "en"
    }

    private static var systemLanguageIdentifier: String {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        return Locale.Language(identifier: preferred).minimalIdentifier
    }
}

@MainActor
private final class SaveFormatAccessoryController: NSViewController {
    var onChange: ((SubtitleFormat) -> Void)?

    private let formats: [SubtitleFormat]
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)

    var selectedFormat: SubtitleFormat {
        formats[max(0, popup.indexOfSelectedItem)]
    }

    init(originalFormat: SubtitleFormat) {
        formats = [originalFormat] + SubtitleFormat.allCases.filter { $0 != originalFormat }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 228, height: 34))
        let label = NSTextField(labelWithString: L10n.format)
        label.translatesAutoresizingMaskIntoConstraints = false

        popup.translatesAutoresizingMaskIntoConstraints = false
        for (index, format) in formats.enumerated() {
            let title = index == 0
                ? "\(format.compactDisplayName) (\(L10n.originalFormat))"
                : format.compactDisplayName
            popup.addItem(withTitle: title)
        }
        popup.setContentHuggingPriority(.required, for: .horizontal)
        popup.setContentCompressionResistancePriority(.required, for: .horizontal)
        popup.target = self
        popup.action = #selector(formatChanged)

        container.addSubview(label)
        container.addSubview(popup)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            popup.widthAnchor.constraint(equalToConstant: 152),
            popup.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        view = container
    }

    @objc private func formatChanged() {
        onChange?(selectedFormat)
    }
}

private struct PreviewRootView: View {
    @ObservedObject var model: PreviewModel
    @State private var hoveredTranslationControl: TranslationControl?

    private enum TranslationControl {
        case close
        case save
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()

            ScrollView {
                Text(model.visibleText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .textColor))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
                    .textSelection(.enabled)
            }

            if model.translationIsOpen {
                translationPanel
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            } else {
                Button(action: model.openTranslation) {
                    Image(systemName: "translate")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.translate)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(18)
            }

            WindowReader(window: model.setHostWindow)
                .frame(width: 0, height: 0)
        }
        .overlay(alignment: .top) {
            if let message = model.noticeMessage ?? model.errorMessage {
                Text(message)
                    .font(.callout)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
            }
        }
        .translationTask(model.configuration) { session in
            await model.translate(using: session)
        }
    }

    private var translationPanel: some View {
        ViewThatFits(in: .horizontal) {
            translationPanelContents(compact: false)
            translationPanelContents(compact: true)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            ZStack(alignment: .leading) {
                Capsule().fill(.regularMaterial)

                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.13))
                        .frame(
                            width: geometry.size.width * model.translationProgress,
                            height: geometry.size.height
                        )
                }
                .opacity(model.isTranslating ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: model.translationProgress)
                .animation(.easeOut(duration: 0.18), value: model.isTranslating)
            }
            .clipShape(Capsule())
        }
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }

    private func translationPanelContents(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            Button(action: model.closeTranslation) {
                Image(systemName: "xmark")
            }
            .buttonStyle(TranslationIconButtonStyle(
                isHovered: hoveredTranslationControl == .close
            ))
            .onHover { updateHover(.close, isHovering: $0) }
            .help(L10n.closeTranslation)

            Divider().frame(height: 18)

            LanguageMenu(
                title: model.sourceLanguageName,
                selectedIdentifier: model.sourceIdentifier,
                includesAuto: true,
                commonLanguages: model.commonLanguages,
                otherLanguages: model.otherLanguages,
                select: model.setSource
            )
            .frame(width: compact ? 78 : 132)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            LanguageMenu(
                title: model.targetLanguageName,
                selectedIdentifier: model.targetIdentifier,
                includesAuto: false,
                commonLanguages: model.commonLanguages,
                otherLanguages: model.otherLanguages
            ) { identifier in
                if let identifier {
                    model.setTarget(identifier)
                }
            }
            .frame(width: compact ? 78 : 132)

            Divider().frame(height: 18)

            Button(action: model.requestSaveAs) {
                Group {
                    if model.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: model.didSave ? "checkmark" : "square.and.arrow.down")
                    }
                }
            }
            .buttonStyle(TranslationIconButtonStyle(
                isHovered: hoveredTranslationControl == .save
            ))
            .onHover { updateHover(.save, isHovering: $0) }
            .disabled(!model.canSave)
            .help(L10n.saveAs)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func updateHover(_ control: TranslationControl, isHovering: Bool) {
        hoveredTranslationControl = isHovering ? control : nil
        if isHovering {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

private struct TranslationIconButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 32, height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(
                        configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)
                    ))
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct LanguageMenu: View {
    let title: String
    let selectedIdentifier: String?
    let includesAuto: Bool
    let commonLanguages: [LanguageOption]
    let otherLanguages: [LanguageOption]
    let select: (String?) -> Void

    var body: some View {
        Menu {
            if includesAuto {
                languageButton(identifier: nil, name: L10n.auto)
                Divider()
            }

            ForEach(commonLanguages) { language in
                languageButton(identifier: language.id, name: language.name)
            }

            if !otherLanguages.isEmpty {
                Divider()
                Menu(L10n.more) {
                    ForEach(otherLanguages) { language in
                        languageButton(identifier: language.id, name: language.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(title)
    }

    private func languageButton(identifier: String?, name: String) -> some View {
        Button {
            select(identifier)
        } label: {
            if selectedIdentifier == identifier {
                Label(name, systemImage: "checkmark")
            } else {
                Text(name)
            }
        }
    }
}

private struct WindowReader: NSViewRepresentable {
    let window: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { window(nsView.window) }
    }
}

private struct LanguageOption: Identifiable, Hashable {
    let id: String
    let name: String
}

private struct PreviewPayload {
    let url: URL
    let loadedText: LoadedText
    let document: SubtitleDocument
}


private enum L10n {
    private static var zh: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    static var auto: String { zh ? "自动" : "Auto" }
    static var more: String { zh ? "更多" : "More" }
    static var noTranslationNeeded: String { zh ? "无需翻译" : "No translation needed" }
    static var translate: String { zh ? "翻译" : "Translate" }
    static var closeTranslation: String { zh ? "关闭翻译" : "Close translation" }
    static var saveAs: String { zh ? "另存为" : "Save As" }
    static var format: String { zh ? "格式" : "Format" }
    static var originalFormat: String { zh ? "原始格式" : "Original Format" }
    static var saveTranslatedSubtitle: String { zh ? "保存翻译字幕" : "Save Translated Subtitle" }
    static var cannotShowSavePanel: String {
        zh ? "暂时无法显示另存为面板。" : "The Save As panel is temporarily unavailable."
    }
    static var noSubtitleText: String {
        zh ? "没有找到可翻译的字幕正文。" : "No translatable subtitle text was found."
    }
    static var cannotEncode: String {
        zh ? "无法用原文件编码保存译文。" : "The translation can't be saved using the original encoding."
    }
    static var saveFailed: String {
        zh ? "无法保存翻译字幕。" : "The translated subtitle couldn't be saved."
    }
    static var unsupportedEncoding: String {
        zh ? "无法识别该文件的文本编码。" : "The file's text encoding isn't supported."
    }
    static var truncated: String {
        zh ? "—— 预览已在 8 MiB 处截断，不能覆盖保存 ——" : "— Preview truncated at 8 MiB; saving is disabled —"
    }
}
