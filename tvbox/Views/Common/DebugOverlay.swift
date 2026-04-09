import SwiftUI

/// 悬浮调试窗口，显示实时日志
struct DebugOverlay: View {
    @ObservedObject var logger = Logger.shared
    @State private var isExpanded = false
    @State private var isVisible = true
    
    var body: some View {
        if isVisible {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    // 标题栏
                    HStack {
                        Text("📋 调试日志")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { isExpanded.toggle() }) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                        Button(action: { logger.clear() }) {
                            Image(systemName: "trash")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                        Button(action: { isVisible = false }) {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    
                    if isExpanded {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(logger.messages) { entry in
                                        HStack(alignment: .top, spacing: 4) {
                                            Text(entry.formattedTime)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.gray)
                                            Text(entry.message)
                                                .font(.system(size: 10))
                                                .foregroundColor(logColor(for: entry.level))
                                                .lineLimit(3)
                                        }
                                        .id(entry.id)
                                    }
                                }
                                .padding(6)
                            }
                            .frame(maxHeight: 200)
                            .background(Color.black.opacity(0.8))
                            .onChange(of: logger.messages.count) { _ in
                                if let last = logger.messages.last {
                                    withAnimation {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.9))
                .cornerRadius(8)
                .padding(8)
            }
            .transition(.move(edge: .bottom))
        }
    }
    
    private func logColor(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .white
        case .warning: return .yellow
        case .error: return .red
        }
    }
}

/// 用于在 App 启动后显示调试窗口的小按钮（当悬浮窗被关闭时可用）
struct DebugToggleButton: View {
    @State private var showOverlay = false
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { showOverlay.toggle() }) {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.orange.opacity(0.8))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .padding(16)
            }
        }
        .overlay(
            Group {
                if showOverlay {
                    DebugOverlay()
                }
            }
        )
    }
}
