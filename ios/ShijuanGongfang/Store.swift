import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published var jobs: [JobSummary] = []
    @Published var current: JobDetail?
    @Published var serverOnline = false
    @Published var busy = false
    @Published var errorText: String?

    private var pollTask: Task<Void, Never>?

    var serverURL: String {
        UserDefaults.standard.string(forKey: "server_url") ?? "http://192.168.1.10:8765"
    }

    func refreshJobs() async {
        busy = true
        defer { busy = false }
        do {
            serverOnline = (try? await APIClient.health()) ?? false
            jobs = try await APIClient.jobs()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    func open(_ id: String) async {
        do {
            current = try await APIClient.job(id)
            startPolling(id)
        } catch {
            errorText = error.localizedDescription
        }
    }

    func close() {
        pollTask?.cancel()
        pollTask = nil
        current = nil
    }

    private func startPolling(_ id: String) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { return }
                do {
                    let fresh = try await APIClient.job(id)
                    self.current = fresh
                    if !JobStage(raw: fresh.stage).isRunning && fresh.searching != true {
                        await self.refreshJobs()
                        return
                    }
                } catch {
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    // MARK: 操作
    func createJob(files: [(String, Data, String)], meta: ExamMeta) async {
        busy = true
        defer { busy = false }
        do {
            let job = try await APIClient.createJob(
                files: files.map { (name: $0.0, data: $0.1, mime: $0.2) }, meta: meta)
            current = job
            startPolling(job.id)
            await refreshJobs()
        } catch {
            errorText = error.localizedDescription
        }
    }

    func updateMeta(_ meta: ExamMeta) async {
        guard let id = current?.id else { return }
        do {
            current = try await APIClient.patchMeta(id, meta: meta)
        } catch { errorText = error.localizedDescription }
    }

    func startSearch() async {
        guard let id = current?.id else { return }
        do {
            try await APIClient.search(id)
            current?.searching = true
            startPolling(id)
        } catch { errorText = error.localizedDescription }
    }

    func choose(index: Int, candidate: Int) async {
        guard let id = current?.id else { return }
        do {
            try await APIClient.choose(id, index: index, choice: ["type": "jyeoo", "index": candidate])
            current = try await APIClient.job(id)
        } catch { errorText = error.localizedDescription }
    }

    func redraw(index: Int, mode: String = "ai") async {
        guard let id = current?.id else { return }
        do {
            try await APIClient.redraw(id, index: index, mode: mode)
            current = try await APIClient.job(id)
        } catch { errorText = error.localizedDescription }
    }

    func render(mode: String = "image") async {
        guard let id = current?.id else { return }
        do {
            current = try await APIClient.render(id, mode: mode)
            await refreshJobs()
        } catch { errorText = error.localizedDescription }
    }
}
