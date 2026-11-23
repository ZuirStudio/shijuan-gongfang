import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("default_output_mode") private var modeRaw = OutputMode.image.rawValue
    @AppStorage("enhance_enabled") private var enhance = true
    @AppStorage("max_pages") private var maxPages = 30
    @AppStorage("ocr_languages") private var languages = "zh-Hans,en-US"

    @State private var showClearConfirm = false

    private var mode: OutputMode {
        OutputMode(rawValue: modeRaw) ?? .image
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("默认输出模式", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                        ForEach(OutputMode.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    Text(mode.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("输出")
                }

                Section {
                    Toggle("增强清晰度", isOn: $enhance)
                    Stepper(value: $maxPages, in: 5...80, step: 5) {
                        Text("最多处理 " + String(maxPages) + " 页")
                    }
                    Picker("识别语言", selection: $languages) {
                        Text("简体中文 + 英文").tag("zh-Hans,en-US")
                        Text("仅简体中文").tag("zh-Hans")
                        Text("中文 + 英文 + 日文").tag("zh-Hans,en-US,ja-JP")
                    }
                } header: {
                    Text("识别")
                } footer: {
                    Text("识别由系统 Vision 引擎在本机完成，不会把图像上传到任何服务器。")
                }

                Section {
                    HStack {
                        Text("已存任务")
                        Spacer()
                        Text(String(store.jobs.count))
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        showClearConfirm = true
                    } label: {
                        Text("清空所有任务")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("本地数据")
                } footer: {
                    Text("删除后，对应页面图、题图和导出 PDF 会一并移除，不可恢复。")
                }

                Section {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0").foregroundStyle(.secondary)
                    }
                    Text("试卷工坊 · 端侧版。导入 PDF 或照片后，在本机完成增强、文字识别、拆题与排版导出，全程不联网、不依赖服务器。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("关于")
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("清空所有任务？", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    for job in store.jobs {
                        store.delete(job.id)
                    }
                }
            }
        }
    }
}
