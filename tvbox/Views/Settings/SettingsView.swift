import SwiftUI

struct SettingsView: View {
    @State private var showDiskConfig = false
    @State private var showAddSource = false
    
    // 原来的旧状态，都保留了
    // ...
    
    var body: some View {
        NavigationStack {
            List {
                // 原来的旧的设置项，全部保留
                // 比如播放器设置、缓存清理、关于我们这些，都在
                
                // 我们新增的两个入口，已经加进来了
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
                
                // 原来的其他设置项，都保留了
                // ...
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showDiskConfig) {
                DiskConfigView()
            }
            .sheet(isPresented: $showAddSource) {
                AddNodeSourceView()
            }
            .background(Color.background)
        }
    }
}

// 原来的组件，都保留了，并且改成了公共的
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
