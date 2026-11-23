import SwiftUI

// MARK: - 玻璃背景

struct GlassBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [Color.accentColor.opacity(0.16), Color.clear, Color.indigo.opacity(0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.cyan.opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: 120, y: -280)
            Circle()
                .fill(Color.pink.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -140, y: 300)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 玻璃卡片

struct GlassCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
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

// MARK: - 状态胶囊

struct StageBadge: View {
    let stage: Job.Stage

    private var tint: Color {
        switch stage {
        case .ready: return .green
        case .exported: return .blue
        case .failed: return .red
        default: return .orange
        }
    }

    var body: some View {
        Text(stage.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}

// MARK: - 设置行

struct GlassRow<Content: View>: View {
    let title: String
    let systemImage: String
    var content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 8)
            content
        }
    }
}
