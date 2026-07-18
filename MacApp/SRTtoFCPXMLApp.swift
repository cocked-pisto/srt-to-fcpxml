import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct Subtitle {
    let startMs: Int64
    let endMs: Int64
    let text: String
}

struct FCPFrameRate: Identifiable, Hashable {
    let label: String
    let frameNumerator: Int64
    let frameDenominator: Int64
    var id: String { label }

    static let choices = [
        FCPFrameRate(label: "23.976 fps", frameNumerator: 1001, frameDenominator: 24000),
        FCPFrameRate(label: "24 fps", frameNumerator: 1, frameDenominator: 24),
        FCPFrameRate(label: "25 fps", frameNumerator: 1, frameDenominator: 25),
        FCPFrameRate(label: "29.97 fps", frameNumerator: 1001, frameDenominator: 30000),
        FCPFrameRate(label: "30 fps", frameNumerator: 1, frameDenominator: 30),
        FCPFrameRate(label: "50 fps", frameNumerator: 1, frameDenominator: 50),
        FCPFrameRate(label: "59.94 fps", frameNumerator: 1001, frameDenominator: 60000),
        FCPFrameRate(label: "60 fps", frameNumerator: 1, frameDenominator: 60)
    ]

    func frame(forMilliseconds milliseconds: Int64) -> Int64 {
        let numerator = milliseconds * frameDenominator
        let denominator = 1000 * frameNumerator
        return max(0, (numerator + denominator / 2) / denominator)
    }

    func time(frame: Int64) -> String {
        let numerator = frame * frameNumerator
        let divisor = FCPXMLConverter.gcd(numerator, frameDenominator)
        let n = numerator / divisor, d = frameDenominator / divisor
        return d == 1 ? "\(n)s" : "\(n)/\(d)s"
    }

    func range(startMs: Int64, endMs: Int64) -> (offset: String, duration: String) {
        let start = frame(forMilliseconds: startMs)
        let end = max(start + 1, frame(forMilliseconds: endMs))
        return (time(frame: start), time(frame: end - start))
    }
}

enum ConverterError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(text) = self { return text }
        return "알 수 없는 오류"
    }
}

