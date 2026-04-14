import SwiftUI

struct SettingsView: View {
    @State private var showDiskConfig = false
    @State private var showAddSource = false
    
    var body: some View {
        NavigationStack {
            List {
                SectionCard(title: "源管理") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "folder",
                            title: "网盘配置",
                            subtitle: "配置阿里云盘、夸克网盘等"
                        ) {
                            showDiskConfig = true
                        }
                        
                        SettingsRow(
                            icon: "globe",
                            title: "添加 Node 源",
                            subtitle: "自动下载远程 Node.js 源"
                        ) {
                            showAddSource = true
                        }
                    }
                }
                
                SectionCard(title: "通用设置") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "play",
                            title: "播放器设置",
                            subtitle: "自定义解码方式"
                        ) {
                            // 播放器设置
                        }
                        
                        SettingsRow(
                            icon: "cache",
                            title: "缓存清理",
                            subtitle: "清理下载的源文件"
                        ) {
                            // 缓存清理
                        }
                    }
                }
                
                SectionCard(title: "关于") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "info",
                            title: "版本信息",
                            subtitle: "查看当前版本"
                        ) {
                            // 关于页面
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showDiskConfig) {
                DiskConfigView()
            }
            .sheet(isPresented: $showAddSource) {
                AddNodeSourceView()
            }
        }
    }
}

// MARK: - 公共组件（修复：从 private 改为 internal，所有页面都能访问）
struct SectionCard<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondaryLabel)
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                content
            }
            .background(Color.secondaryBackground)
            .cornerRadius(12)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.tint)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.label)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondaryLabel)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.tertiaryLabel)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}
