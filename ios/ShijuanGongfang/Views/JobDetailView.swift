import SwiftUI

struct JobDetailView: View {
    let jobID: String

    @EnvironmentObject private var store: Store
    @State private var mode: OutputMode = .image
    @State private var preview: Question?

    private var job: Job? {
        store.jobs.first { $0.id == jobID }
    }

    var body: some View {
        ScrollView {
            if let job = job {
                VStack(spacing: 14) {
                    statusCard(job)
                    exportCard(job)
                    questionsCard(job)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 32)
            } else {
                Text("任务不存在")
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
            }
        }
        .background(GlassBackground())
        .navigationTitle(job?.meta.previewName ?? "任务")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let job = job { mode = job.outputMode }
        }
        .sheet(item: $preview) { question in
            QuestionPreview(jobID: jobID, question: question, mode: mode)
        }
    }

    // MARK: 状态

    private func statusCard(_ job: Job) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StageBadge(stage: job.stage)
                    Spacer()
                    Text(job.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if job.stage.isRunning {
                    ProgressView(value: job.progress)
                        .tint(.accentColor)
                }

                Text(job.statusText + (job.errorText == nil ? "" : "\n" + (job.errorText ?? "")))
                    .font(.footnote)
                    .foregroundStyle(job.errorText == nil ? .secondary : .red)

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("端侧处理，内容不上传")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 导出

    private func exportCard(_ job: Job) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("输出")
                    .font(.subheadline.weight(.semibold))

                Picker("输出模式", selection: $mode) {
                    ForEach(OutputMode.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Text(mode.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        store.export(job.id, mode: mode)
                    } label: {
                        Label("生成 PDF", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(job.questions.isEmpty || job.stage == .exporting)

                    if let url = paperURL(job) {
                        ShareLink(item: url) {
                            Label("分享", systemImage: "paperplane")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }

                if let path = job.paperPath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: 题目

    private func questionsCard(_ job: Job) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("题目")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(String(job.questions.count) + " 题")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if job.questions.isEmpty {
                    Text(job.stage.isRunning ? "识别完成后这里会列出题目" : "没有拆出题目，可检查文件是否清晰")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(job.questions) { question in
                        Button {
                            preview = question
                        } label: {
                            QuestionRow(jobID: job.id, question: question)
                        }
                        .buttonStyle(.plain)
                        if question.id != job.questions.last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
    }

    private func paperURL(_ job: Job) -> URL? {
        guard let path = job.paperPath else { return nil }
        return AppPaths.crop(AppPaths.dir(job.id), path: path)
    }
}

// MARK: - 题目行

struct QuestionRow: View {
    let jobID: String
    let question: Question

    private var cropped: UIImage? {
        guard let path = question.cropFile else { return nil }
        return UIImage(contentsOfFile: AppPaths.crop(AppPaths.dir(jobID), path: path).path)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = cropped {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .background(Color.white.opacity(0.25))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 84, height: 84)
                    .overlay(Text(String(question.no)).font(.headline).foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("第 " + String(question.no) + " 题")
                        .font(.footnote.weight(.semibold))
                    if let section = question.section {
                        Text(section)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(question.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}

// MARK: - 题目预览

struct QuestionPreview: View {
    let jobID: String
    let question: Question
    let mode: OutputMode

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let path = question.cropFile,
                       let image = UIImage(contentsOfFile: AppPaths.crop(AppPaths.dir(jobID), path: path).path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("识别文字")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(question.text)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(18)
            }
            .background(GlassBackground())
            .navigationTitle("第 " + String(question.no) + " 题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
