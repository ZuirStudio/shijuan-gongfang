import Foundation
import CoreGraphics

// MARK: - 输出模式

enum OutputMode: String, Codable, CaseIterable, Identifiable {
    case image
    case text

    var id: String { rawValue }

    var label: String {
        self == .image ? "题图版" : "纯文字版"
    }

    var detail: String {
        switch self {
        case .image:
            return "每题放回原卷高清题图，版面接近真实试卷"
        case .text:
            return "只用离线识别出的文字重排，体积小、便于校对"
        }
    }
}

// MARK: - 试卷元信息

struct ExamMeta: Codable, Hashable {
    var xuenian: String = "2026-2027学年"
    var sheng: String = "天津市"
    var shi: String = "天津市"
    var qu: String = ""
    var school: String = ""
    var nianji: String = "八年级"
    var xueqi: String = "上学期"
    var leixing: String = "期中"
    var xueke: String = "数学"
    var manfen: String = "100"
    var shijian: String = "90"

    init() {}

    var previewName: String {
        var parts: [String] = []
        if !xuenian.isEmpty { parts.append(xuenian.hasSuffix("学年") ? xuenian : xuenian + "学年") }
        if !sheng.isEmpty { parts.append(sheng) }
        if !shi.isEmpty && !sheng.contains(shi) { parts.append(shi) }
        if !qu.isEmpty && !shi.contains(qu) { parts.append(qu) }
        if !school.isEmpty { parts.append(school) }
        if !nianji.isEmpty { parts.append(nianji) }
        if !xueqi.isEmpty { parts.append(xueqi) }
        parts.append(leixing + xueke)
        return parts.joined() + "试卷"
    }
}

// MARK: - 坐标框（归一化，左上原点）

struct BBox: Codable, Hashable {
    var x: Double = 0
    var y: Double = 0
    var w: Double = 0
    var h: Double = 0

    func union(_ other: BBox) -> BBox {
        let minX = Swift.min(x, other.x)
        let minY = Swift.min(y, other.y)
        let maxX = Swift.max(x + w, other.x + other.w)
        let maxY = Swift.max(y + h, other.y + other.h)
        return BBox(x: minX, y: minY, w: maxX - minX, h: maxY - minY)
    }

    func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * Double(size.width),
               y: y * Double(size.height),
               width: w * Double(size.width),
               height: h * Double(size.height))
    }
}

// MARK: - 题目

struct Question: Identifiable, Codable, Hashable {
    var id: Int { index }
    var index: Int
    var no: Int
    var section: String?
    var text: String
    var page: Int
    var box: BBox
    var cropFile: String?
}

// MARK: - 任务

struct Job: Identifiable, Codable, Hashable {
    enum Stage: String, Codable {
        case pending, reading, enhancing, recognizing, segmenting, cropping, ready, exporting, exported, failed

        var label: String {
            switch self {
            case .pending: return "排队"
            case .reading: return "读取试卷"
            case .enhancing: return "增强清晰度"
            case .recognizing: return "文字识别"
            case .segmenting: return "拆分题目"
            case .cropping: return "裁剪题图"
            case .ready: return "待导出"
            case .exporting: return "排版导出"
            case .exported: return "已导出"
            case .failed: return "出错"
            }
        }

        var isRunning: Bool {
            switch self {
            case .pending, .reading, .enhancing, .recognizing, .segmenting, .cropping, .exporting: return true
            case .ready, .exported, .failed: return false
            }
        }
    }

    var id: String
    var created: Date
    var meta: ExamMeta
    var stage: Stage
    var progress: Double
    var statusText: String
    var pageFiles: [String]
    var questions: [Question]
    var paperPath: String?
    var errorText: String?
    var outputMode: OutputMode

    var pageCount: Int { pageFiles.count }
    var title: String { meta.previewName }

    var subtitle: String {
        String(questions.count) + " 题 · " + String(pageCount) + " 页"
    }
}

// MARK: - 路径

enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var jobsRoot: URL {
        documents.appendingPathComponent("jobs", isDirectory: true)
    }

    static func dir(_ id: String) -> URL {
        jobsRoot.appendingPathComponent(id, isDirectory: true)
    }

    static func page(_ dir: URL, name: String) -> URL {
        dir.appendingPathComponent("pages", isDirectory: true).appendingPathComponent(name)
    }

    static func crop(_ dir: URL, path: String) -> URL {
        dir.appendingPathComponent(path)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
