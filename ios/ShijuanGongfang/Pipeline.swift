import Foundation
import UIKit
import PDFKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 流水线（纯端侧）

struct TextLine {
    let text: String
    let box: BBox
}

enum PipelineError: LocalizedError {
    case noPages

    var errorDescription: String? {
        "没有读出可用的页面，请确认文件是 PDF 或图片"
    }
}

enum Pipeline {
    struct Result {
        let pageFiles: [String]
        let questions: [Question]
    }

    struct Seed {
        let no: Int
        let section: String?
        let text: String
        let page: Int
        let box: BBox
    }

    static let maxPageWidth: CGFloat = 2300

    // MARK: 主流程

    static func run(payloads: [(name: String, data: Data)],
                    dir: URL,
                    enhance: Bool,
                    maxPages: Int,
                    ocrLanguages: [String],
                    progress: @escaping (Double, String) -> Void) throws -> Result {
        let fm = FileManager.default
        let pagesDir = dir.appendingPathComponent("pages", isDirectory: true)
        try fm.createDirectory(at: pagesDir, withIntermediateDirectories: true)

        var pageURLs: [URL] = []

        for (idx, item) in payloads.enumerated() {
            progress(0.02 + 0.10 * Double(idx) / Double(Swift.max(payloads.count, 1)),
                     "读取 " + item.name)

            if let doc = PDFDocument(data: item.data) {
                let room = Swift.max(0, maxPages - pageURLs.count)
                let count = Swift.min(doc.pageCount, room)
                for i in 0..<count {
                    guard let page = doc.page(at: i) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    var w = bounds.width * 2
                    var h = bounds.height * 2
                    if w > maxPageWidth {
                        let scale = maxPageWidth / w
                        w *= scale
                        h *= scale
                    }
                    let size = CGSize(width: w.rounded(), height: h.rounded())
                    let thumb = page.thumbnail(of: size, for: .mediaBox)
                    let flat = flatten(thumb, size: size)
                    let url = pagesDir.appendingPathComponent(pageName(pageURLs.count))
                    try write(flat, to: url)
                    pageURLs.append(url)
                }
            } else if let image = UIImage(data: item.data), pageURLs.count < maxPages {
                let scaled = normalize(image, maxWidth: maxPageWidth)
                let url = pagesDir.appendingPathComponent(pageName(pageURLs.count))
                try write(scaled, to: url)
                pageURLs.append(url)
            }
        }

        guard !pageURLs.isEmpty else { throw PipelineError.noPages }
        progress(0.15, "已读取 " + String(pageURLs.count) + " 页")

        if enhance {
            let context = CIContext(options: [.useSoftwareRenderer: false])
            for (i, url) in pageURLs.enumerated() {
                if let source = CIImage(contentsOf: url) {
                    let out = enhanceImage(source)
                    if let cg = context.createCGImage(out, from: out.extent) {
                        try write(UIImage(cgImage: cg), to: url)
                    }
                }
                progress(0.15 + 0.10 * Double(i + 1) / Double(pageURLs.count), "增强清晰度")
            }
        }

        var linesByPage: [(page: Int, lines: [TextLine])] = []
        for (i, url) in pageURLs.enumerated() {
            progress(0.25 + 0.50 * Double(i) / Double(pageURLs.count),
                     "识别第 " + String(i + 1) + " 页")
            guard let cg = cgImage(url) else {
                linesByPage.append((i, []))
                continue
            }
            let lines = recognize(cg, languages: ocrLanguages)
            linesByPage.append((i, lines))
        }

        progress(0.78, "拆分题目")
        let seeds = segment(linesByPage)

        let questionsDir = dir.appendingPathComponent("q", isDirectory: true)
        try fm.createDirectory(at: questionsDir, withIntermediateDirectories: true)

        var questions: [Question] = []
        for (idx, seed) in seeds.enumerated() {
            var question = Question(index: idx, no: seed.no, section: seed.section,
                                    text: seed.text, page: seed.page, box: seed.box, cropFile: nil)
            if let src = pageURLs[safe: seed.page], let cg = cgImage(src),
               let cropped = crop(cg, box: seed.box, padding: 0.006) {
                let name = cropName(idx)
                let outURL = questionsDir.appendingPathComponent(name)
                try write(UIImage(cgImage: cropped), to: outURL)
                question.cropFile = "q/" + name
            }
            questions.append(question)
            progress(0.80 + 0.19 * Double(idx + 1) / Double(Swift.max(seeds.count, 1)),
                     "裁剪第 " + String(idx + 1) + " 题")
        }

        progress(0.99, "完成")

        let names = pageURLs.map { $0.lastPathComponent }
        return Result(pageFiles: names, questions: questions)
    }

