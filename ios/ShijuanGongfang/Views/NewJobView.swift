import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct NewJobView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var meta = ExamMeta()
    @State private var pickedFiles: [PickedFile] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showImporter = false
    @State private var uploading = false

    struct PickedFile: Identifiable {
        let id = UUID()
        let name: String
        let data: Data
        let mime: String
    }

    var body: some View {
        NavigationStack {
            Form {
                fileSection
                metaSection
            }
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: allowedTypes) { result in
                handleImport(result)
            }
            .onChange(of: photoItems) { _, items in
                Task { await loadPhotos(items) }
            }
        }
    }

    private var allowedTypes: [UTType] {
        [UTType.pdf, UTType.data]
    }

    @ViewBuilder
    private var fileSection: some View {
        Section("试卷文件") {
            Button {
                showImporter = true
            } label: {
                Label("从「文件」选择 PDF / DOC / DOCX", systemImage: "doc.badge.plus")
            }

            PhotosPicker(selection: $photoItems, maxSelectionCount: 12, matching: .images) {
                Label("从相册选择照片（可多选）", systemImage: "photo.on.rectangle.angled")
            }

            ForEach(pickedFiles) { f in
                fileRow(f)
            }
            .onDelete { idx in pickedFiles.remove(atOffsets: idx) }
        }
    }

    @ViewBuilder
    private func fileRow(_ f: PickedFile) -> some View {
        let isPDF = (f.mime == "application/pdf")
        let icon = isPDF ? "doc.richtext" : "photo"
        let size = "\(f.data.count / 1024) KB"
        HStack {
            Image(systemName: icon)
            Text(f.name).font(.footnote).lineLimit(1)
            Spacer()
            Text(size).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metaSection: some View {
        Section("试卷信息（用于命名与排版）") {
            TextField("学年，如 2026-2027学年", text: $meta.xuenian)
            TextField("省/直辖市，如 天津市", text: $meta.sheng)
            TextField("地级市，如 天津市", text: $meta.shi)
            TextField("区县，如 南开区", text: $meta.qu)
            TextField("学校（可空）", text: $meta.school)
            Picker("年级", selection: $meta.nianji) {
                ForEach(nianjiList, id: \.self) { Text($0) }
            }
            Picker("学期", selection: $meta.xueqi) {
                ForEach(xueqiList, id: \.self) { Text($0) }
            }
            Picker("类型", selection: $meta.leixing) {
                ForEach(leixingList, id: \.self) { Text($0) }
            }
            Picker("学科", selection: $meta.xueke) {
                ForEach(xuekeList, id: \.self) { Text($0) }
            }
            previewRow
        }
    }

    private var nianjiList: [String] { ["七年级", "八年级", "九年级", "高一", "高二", "高三"] }
    private var xueqiList: [String] { ["上学期", "下学期"] }
    private var leixingList: [String] { ["月考", "期中", "期末", "一模", "二模", "模拟", "单元测试"] }
    private var xuekeList: [String] { ["语文", "数学", "英语", "物理", "化学", "生物", "政治", "历史", "地理"] }

    @ViewBuilder
    private var previewRow: some View {
        HStack {
            Text("预览名称").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(meta.previewName + ".pdf").font(.caption2).lineLimit(2).multilineTextAlignment(.trailing)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(uploading ? "上传中…" : "开始") {
                Task { await upload() }
            }
            .disabled(pickedFiles.isEmpty || uploading)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let mime = ext == "pdf" ? "application/pdf"
            : ext == "docx" ? "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            : "application/msword"
        pickedFiles.append(PickedFile(name: url.lastPathComponent, data: data, mime: mime))
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for (i, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let name = "photo_\(i + 1).jpg"
            pickedFiles.append(PickedFile(name: name, data: data, mime: "image/jpeg"))
        }
        photoItems = []
    }

    private func upload() async {
        uploading = true
        await store.createJob(
            files: pickedFiles.map { ($0.name, $0.data, $0.mime) }, meta: meta)
        uploading = false
        dismiss()
    }
}
