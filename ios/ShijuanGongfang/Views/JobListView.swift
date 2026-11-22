import SwiftUI

struct JobListView: View {
    @EnvironmentObject var store: Store
    @State private var showNew = false
    @State private var showSettings = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    Circle()
                        .fill(store.serverOnline ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(store.serverOnline ? "已连接服务器" : "未连接服务器")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(store.serverURL).font(.caption2).foregroundStyle(.tertiary)
                }
            }

            if let err = store.errorText, !store.serverOnline {
                Section { Text(err).font(.footnote).foregroundStyle(.secondary) }
            }

            Section("任务") {
                if store.jobs.isEmpty {
                    Text("还没有任务，点右上角「＋」上传一份试卷。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(store.jobs) { job in
                    NavigationLink {
                        JobDetailView(jobID: job.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(job.preview).font(.subheadline).lineLimit(2)
                            HStack(spacing: 8) {
                                Text(JobStage(raw: job.stage).label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                Text("\(job.count) 题").font(.caption2).foregroundStyle(.secondary)
                                Text(job.id).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("试卷工坊")
        .refreshable { await store.refreshJobs() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus.circle.fill") }
            }
        }
        .sheet(isPresented: $showNew) {
            NewJobView().environmentObject(store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
    }
}
