import Foundation
import UIKit

// MARK: - 排版导出（端侧 PDFKit / Core Graphics）

enum PDFExport {
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 42

    static func build(job: Job, dir: URL, mode: OutputMode) throws -> URL {
        let contentWidth = pageSize.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        let data = renderer.pdfData { ctx in
            var y: CGFloat = margin
            var pageNumber = 0
            var lastSection: String?

            func footer() {
                let label = "第 " + String(pageNumber) + " 页"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9),
                    .foregroundColor: UIColor.systemGray
                ]
                let size = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(at: CGPoint(x: pageSize.width - margin - size.width,
                                                   y: pageSize.height - 24),
                                         withAttributes: attrs)
            }

            func newPage() {
                ctx.beginPage()
                pageNumber += 1
                y = margin
                footer()
            }

            newPage()

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
            let titleSize = (job.title as NSString).size(withAttributes: titleAttrs)
            (job.title as NSString).draw(at: CGPoint(x: (pageSize.width - titleSize.width) / 2, y: y),
                                         withAttributes: titleAttrs)
            y += titleSize.height + 6

            var subtitle = ""
            if !job.meta.manfen.isEmpty { subtitle += "满分 " + job.meta.manfen + " 分　" }
            if !job.meta.shijian.isEmpty { subtitle += "答题时间 " + job.meta.shijian + " 分钟" }
            if !subtitle.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor.systemGray
                ]
                let size = (subtitle as NSString).size(withAttributes: attrs)
                (subtitle as NSString).draw(at: CGPoint(x: (pageSize.width - size.width) / 2, y: y),
                                            withAttributes: attrs)
                y += size.height + 14
            }

            let bodyFont = UIFont.systemFont(ofSize: 11.5)
            let sectionFont = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
            let bottomLimit = pageSize.height - margin - 30
            let fullLimit = pageSize.height - margin * 2 - 40

            for question in job.questions {
                if let section = question.section, section != lastSection {
                    lastSection = section
                    let height = measure(section, font: sectionFont, width: contentWidth) + 8
                    if y + height > bottomLimit { newPage() }
                    (section as NSString).draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height),
                                               withAttributes: [.font: sectionFont, .foregroundColor: UIColor.label])
                    y += height
                }

                if mode == .image, let path = question.cropFile {
                    let url = AppPaths.crop(dir, path: path)
                    if let image = UIImage(contentsOfFile: url.path), image.size.width > 0 {
                        let ratio = image.size.height / image.size.width
                        var height = contentWidth * ratio
                        if height > fullLimit { height = fullLimit }
                        if y + height > bottomLimit { newPage() }
                        image.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height))
                        y += height + 10
                        continue
                    }
                }

                let text = question.text
                var height = measure(text, font: bodyFont, width: contentWidth) + 8
                if y + height > bottomLimit {
                    newPage()
                    height = measure(text, font: bodyFont, width: contentWidth) + 8
                }
                (text as NSString).draw(in: CGRect(x: margin, y: y, width: contentWidth, height: height),
                                        withAttributes: [.font: bodyFont, .foregroundColor: UIColor.label])
                y += height + 4
            }
        }

        let outputDir = dir.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let suffix = mode == .image ? "题图版" : "文字版"
        let name = cleanName(job.title) + "（" + suffix + "）.pdf"
        let url = outputDir.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func measure(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).boundingRect(with: CGSize(width: width, height: 6000),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading],
                                               attributes: attrs,
                                               context: nil).height
    }

    static func cleanName(_ name: String) -> String {
        var result = name
        result = result.replacingOccurrences(of: "/", with: "_")
        result = result.replacingOccurrences(of: ":", with: "_")
        if result.isEmpty { result = "试卷" }
        return result
    }
}
