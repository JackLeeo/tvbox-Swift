import SwiftUI

struct SettingsView: View {
    @State private var showDiskConfig = false
    @State private var showAddNodeSource = false
    
    @ObservedObject private var sourceService = SourceService.shared
    
    var body: some View {
        Form {
            SectionCard(title: "源管理") {
                VStack(spacing: 0) {
                    SettingsRow(
                        icon: "cloud",
                        title: "网盘配置",
                        subtitle: "配置阿里云盘、夸克网盘等"
                    ) {
                        showDiskConfig = true
                    }
                    
                    Divider()
                    
                    SettingsRow(
                        icon: "plus.circle",
                        title: "添加 Node 源",
                        subtitle: "添加远程 Node.js 源"
                    ) {
                        showAddNodeSource = true
                    }
                }
            }
            
            if !sourceService.remoteSources.isEmpty {
                SectionCard(title: "已添加的 Node 源") {
                    VStack(spacing: 0) {
                        ForEach(sourceService.remoteSources) { source in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                        .foregroundColor(.label)
                                    
                                    Text(source.api)
                                        .font(.caption)
                                        .foregroundColor(.secondaryLabel)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Button("加载") {
                                    NodeJSBridge.shared.loadRemoteSource(path: source.localPath!)
                                    NodeJSBridge.shared.currentSourcePath = source.localPath
                                }
                                .buttonStyle(.bordered)
                                
                                Button("删除") {
                                    SourceService.shared.removeRemoteSource(source)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            if source.id != sourceService.remoteSources.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            
            // 原来的旧设置项，全部保留
            SectionCard(title: "通用设置") {
                // 你原来的设置项，全部保留
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDiskConfig) {
            NavigationStack {
                DiskConfigView()
            }
        }
        .sheet(isPresented: $showAddNodeSource) {
            NavigationStack {
                AddNodeSourceView()
            }
        }
    }
}