    // MARK: 文件

    static func pageName(_ index: Int) -> String {
        "p" + String(index) + ".jpg"
    }

    static func cropName(_ index: Int) -> String {
        "q" + String(index) + ".jpg"
    }

    static func write(_ image: UIImage, to url: URL) throws {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw PipelineError.noPages
        }
        try data.write(to: url, options: .atomic)
    }

    static func cgImage(_ url: URL) -> CGImage? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return image.cgImage
    }

    static func flatten(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func normalize(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        var size = image.size
        if size.width <= 0 || size.height <= 0 { size = CGSize(width: 1000, height: 1414) }
        if size.width > maxWidth {
            let scale = maxWidth / size.width
            size = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        }
        return flatten(image, size: size)
    }

    // MARK: 增强

    static func enhanceImage(_ input: CIImage) -> CIImage {
        var image = input
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.brightness = 0.02
        controls.contrast = 1.12
        controls.saturation = 0.4
        if let output = controls.outputImage { image = output }

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = image
        sharpen.sharpness = 0.45
        if let output = sharpen.outputImage { image = output }

        return image
    }

    // MARK: 识别

    static func recognize(_ cg: CGImage, languages: [String]) -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        request.minimumTextHeight = 0.006

        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        guard let results = try? handler.perform([request]), let observations = request.results else {
            return []
        }

        var lines: [TextLine] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            let rect = observation.boundingBox
            let box = BBox(x: Double(rect.minX),
                           y: Double(1 - rect.maxY),
                           w: Double(rect.width),
                           h: Double(rect.height))
            lines.append(TextLine(text: text, box: box))
        }
        return lines
    }

    // MARK: 拆题

    static func segment(_ pages: [(page: Int, lines: [TextLine])]) -> [Seed] {
        var seeds: [Seed] = []
        var section: String?

        var open = false
        var currentNo = 0
        var currentSection: String?
        var currentPage = 0
        var currentBox = BBox()
        var currentText = ""

        func flush() {
            if open && !currentText.isEmpty {
                seeds.append(Seed(no: currentNo, section: currentSection,
                                 text: currentText, page: currentPage, box: currentBox))
            }
            open = false
            currentText = ""
        }

        for page in pages {
            let sorted = page.lines.sorted { a, b in
                if abs(a.box.y - b.box.y) > 0.012 { return a.box.y < b.box.y }
                return a.box.x < b.box.x
            }

            for line in sorted {
                if isNoise(line.text) { continue }
                if let title = sectionTitle(line.text) {
                    flush()
                    section = title
                    continue
                }
                if let no = questionNumber(line.text) {
                    flush()
                    currentNo = no
                    currentSection = section
                    currentPage = page.page
                    currentBox = line.box
                    currentText = line.text
                    open = true
                } else if open {
                    if page.page == currentPage {
                        currentText += "\n" + line.text
                        currentBox = currentBox.union(line.box)
                    }
                }
            }
        }
        flush()
        return seeds
    }

    static func questionNumber(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        var digits = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex, trimmed[index].isNumber, digits.count < 3 {
            digits.append(trimmed[index])
            index = trimmed.index(after: index)
        }
        guard !digits.isEmpty, let number = Int(digits), number > 0 else { return nil }
        guard index < trimmed.endIndex else { return nil }
        let separator = trimmed[index]
        guard ".、．。)、）".contains(separator) else { return nil }
        return number
    }

    static func sectionTitle(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, "一二三四五六七八九十".contains(first) else { return nil }
        let rest = trimmed.dropFirst()
        guard let separator = rest.first, "、．.：:".contains(separator) else { return nil }
        return String(trimmed.prefix(24))
    }

    static func isNoise(_ text: String) -> Bool {
        if text.count < 2 { return true }
        if text.contains("共") && text.contains("页") && text.count < 12 { return true }
        if text.hasPrefix("第") && text.contains("页") && text.count < 12 { return true }
        if text.contains("http") { return true }
        return false
    }

    // MARK: 裁剪

    static func crop(_ cg: CGImage, box: BBox, padding: Double) -> CGImage? {
        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        var rect = CGRect(x: CGFloat(box.x) * width,
                          y: CGFloat(box.y) * height,
                          width: CGFloat(box.w) * width,
                          height: CGFloat(box.h) * height)
        let pad = CGFloat(padding) * width
        rect = rect.insetBy(dx: -pad, dy: -pad)
        rect = rect.integral
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        rect = rect.intersection(bounds)
        guard rect.width > 8, rect.height > 8 else { return nil }
        return cg.cropping(to: rect)
    }
}
