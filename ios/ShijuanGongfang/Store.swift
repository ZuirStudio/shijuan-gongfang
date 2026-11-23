import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published private(set) var jobs: [Job] = []
    @Published var errorText: String?
    @Published var busyJobID: String?

    private let root = AppPaths.jobsRoot

    init() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    // MARK: 持久化

    func reload() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
            jobs = []
            return
        }
        var loaded: [Job] = []
        for item in items {
            let json = item.appendingPathComponent("job.json")
            guard let data = try? Data(contentsOf: json),
                  let job = try? JSONDecoder().decode(Job.self, from: data) else { continue }
            loaded.append(job)
        }
        jobs = loaded.sorted { $0.created > $1.created }
        // 上次中断的任务标记为失败，避免“永远在跑”的假状态
        for (index, job) in jobs.enumerated() where job.stage.isRunning {
            jobs[index].stage = .failed
            jobs[index].errorText = "上次处理被中断"
            persist(jobs[index])
        }
    }

    func persist(_ job: Job) {
        let dir = AppPaths.dir(job.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(job) {
            try? data.write(to: dir.appendingPathComponent("job.json"), options: .atomic)
        }
    }

    // MARK: 新建任务

    func create(files: [(name: String, data: Data)],
                meta: ExamMeta,
                mode: OutputMode,
                enhance: Bool,
                maxPages: Int,
                languages: [String]) {
        let id = makeID()
        let job = Job(id: id, created: Date(), meta: meta, stage: .pending, progress: 0,
                      statusText: "准备中", pageFiles: [], questions: [],
                      paperPath: nil, errorText: nil, outputMode: mode)
        jobs.insert(job, at: 0)
        persist(job)

        let dir = AppPaths.dir(id)
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let result = try Pipeline.run(payloads: files, dir: dir, enhance: enhance,
                                             maxPages: maxPages, ocrLanguages: languages) { progress, text in
                    Task { @MainActor in
                        self?.updateProgress(id: id, progress: progress, text: text)
                    }
                }
                await MainActor.run {
                    self?.finish(id: id, result: result)
                }
            } catch {
                await MainActor.run {
                    self?.fail(id: id, message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: 导出

    func export(_ id: String, mode: OutputMode) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].stage = .exporting
        jobs[index].statusText = "排版中"
        jobs[index].progress = 0.5
        jobs[index].errorText = nil
        persist(jobs[index])

        let job = jobs[index]
        let dir = AppPaths.dir(id)
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let url = try PDFExport.build(job: job, dir: dir, mode: mode)
                let relative = "output/" + url.lastPathComponent
                await MainActor.run {
                    self?.exported(id: id, path: relative)
                }
            } catch {
                await MainActor.run {
                    self?.fail(id: id, message: error.localizedDescription)
                }
            }
        }
    }

    func delete(_ id: String) {
        jobs.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: AppPaths.dir(id))
    }

    func renameMeta(_ id: String, meta: ExamMeta) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].meta = meta
        persist(jobs[index])
    }

    // MARK: 内部状态

    private func updateProgress(id: String, progress: Double, text: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].progress = progress
        jobs[index].statusText = text
        jobs[index].stage = stage(for: progress)
        if progress < 0.25 { busyJobID = id }
        persist(jobs[index])
    }

    private func stage(for progress: Double) -> Job.Stage {
        if progress < 0.15 { return .reading }
        if progress < 0.25 { return .enhancing }
        if progress < 0.78 { return .recognizing }
        if progress < 0.80 { return .segmenting }
        return .cropping
    }

    private func finish(id: String, result: Pipeline.Result) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].pageFiles = result.pageFiles
        jobs[index].questions = result.questions
        jobs[index].stage = .ready
        jobs[index].progress = 1
        jobs[index].statusText = "已拆出 " + String(result.questions.count) + " 题"
        busyJobID = nil
        persist(jobs[index])
    }

    private func exported(id: String, path: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].paperPath = path
        jobs[index].stage = .exported
        jobs[index].progress = 1
        jobs[index].statusText = "已导出"
        persist(jobs[index])
    }

    private func fail(id: String, message: String) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].stage = .failed
        jobs[index].errorText = message
        jobs[index].statusText = "出错"
        busyJobID = nil
        persist(jobs[index])
    }

    private func makeID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date()) + "-" + String(UUID().uuidString.prefix(4)).lowercased()
    }
}
