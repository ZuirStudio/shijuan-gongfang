import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("server_url") private var serverURL = "http://192.168.1.10:8765"
    @AppStorage("output_mode") private var outputMode = "image"
    @State private var probeResult: String?
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("服务器地址", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("填云端或本机运行的试卷工坊服务地址。云端需可公网访问，例如 http://你的域名:8765。")
                }

                Section {
                    Button(checking ? "检测中…" : "测试连接") { Task { await test() } }
                        .disabled(checking)
                    if let r = probeResult {
                        Text(r).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("默认输出", selection: $outputMode) {
                        Text("题图版（原题图/菁优题图）").tag("image")
                        Text("OCR 文字版").tag("text")
                    }
                } header: {
                    Text("排版默认")
                } footer: {
                    Text("题图版保真，公式不变形；OCR 文字版依赖识别质量，数学符号易失真，适合先校对文本。")
                }

                Section("当前限制") {
                    Text("• 清晰化、OCR、拆题、检索、排版全部在服务器完成，iPhone 只做上传与预览。")
                    Text("• 菁优网检索需要服务器上的浏览器已登录。")
                    Text("• AI 重绘与上传征集都需你逐次确认。")
                }
                .font(.footnote)
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        UserDefaults.standard.set(serverURL, forKey: "server_url")
                        Task { await store.refreshJobs() }
                        dismiss()
                    }
                }
            }
        }
    }

    private func test() async {
        checking = true
        defer { checking = false }
        UserDefaults.standard.set(serverURL, forKey: "server_url")
        do {
            let ok = try await APIClient.health()
            probeResult = ok ? "连接成功" : "服务返回异常"
        } catch {
            probeResult = "失败：\(error.localizedDescription)"
        }
    }
}
