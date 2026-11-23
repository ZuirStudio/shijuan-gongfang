import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: Store
    @State private var showImport = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.jobs.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.jobs) { job in
                            NavigationLink(value: job.id) {
                                JobCard(job: job)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(GlassBackground())
            .scrollIndicators(.hidden)
            .navigationTitle("试卷工坊")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { id in
                JobDetailView(jobID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                ImportView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tint)
            Text("还没有试卷")
                .font(.title3.weight(.semibold))
            Text("点右上角 + 导入 PDF 或照片。识别、拆题、排版全部在本机完成，不上传任何内容。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showImport = true
            } label: {
                Label("导入第一份试卷", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.top, 40)
    }
}

struct JobCard: View {
    let job: Job

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(job.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Spacer(minLength: 6)
                StageBadge(stage: job.stage)
            }

            Text(job.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if job.stage.isRunning {
                ProgressView(value: job.progress)
                    .tint(.accentColor)
                Text(job.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if job.stage == .failed {
                Text(job.errorText ?? "处理失败")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                Text(job.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.07), radius: 16, x: 0, y: 8)
    }
}
