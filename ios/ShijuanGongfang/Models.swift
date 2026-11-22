import Foundation

// MARK: - 试卷元信息（命名：学年 + 省 + 市/区 + 学校 + 年级 + 学期 + 类型 + 学科）

struct ExamMeta: Codable, Equatable {
    var xuenian: String = "2026-2027学年"
    var sheng: String = ""
    var shi: String = ""
    var qu: String = ""
    var school: String = ""
    var nianji: String = "八年级"
    var xueqi: String = "上学期"
    var leixing: String = "期中"
    var xueke: String = "数学"
    var manfen: String = ""
    var shijian: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xuenian = (try? c.decode(String.self, forKey: .xuenian)) ?? "2026-2027学年"
        sheng = (try? c.decode(String.self, forKey: .sheng)) ?? ""
        shi = (try? c.decode(String.self, forKey: .shi)) ?? ""
        qu = (try? c.decode(String.self, forKey: .qu)) ?? ""
        school = (try? c.decode(String.self, forKey: .school)) ?? ""
        nianji = (try? c.decode(String.self, forKey: .nianji)) ?? ""
        xueqi = (try? c.decode(String.self, forKey: .xueqi)) ?? ""
        leixing = (try? c.decode(String.self, forKey: .leixing)) ?? ""
        xueke = (try? c.decode(String.self, forKey: .xueke)) ?? ""
        manfen = (try? c.decode(String.self, forKey: .manfen)) ?? ""
        shijian = (try? c.decode(String.self, forKey: .shijian)) ?? ""
    }

    /// 与服务端 naming.build_basename 保持一致的本地预览
    var previewName: String {
        var parts: [String] = []
        if !xuenian.isEmpty {
            parts.append(xuenian.hasSuffix("学年") ? xuenian : xuenian + "学年")
        }
        if !sheng.isEmpty { parts.append(sheng) }
        if !shi.isEmpty && !sheng.contains(shi) { parts.append(shi) }
        if !qu.isEmpty && !shi.contains(qu) { parts.append(qu) }
        if !school.isEmpty { parts.append(school) }
        if !nianji.isEmpty { parts.append(nianji) }
        if !xueqi.isEmpty { parts.append(xueqi) }
        parts.append(leixing + xueke)
        return parts.filter { !$0.isEmpty }.joined() + "试卷"
    }
}

/// output 里混有 "names" 这类字典值，这里只挑出字符串键值，避免整体解码失败
struct StringMap: Decodable, Hashable {
    var values: [String: String] = [:]

    private struct Key: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        for k in c.allKeys {
            if let v = try? c.decode(String.self, forKey: k) { values[k.stringValue] = v }
        }
    }

    subscript(_ key: String) -> String? { values[key] }
}

// MARK: - 检索候选

struct Candidate: Codable, Hashable {
    let label: String?
    let text: String?
    let answer: String?
    let score: Double?
    let image: String?
}

// MARK: - 题目

struct Question: Codable, Identifiable, Hashable {
    var id: Int { index }
    let no: Int
    let index: Int
    let section: String?
    let text: String
    let type: String?
    let page: Int?
    let bbox: [Double]?
    let origImage: String?
    let redrawImage: String?
    let candidates: [Candidate]?
    let status: String?
    let answer: String?

    enum CodingKeys: String, CodingKey {
        case no, index, section, text, type, page, bbox, candidates, status, answer
        case origImage = "orig_image"
        case redrawImage = "redraw_image"
    }

    /// 当前展示用图：命中 / 重绘 / 原卷
    var displayKind: String {
        if let s = status {
            if s == "matched" || s == "confirmed" { return "hit" }
            if s == "redrawn" { return "redraw" }
        }
        return "orig"
    }

    var statusLabel: (String, String) {
        switch status {
        case "matched": return ("已匹配", "green")
        case "confirmed": return ("已采用", "blue")
        case "low": return ("相似度低", "orange")
        case "skipped": return ("已跳过", "gray")
        case "redrawn": return ("已重绘", "purple")
        default: return ("未检索", "gray")
        }
    }

    var bestScore: Double? { candidates?.first?.score }
}

// MARK: - 进度

struct JobProgress: Codable {
    let done: Int?
    let total: Int?
    let msg: String?

    var fraction: Double {
        guard let total, total > 0, let done else { return 0 }
        return min(1, Double(done) / Double(total))
    }
}

// MARK: - 任务

struct JobSummary: Codable, Identifiable, Hashable {
    let id: String
    let created: String?
    let stage: String?
    let preview: String
    let count: Int
    let output: StringMap?
}

struct JobDetail: Codable {
    let id: String
    var stage: String
    var progress: JobProgress?
    var meta: ExamMeta
    var questions: [Question]
    var output: StringMap?
    var searching: Bool?
    var searchProgress: String?
    var answerImages: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, stage, progress, meta, questions, output, searching
        case searchProgress = "search_progress"
        case answerImages = "answer_images"
    }
}

struct BrowserStatus: Codable {
    let loggedIn: Bool
    let url: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case loggedIn = "logged_in"
        case url, name
    }
}

enum JobStage: String {
    case queued, enhancing, ocr, segmenting, ready, searching, rendering, rendered, error, unknown

    init(raw: String?) {
        self = JobStage(rawValue: raw ?? "") ?? .unknown
    }

    var label: String {
        switch self {
        case .queued: return "排队中"
        case .enhancing: return "清晰化"
        case .ocr: return "文字识别"
        case .segmenting: return "拆题"
        case .ready: return "待检索"
        case .searching: return "检索中"
        case .rendering: return "排版中"
        case .rendered: return "已导出"
        case .error: return "出错"
        case .unknown: return "未知"
        }
    }

    var isRunning: Bool {
        [.queued, .enhancing, .ocr, .segmenting, .searching, .rendering].contains(self)
    }
}