enum FCPXMLConverter {
    static func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func decodeFile(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .nonLossyASCII] {
            if let value = String(data: data, encoding: encoding) { return value }
        }
        // Korean Windows SRT fallback.
        let korean = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
        if let value = String(data: data, encoding: korean) { return value }
        throw ConverterError.message("SRT 파일의 문자 인코딩을 읽을 수 없습니다.")
    }

    static func parseSRT(_ source: String) throws -> [Subtitle] {
        let normalized = source.replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Split blocks with a regex so blank lines containing spaces also work.
        let regex = try NSRegularExpression(pattern: "\\n\\s*\\n")
        let ns = normalized as NSString
        var parts: [String] = []
        var location = 0
        for match in regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: location, length: match.range.location - location)))
            location = match.range.location + match.range.length
        }
        parts.append(ns.substring(from: location))
        let timeRegex = try NSRegularExpression(pattern: "^(\\d{1,2}):(\\d{2}):(\\d{2})[,.](\\d{3})\\s*-->\\s*(\\d{1,2}):(\\d{2}):(\\d{2})[,.](\\d{3})")
        var result: [Subtitle] = []
        for (blockIndex, block) in parts.enumerated() {
            var lines = block.components(separatedBy: "\n")
            while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { lines.removeFirst() }
            if lines.first?.trimmingCharacters(in: .whitespaces).allSatisfy({ $0.isNumber }) == true { lines.removeFirst() }
            guard let timeLine = lines.first else { continue }
            let range = NSRange(timeLine.startIndex..., in: timeLine)
            guard let match = timeRegex.firstMatch(in: timeLine, range: range), match.range.location != NSNotFound else {
                throw ConverterError.message("SRT \(blockIndex + 1)번 블록의 타임스탬프를 읽을 수 없습니다.")
            }
            func value(_ index: Int) -> Int64 { Int64((timeLine as NSString).substring(with: match.range(at: index)))! }
            let start = ((value(1) * 3600 + value(2) * 60 + value(3)) * 1000 + value(4))
            let end = ((value(5) * 3600 + value(6) * 60 + value(7)) * 1000 + value(8))
            guard end > start else { throw ConverterError.message("SRT \(blockIndex + 1)번 자막의 종료 시간이 잘못되었습니다.") }
            let text = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { result.append(Subtitle(startMs: start, endMs: end, text: text)) }
        }
        guard !result.isEmpty else { throw ConverterError.message("SRT에 변환할 자막이 없습니다.") }
        return result
    }

    static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var x = abs(a), y = abs(b)
        while y != 0 { (x, y) = (y, x % y) }
        return max(x, 1)
    }

    static func fcpxTime(milliseconds: Int64) -> String {
        let divisor = gcd(milliseconds, 1000)
        let numerator = milliseconds / divisor
        let denominator = 1000 / divisor
        return denominator == 1 ? "\(numerator)s" : "\(numerator)/\(denominator)s"
    }

    static func setAttribute(_ element: XMLElement, name: String, value: String) {
        if let attribute = element.attribute(forName: name) { attribute.stringValue = value }
        else { element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode) }
    }

    static func replaceText(in title: XMLElement, with value: String) throws {
        let nodes = try title.nodes(forXPath: ".//text-style")
        if let first = nodes.first {
            first.stringValue = value
            for node in nodes.dropFirst() { node.stringValue = "" }
            return
        }
        if let text = try title.nodes(forXPath: ".//text").first { text.stringValue = value; return }
        throw ConverterError.message("템플릿 title 안에서 표시 문구를 찾지 못했습니다.")
    }

    static func convert(srtURL: URL, templateURL: URL, outputURL: URL, frameRate: FCPFrameRate) throws -> Int {
        let subtitles = try parseSRT(decodeFile(srtURL))
        if templateURL.pathExtension.lowercased() == "moti" {
            try convertMotion(subtitles: subtitles, templateURL: templateURL, outputURL: outputURL, frameRate: frameRate)
            return subtitles.count
        }
        let document = try XMLDocument(data: Data(contentsOf: templateURL), options: [.nodePreserveAll])
        guard let exemplar = try document.nodes(forXPath: "//title").first as? XMLElement,
              let parent = exemplar.parent as? XMLElement else {
            throw ConverterError.message("템플릿에서 title 자막 클립을 찾지 못했습니다.")
        }
        let position = exemplar.index
        let siblingTitles = parent.children?.compactMap { $0 as? XMLElement }.filter { $0.name == "title" } ?? []
        for title in siblingTitles { title.detach() }

        for (index, subtitle) in subtitles.enumerated() {
            guard let title = exemplar.copy() as? XMLElement else { continue }
            let timing = frameRate.range(startMs: subtitle.startMs, endMs: subtitle.endMs)
            setAttribute(title, name: "offset", value: timing.offset)
            setAttribute(title, name: "duration", value: timing.duration)
            setAttribute(title, name: "start", value: "0s")
            setAttribute(title, name: "name", value: String(subtitle.text.replacingOccurrences(of: "\n", with: " ").prefix(80)))
            try replaceText(in: title, with: subtitle.text)
            parent.insertChild(title, at: min(position + index, parent.childCount))
        }
        let data = document.xmlData(options: [.nodePrettyPrint])
        try data.write(to: outputURL, options: .atomic)
        return subtitles.count
    }

    static func installedMotionTemplate(matching selected: URL) -> URL? {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/Containers/com.apple.FinalCut/Data/Movies/Motion Templates.localized/Titles.localized"),
            home.appendingPathComponent("Movies/Motion Templates.localized/Titles.localized")
        ]
        let wantedName = selected.lastPathComponent.precomposedStringWithCanonicalMapping
        for root in roots where manager.fileExists(atPath: root.path) {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let candidate as URL in enumerator {
                if candidate.lastPathComponent.precomposedStringWithCanonicalMapping == wantedName { return candidate }
            }
        }
        return nil
    }

    static func convertMotion(subtitles: [Subtitle], templateURL: URL, outputURL: URL, frameRate: FCPFrameRate) throws {
        let motionDocument = try XMLDocument(data: Data(contentsOf: templateURL), options: [])
        guard motionDocument.rootElement()?.name == "ozml" else {
            throw ConverterError.message("선택한 파일이 Apple Motion .moti 형식이 아닙니다.")
        }
        guard let installed = installedMotionTemplate(matching: templateURL) else {
            throw ConverterError.message("이 Motion 타이틀이 Final Cut Pro의 타이틀 폴더에 설치되어 있지 않습니다. 먼저 Final Cut에서 사용할 수 있도록 템플릿을 설치해 주세요.")
        }
        let marker = "/Titles.localized/"
        guard let range = installed.path.range(of: marker) else {
            throw ConverterError.message("Motion 타이틀 설치 경로에서 UID를 만들 수 없습니다.")
        }
        let relativePath = String(installed.path[range.upperBound...])
        let effectUID = "~/Titles.localized/" + relativePath
        let effectName = templateURL.deletingPathExtension().lastPathComponent

        func integer(_ xpath: String, fallback: Int) -> Int {
            guard let nodes = try? motionDocument.nodes(forXPath: xpath),
                  let value = nodes.first?.stringValue,
                  let number = Int(value) else { return fallback }
            return number
        }
        let width = integer("//sceneSettings/width", fallback: 1920)
        let height = integer("//sceneSettings/height", fallback: 1080)
        let totalMs = subtitles.map(\.endMs).max() ?? 1000
        let totalFrames = max(1, frameRate.frame(forMilliseconds: totalMs))
        let sourceURL = installed.absoluteString

        var titles = ""
        for (index, subtitle) in subtitles.enumerated() {
            let styleID = "ts\(index + 1)"
            let timing = frameRate.range(startMs: subtitle.startMs, endMs: subtitle.endMs)
            titles += """
                <title ref="r2" lane="1" offset="\(timing.offset)" name="\(xmlEscape(subtitle.text.replacingOccurrences(of: "\n", with: " ")))" start="0s" duration="\(timing.duration)" role="subtitles.subtitles-1">
                  <text><text-style ref="\(styleID)">\(xmlEscape(subtitle.text))</text-style></text>
                  <text-style-def id="\(styleID)"><text-style font=".AppleSystemUIFont" fontSize="40" fontColor="1 1 1 1" alignment="center"/></text-style-def>
                </title>
            """
        }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.11">
          <resources>
            <format id="r1" name="FFVideoFormatRateUndefined" frameDuration="\(frameRate.time(frame: 1))" width="\(width)" height="\(height)" colorSpace="1-1-1 (Rec. 709)"/>
            <effect id="r2" name="\(xmlEscape(effectName))" uid="\(xmlEscape(effectUID))" src="\(xmlEscape(sourceURL))"/>
          </resources>
          <library><event name="SRT 자막"><project name="\(xmlEscape(outputURL.deletingPathExtension().lastPathComponent))">
            <sequence format="r1" duration="\(frameRate.time(frame: totalFrames))" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
              <spine><gap name="갭" offset="0s" start="0s" duration="\(frameRate.time(frame: totalFrames))">\(titles)</gap></spine>
            </sequence>
          </project></event></library>
        </fcpxml>
        """
        try xml.data(using: .utf8)!.write(to: outputURL, options: .atomic)
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let templatePathKey = "selectedFCPXMLTemplatePath"
    @Published var srtURL: URL?
    @Published var templateURL: URL?
    @Published var outputURL: URL?
    @Published var status = "SRT 파일과 FCPXML 템플릿을 선택해 주세요."
    @Published var isWorking = false
    @Published var frameRate = FCPFrameRate.choices[3]

    init() {
        if let savedPath = UserDefaults.standard.string(forKey: Self.templatePathKey) {
            let savedURL = URL(fileURLWithPath: savedPath)
            if FileManager.default.fileExists(atPath: savedURL.path) {
                templateURL = savedURL
                status = "저장된 FCPXML 템플릿을 불러왔습니다. SRT 파일을 선택해 주세요."
            } else {
                UserDefaults.standard.removeObject(forKey: Self.templatePathKey)
                status = "기존 템플릿 파일을 찾지 못했습니다. 템플릿을 다시 선택해 주세요."
            }
        }
    }

    func chooseSRT() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            acceptSRT(url)
        }
    }

    func acceptSRT(_ url: URL) {
        guard url.pathExtension.lowercased() == "srt" else {
            status = "SRT 영역에는 .srt 파일을 넣어 주세요."
            return
        }
        srtURL = url
        outputURL = url.deletingPathExtension().appendingPathExtension("fcpxml")
        status = templateURL == nil
            ? "SRT를 선택했습니다. 이제 템플릿을 선택해 주세요."
            : "SRT를 선택했습니다. 변환할 준비가 되었습니다."
    }

    func chooseTemplate() {
        let panel = NSOpenPanel()
        // .moti has no consistent system UTType across macOS/FCP installations.
        panel.allowedFileTypes = ["fcpxml", "xml", "moti"]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let selectedURL = panel.url {
            acceptTemplate(selectedURL)
        }
    }

    func acceptTemplate(_ url: URL) {
        guard ["fcpxml", "xml", "moti"].contains(url.pathExtension.lowercased()) else {
            status = "템플릿 영역에는 .fcpxml, .xml 또는 .moti 파일을 넣어 주세요."
            return
        }
        templateURL = url
        UserDefaults.standard.set(url.path, forKey: Self.templatePathKey)
        status = srtURL == nil
            ? "템플릿을 저장했습니다. 다음 실행에도 유지됩니다."
            : "템플릿을 저장했습니다. 변환할 준비가 되었습니다."
    }

    func acceptDroppedFile(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "srt": acceptSRT(url)
        case "fcpxml", "xml", "moti": acceptTemplate(url)
        default: status = "지원하지 않는 파일입니다. SRT 또는 FCPXML을 넣어 주세요."
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "fcpxml") ?? .xml]
        panel.nameFieldStringValue = outputURL?.lastPathComponent ?? "subtitles.fcpxml"
        if panel.runModal() == .OK { outputURL = panel.url }
    }

    func run() {
        guard let srtURL, let templateURL, let outputURL else { status = "세 파일 경로를 모두 지정해 주세요."; return }
        isWorking = true
        do {
            let count = try FCPXMLConverter.convert(srtURL: srtURL, templateURL: templateURL, outputURL: outputURL, frameRate: frameRate)
            status = "완료 — 자막 \(count)개를 \(outputURL.lastPathComponent)에 저장했습니다."
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } catch { status = "변환 실패 — \(error.localizedDescription)" }
        isWorking = false
    }
}

struct FileRow: View {
    let title: String
    let url: URL?
    let buttonTitle: String
    let action: () -> Void
    let onDropFile: ((URL) -> Void)?
    @State private var isDropTarget = false

    init(title: String, url: URL?, buttonTitle: String, action: @escaping () -> Void, onDropFile: ((URL) -> Void)? = nil) {
        self.title = title
        self.url = url
        self.buttonTitle = buttonTitle
        self.action = action
        self.onDropFile = onDropFile
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: url == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                .font(.title2).foregroundColor(url == nil ? Color.secondary : Color.green).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(url?.path ?? "선택되지 않음").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(buttonTitle, action: action).controlSize(.large)
        }
        .padding(14)
        .contentShape(Rectangle())
        .background(isDropTarget ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTarget ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .overlay {
            if let onDropFile {
                NativeFileDropTarget(isTargeted: $isDropTarget, onClick: action, onDropFile: onDropFile)
            }
        }
    }
}

/// AppKit drop destination. This receives Finder file drags directly through NSPasteboard.
struct NativeFileDropTarget: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onClick: () -> Void
    let onDropFile: (URL) -> Void

    func makeNSView(context: Context) -> FinderDropView {
        let view = FinderDropView()
        view.onTargetChange = { value in
            DispatchQueue.main.async { isTargeted = value }
        }
        view.onClick = onClick
        view.onDropFile = onDropFile
        return view
    }

    func updateNSView(_ view: FinderDropView, context: Context) {
        view.onDropFile = onDropFile
        view.onClick = onClick
        view.onTargetChange = { value in
            DispatchQueue.main.async { isTargeted = value }
        }
    }
}

final class FinderDropView: NSView {
    var onClick: (() -> Void)?
    var onDropFile: ((URL) -> Void)?
    var onTargetChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
            return []
        }
        onTargetChange?(true)
        return .copy
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetChange?(false)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        let urls = objects.compactMap { object -> URL? in
            guard let value = object as? NSURL else { return nil }
            return value as URL
        }
        guard let first = urls.first else { return false }
        onDropFile?(first.standardizedFileURL)
        return true
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("SRT → FCPXML").font(.system(size: 30, weight: .bold))
                    Text("버전 12").font(.caption).foregroundStyle(.secondary)
                }
                Text("내 Final Cut Pro 타이틀 디자인을 그대로 사용합니다.").foregroundStyle(.secondary)
            }
            FileRow(title: "1. SRT 자막 (여기에 드래그 가능)", url: model.srtURL, buttonTitle: "SRT 선택", action: model.chooseSRT, onDropFile: model.acceptSRT)
            FileRow(title: "2. FCPXML / Motion 템플릿 (드래그 가능)", url: model.templateURL, buttonTitle: "템플릿 선택", action: model.chooseTemplate, onDropFile: model.acceptTemplate)
            FileRow(title: "3. 결과 저장 위치", url: model.outputURL, buttonTitle: "위치 변경", action: model.chooseOutput)
            HStack {
                Label("4. 프로젝트 프레임레이트", systemImage: "film")
                    .font(.headline)
                Spacer()
                Picker("프레임레이트", selection: $model.frameRate) {
                    ForEach(FCPFrameRate.choices) { rate in Text(rate.label).tag(rate) }
                }
                .labelsHidden().frame(width: 150)
            }
            .padding(14).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Image(systemName: model.status.hasPrefix("완료") ? "checkmark.circle" : "info.circle")
                Text(model.status).font(.callout).lineLimit(2)
                Spacer()
                Button("FCPXML 만들기", action: model.run)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(model.srtURL == nil || model.templateURL == nil || model.outputURL == nil || model.isWorking)
            }
            .padding(.top, 4)
        }
        .padding(28).frame(width: 720, height: 570)
    }
}

@main
struct SRTtoFCPXMLApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentSize)
        Settings { EmptyView() }
    }
}
