import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "服务器地址无效"
        case .http(let code, let body): return "HTTP \(code)：\(body)"
        case .decode(let msg): return "数据解析失败：\(msg)"
        }
    }
}

/// 与云端 FastAPI 服务通信。所有重活都在服务端（清晰化 / OCR / 拆题 / 菁优网检索 / 排版）。
struct APIClient {
    static var baseURL: URL {
        let raw = UserDefaults.standard.string(forKey: "server_url") ?? "http://192.168.1.10:8765"
        return URL(string: raw) ?? URL(string: "http://127.0.0.1:8765")!
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 180
        return URLSession(configuration: cfg)
    }()

    static func url(_ path: String) -> URL? { URL(string: path, relativeTo: baseURL) }

    private static func send(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return data }
        if http.statusCode >= 400 {
            throw APIError.http(http.statusCode, String(data: data.prefix(400), encoding: .utf8) ?? "")
        }
        return data
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode(String(describing: error))
        }
    }

    // MARK: 健康检查
    static func health() async throws -> Bool {
        guard let u = url("/api/health") else { throw APIError.badURL }
        let data = try await send(URLRequest(url: u))
        struct Health: Decodable { let ok: Bool? }
        return (try? JSONDecoder().decode(Health.self, from: data))?.ok ?? false
    }

    // MARK: 任务列表
    static func jobs() async throws -> [JobSummary] {
        guard let u = url("/api/jobs") else { throw APIError.badURL }
        let data = try await send(URLRequest(url: u))
        struct Wrap: Decodable { let jobs: [JobSummary] }
        return try decode(Wrap.self, data).jobs
    }

    static func job(_ id: String) async throws -> JobDetail {
        guard let u = url("/api/jobs/\(id)") else { throw APIError.badURL }
        let data = try await send(URLRequest(url: u))
        return try decode(JobDetail.self, data)
    }

    // MARK: 新建任务（多文件上传 + 元信息）
    static func createJob(files: [(name: String, data: Data, mime: String)], meta: ExamMeta) async throws -> JobDetail {
        guard let u = url("/api/jobs") else { throw APIError.badURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        let metaJSON = (try? JSONEncoder().encode(meta)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"meta\"\r\n\r\n")
        append(metaJSON + "\r\n")

        for f in files {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"files\"; filename=\"\(f.name)\"\r\n")
            append("Content-Type: \(f.mime)\r\n\r\n")
            body.append(f.data)
            append("\r\n")
        }
        append("--\(boundary)--\r\n")
        req.httpBody = body

        struct Created: Decodable { let id: String }
        let created = try decode(Created.self, try await send(req))
        return try await job(created.id)
    }

    // MARK: 元信息修改
    static func patchMeta(_ id: String, meta: ExamMeta) async throws -> JobDetail {
        guard let u = url("/api/jobs/\(id)/meta") else { throw APIError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(meta)
        _ = try await send(req)
        return try await job(id)
    }

    // MARK: 菁优网检索
    static func search(_ id: String) async throws {
        guard let u = url("/api/jobs/\(id)/search") else { throw APIError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        _ = try await send(req)
    }

    /// choice: {"type":"jyeoo","index":n} / {"type":"orig"} / {"type":"skip"} / {"type":"text"}
    static func choose(_ id: String, index: Int, choice: [String: Any]) async throws {
        guard let u = url("/api/jobs/\(id)/questions/\(index)/choose") else { throw APIError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["choice": choice])
        _ = try await send(req)
    }

    // MARK: AI 重绘（必须显式同意）
    /// mode: "ai" 走图像模型重绘，"typeset" 用本地排版渲字（无需外网）
    static func redraw(_ id: String, index: Int, mode: String = "ai") async throws {
        guard let u = url("/api/jobs/\(id)/questions/\(index)/redraw") else { throw APIError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["mode": mode])
        _ = try await send(req)
    }

    // MARK: 排版导出
    /// mode: "image" 原题图/菁优题图；"text" OCR 文字重排
    static func render(_ id: String, layout: String = "single", mode: String = "image") async throws -> JobDetail {
        guard let u = url("/api/jobs/\(id)/render") else { throw APIError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["layout": layout, "mode": mode])
        _ = try await send(req)
        return try await job(id)
    }

    // MARK: 题图（orig = 原卷裁剪，hit = 菁优网命中，answer = 答案裁剪）
    static func imageURL(_ id: String, index: Int, kind: String) -> URL? {
        url("/api/jobs/\(id)/images/\(index)/\(kind)")
    }

    // MARK: 文件下载（paper / answer / clean / source）
    static func fileURL(_ id: String, kind: String) -> URL? {
        url("/api/jobs/\(id)/files/\(kind)")
    }

    static func download(_ id: String, kind: String) async throws -> URL {
        guard let u = fileURL(id, kind: kind) else { throw APIError.badURL }
        let (tmp, _) = try await session.download(from: u)
        let ext = "pdf"
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(kind)-\(id).\(ext)")
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.moveItem(at: tmp, to: dst)
        return dst
    }

    // MARK: 菁优网登录与上传
    static func browserCheck() async throws -> BrowserStatus {
        guard let u = url("/api/browser/check") else { throw APIError.badURL }
        let data = try await send(URLRequest(url: u))
        return try decode(BrowserStatus.self, data)
    }

    static func uploadSubmit(_ id: String, includeAnswer: Bool) async throws {
        guard let u = url("/api/jobs/\(id)/upload/submit") else { throw APIError.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["include_answer": includeAnswer])
        _ = try await send(req)
    }
}
