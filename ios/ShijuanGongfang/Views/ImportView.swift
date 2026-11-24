import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("default_output_mode") private var modeRaw = OutputMode.image.rawValue
    @AppStorage("enhance_enabled") private var enhance = true
    @AppStorage("max_pages") private var maxPages = 30
    @AppStorage("ocr_languages") private var languages = "zh-Hans,en-US"

    @State private var meta = ExamMeta()
    @State private var picked: [Picked] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var errorMessage: String?

    struct Picked: Identifiable {
        let id = UUID()
        let name: String
        let data: Data
    }

    private var mode: OutputMode {
        OutputMode(rawValue: modeRaw) ?? .image
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    filesCard
                    metaCard
                    optionsCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(GlassBackground())
            .navigationTitle("新建")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") { start() }
                        .fontWeight(.semibold)
                        .disabled(picked.isEmpty)
                }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [UTType.item], allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .onChange(of: photoItems) { _, items in
                loadPhotos(items)
            }
            .alert("无法导入", isPresented: Binding(get: { errorMessage != nil },
                                            set: { if !$0 { errorMessage = nil } })) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: 文件

    private var filesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("试卷文件")
                    .font(.subheadline.weight(.semibold))

                Button {
                    showFiles = true
                } label: {
                    Label("从「文件」导入 PDF / 图片", systemImage: "folder")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
                    Label("从相册选照片（可多选）", systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Text("支持 PDF、JPG、PNG、HEIC。Word 文档请先导出 PDF 再导入。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !picked.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(picked) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tint)
                                Text(item.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(sizeText(item.data.count))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Button {
                                    picked.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: 试卷信息

    private var metaCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("试卷信息")
                    .font(.subheadline.weight(.semibold))

                field("学年", text: $meta.xuenian, placeholder: "2026-2027学年")
                field("省/直辖市", text: $meta.sheng, placeholder: "天津市")
                field("地级市", text: $meta.shi, placeholder: "天津市")
                field("区县", text: $meta.qu, placeholder: "南开区")
                field("学校（可空）", text: $meta.school, placeholder: "可选")

                menuRow(title: "年级", value: $meta.nianji, options: optionsNianji)
                menuRow(title: "学期", value: $meta.xueqi, options: optionsXueqi)
                menuRow(title: "类型", value: $meta.leixing, options: optionsLeixing)
                menuRow(title: "学科", value: $meta.xueke, options: optionsXueke)

                HStack {
                    Text("预览名称").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(meta.previewName)
                        .font(.caption2)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
                .padding(.top, 2)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    private func menuRow(title: String, value: Binding<String>, options: [String]) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Picker(title, selection: value) {
                ForEach(options, id: \.self) { item in
                    Text(item).tag(item)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: 选项

    private var optionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("处理选项")
                    .font(.subheadline.weight(.semibold))

                Picker("默认输出", selection: Binding(get: { mode }, set: { modeRaw = $0.rawValue })) {
                    ForEach(OutputMode.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Text(mode.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle("增强清晰度（提升扫描件与照片的辨识率）", isOn: $enhance)
                    .font(.caption)

                Stepper(value: $maxPages, in: 5...80, step: 5) {
                    Text("最多处理 " + String(maxPages) + " 页")
                        .font(.caption)
                }

                Text("全部在本机完成 · 不上传、不联网")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 动作

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var failed: [String] = []
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else {
                    failed.append(url.lastPathComponent)
                    continue
                }
                guard isSupported(data: data, name: url.lastPathComponent) else {
                    failed.append(url.lastPathComponent)
                    continue
                }
                picked.append(Picked(name: url.lastPathComponent, data: data))
            }
            if !failed.isEmpty {
                errorMessage = "下面这些文件没能导入（目前只支持 PDF 与图片，Word 请先导出 PDF）：" + failed.joined(separator: "、")
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func isSupported(data: Data, name: String) -> Bool {
        if PDFDocumentCheck.isPDF(data: data) { return true }
        if UIImage(data: data) != nil { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "pdf" || ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "heic"
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let name = "照片" + String(index + 1) + ".jpg"
                    let value = Picked(name: name, data: data)
                    await MainActor.run {
                        picked.append(value)
                    }
                }
            }
            await MainActor.run {
                photoItems = []
            }
        }
    }

    private func start() {
        let payloads = picked.map { (name: $0.name, data: $0.data) }
        store.create(files: payloads,
                     meta: meta,
                     mode: mode,
                     enhance: enhance,
                     maxPages: maxPages,
                     languages: parseLanguages(languages))
        dismiss()
    }

    private func parseLanguages(_ raw: String) -> [String] {
        var result: [String] = []
        for part in raw.split(separator: ",") {
            let value = part.trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { result.append(value) }
        }
        if result.isEmpty { result = ["zh-Hans"] }
        return result
    }

    private func sizeText(_ bytes: Int) -> String {
        if bytes > 1024 * 1024 {
            return String(bytes / (1024 * 1024)) + " MB"
        }
        return String(Swift.max(1, bytes / 1024)) + " KB"
    }

    private var optionsNianji: [String] { ["七年级", "八年级", "九年级", "高一", "高二", "高三"] }
    private var optionsXueqi: [String] { ["上学期", "下学期"] }
    private var optionsLeixing: [String] { ["月考", "期中", "期末", "一模", "二模", "模拟", "单元测试"] }
    private var optionsXueke: [String] { ["语文", "数学", "英语", "物理", "化学", "生物", "政治", "历史", "地理"] }
}

// PDF 文件头探测（避免引入 PDFKit 也能判断）
enum PDFDocumentCheck {
    static func isPDF(data: Data) -> Bool {
        guard data.count > 4 else { return false }
        let head = data.prefix(5)
        let text = String(data: head, encoding: .ascii) ?? ""
        return text.hasPrefix("%PDF")
    }
}
