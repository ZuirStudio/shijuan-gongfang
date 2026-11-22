import SwiftUI

struct JobDetailView: View {
    let jobID: String
    @EnvironmentObject var store: Store
    @AppStorage("output_mode") private var outputMode = "image"
    @State private var showMetaSheet = false
    @State private var showUploadSheet = false

    private var job: JobDetail? { store.current?.id == jobID ? store.current : nil }

    var body: some View {
        Group {
            if let job {
                content(job)
            } else {
                ProgressView("加载中…").task { await store.open(jobID) }
            }
        }
        .navigationTitle(job?.meta.previewName ?? "任务")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.close() }
    }

    @ViewBuilder
    private func content(_ job: JobDetail) -> some View {
        List {
            Section { StageCard(job: job) }

            if job.stage == "ready" || job.stage == "rendered" || job.searching == true {
                Section {
                    Button {
                        Task { await store.startSearch() }
                    } label: {
                        Label(job.searching == true ? "正在检索菁优网…" : "用题干检索菁优网题图",
                              systemImage: "magnifyingglass")
                    }
                    .disabled(job.searching == true)
                } footer: {
                    Text("检索结果只是候选，题图是否采用由你逐题决定；相似度低于阈值自动跳过。")
                }
            }

            Section {
                Picker("题图来源", selection: $outputMode) {
                    Text("题图版").tag("image")
                    Text("OCR 文字版").tag("text")
                }
                .pickerStyle(.segmented)

                Button {
                    Task { await store.render(mode: outputMode) }
                } label: {
                    Label("重新排版并导出 PDF", systemImage: "doc.text")
                }
                ForEach(["paper", "answer", "clean"], id: \.self) { kind in
                    if job.output?[kind] != nil { OutputRow(jobID: job.id, kind: kind) }
                }
                if job.stage == "rendered" {
                    Button {
                        showUploadSheet = true
                    } label: {
                        Label("上传到菁优网「试卷征集」", systemImage: "arrow.up.doc")
                    }
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("导出")
            } footer: {
                Text(outputMode == "text"
                     ? "OCR 文字版直接用识别文本重排，公式与符号可能失真，建议仅在校对时使用。"
                     : "题图版按原题图/菁优题图裁剪放置，公式保真；缺少题图的题目会保留文字。")
            }

            Section("题目（\(job.questions.count)）") {
                ForEach(job.questions) { q in
                    QuestionRow(jobID: job.id, q: q)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMetaSheet = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $showMetaSheet) {
            MetaEditView(meta: job.meta) { new in Task { await store.updateMeta(new) } }
        }
        .confirmationDialog("确认上传到菁优网征集栏目？", isPresented: $showUploadSheet, titleVisibility: .visible) {
            Button("确认上传") {
                Task { try? await APIClient.uploadSubmit(job.id, includeAnswer: true) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将提交「\(job.meta.previewName)」试卷与答案两份 PDF。")
        }
    }
}

// MARK: - 阶段

private struct StageCard: View {
    let job: JobDetail

    private var stage: JobStage { JobStage(raw: job.stage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stage.label).font(.headline)
                Spacer()
                if let total = job.progress?.total, total > 0 {
                    Text("\(job.progress?.done ?? 0)/\(total)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if stage.isRunning || job.searching == true {
                ProgressView(value: job.searching == true ? 0.4 : (job.progress?.fraction ?? 0.05))
            }
            if let msg = job.progress?.msg ?? job.searchProgress, !msg.isEmpty {
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 导出文件

private struct OutputRow: View {
    let jobID: String
    let kind: String
    @State private var localURL: URL?
    @State private var loading = false

    private var title: String {
        switch kind {
        case "paper": return "试卷"
        case "answer": return "答案"
        default: return "原卷清晰版"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext")
            Text(title)
            Spacer()
            if let localURL {
                ShareLink(item: localURL) { Image(systemName: "square.and.arrow.up") }
            } else {
                Button {
                    Task {
                        loading = true
                        localURL = try? await APIClient.download(jobID, kind: kind)
                        loading = false
                    }
                } label: {
                    if loading { ProgressView() } else { Image(systemName: "arrow.down.circle") }
                }
            }
        }
    }
}

// MARK: - 题目

private struct QuestionRow: View {
    let jobID: String
    let q: Question
    @EnvironmentObject var store: Store

    @State private var expanded = false
    @State private var confirmRedraw = false
    @State private var redrawMode = "ai"

    private var badgeColor: Color {
        switch q.statusLabel.1 {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "purple": return .purple
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(q.no).").font(.subheadline.bold())
                if let t = q.type, !t.isEmpty {
                    Text(t).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(q.statusLabel.0)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(badgeColor.opacity(0.15), in: Capsule())
                if let s = q.bestScore {
                    Text(String(format: "%.2f", s)).font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Text(q.text).font(.footnote).lineLimit(expanded ? nil : 2)

            if expanded {
                QuestionImage(jobID: jobID, index: q.index, kind: q.displayKind)

                if let cands = q.candidates, !cands.isEmpty {
                    ForEach(Array(cands.enumerated()), id: \.offset) { idx, c in
                        Button {
                            Task { await store.choose(index: q.index, candidate: idx) }
                        } label: {
                            HStack(spacing: 6) {
                                Text("候选 \(idx + 1)").font(.caption)
                                if let s = c.score {
                                    Text(String(format: "%.2f", s))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                HStack(spacing: 8) {
                    Button("用原卷裁剪") {
                        Task { try? await APIClient.choose(jobID, index: q.index, choice: ["type": "orig"]) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button("跳过此题") {
                        Task { try? await APIClient.choose(jobID, index: q.index, choice: ["type": "skip"]) }
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button("AI 重绘") {
                        redrawMode = "ai"
                        confirmRedraw = true
                    }
                    .buttonStyle(.bordered).controlSize(.small)

                    Button("本地渲字") {
                        redrawMode = "typeset"
                        confirmRedraw = true
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }

                if let ans = q.answer, !ans.isEmpty {
                    Text("答案：" + ans).font(.caption2).foregroundStyle(.secondary)
                }
                if q.status == "redrawn" || q.status == "matched" {
                    QuestionImage(jobID: jobID, index: q.index, kind: "answer")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { expanded.toggle() } }
        .confirmationDialog(redrawMode == "ai" ? "确认用 AI 重绘本题题图？" : "确认用本地排版渲字替换本题？",
                            isPresented: $confirmRedraw, titleVisibility: .visible) {
            Button("确认") { Task { await store.redraw(index: q.index, mode: redrawMode) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(redrawMode == "ai"
                 ? "会把题干文字与参考图发给图像模型重新作图，不再使用菁优网原图。"
                 : "用服务器字体把题干重新排版成图，公式保真度有限。")
        }
    }
}

private struct QuestionImage: View {
    let jobID: String
    let index: Int
    let kind: String

    var body: some View {
        AsyncImage(url: APIClient.imageURL(jobID, index: index, kind: kind)) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFit()
                    .frame(maxHeight: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            case .failure:
                EmptyView()
            default:
                ProgressView().frame(maxWidth: .infinity, minHeight: 40)
            }
        }
    }
}

// MARK: - 元信息编辑

private struct MetaEditView: View {
    @State var meta: ExamMeta
    let onSave: (ExamMeta) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("学年", text: $meta.xuenian)
                TextField("省", text: $meta.sheng)
                TextField("市", text: $meta.shi)
                TextField("区县", text: $meta.qu)
                TextField("学校", text: $meta.school)
                TextField("年级", text: $meta.nianji)
                TextField("学期", text: $meta.xueqi)
                TextField("类型", text: $meta.leixing)
                TextField("学科", text: $meta.xueke)
                Text("文件名预览：" + meta.previewName).font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("修改试卷信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave(meta); dismiss() }
                }
            }
        }
    }
}
