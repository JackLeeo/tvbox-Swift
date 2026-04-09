import SwiftUI

/// 历史记录页 - 对应 Android 版 HistoryActivity
struct HistoryView: View {
    @State private var records: [VodRecord] = []
    @State private var isLoading = true
    
    #if os(iOS)
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)
    ]
    #else
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]
    #endif
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if records.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(records) { item in
                                NavigationLink(value: movieVideo(from: item)) {
                                    recordCard(item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        removeRecord(item)
                                    } label: {
                                        Label("删除记录", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.1))
            .navigationTitle("历史记录")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !records.isEmpty {
                    ToolbarItem(placement: .automatic) {
                        Button("清空") {
                            clearAllHistory()
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            .navigationDestination(for: Movie.Video.self) { video in
                DetailView(video: video)
            }
        }
        .onAppear {
            loadHistory()
        }
    }
    
    private var emptyState: some View {
        EmptyStateView(
            icon: "clock.arrow.circlepath",
            title: "暂无播放记录",
            message: "您还没有看任何视频，赶快去首页探索吧！"
        )
        .padding(40)
    }
    
    private func recordCard(_ item: VodRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: URL.posterURL(from: item.vodPic)) { image in
                    image.resizable().aspectRatio(2/3, contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                        .aspectRatio(2/3, contentMode: .fill)
                        .overlay(Image(systemName: "film").foregroundColor(.gray))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if !item.playNote.isEmpty {
                    Text(item.playNote)
                        .font(.system(size: 9))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .padding(4)
                }
            }
            
            Text(item.vodName)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
            
            Text(item.updateTime.displayString)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
    }
    
    private func movieVideo(from item: VodRecord) -> Movie.Video {
        Movie.Video(id: item.vodId, name: item.vodName, pic: item.vodPic, sourceKey: item.sourceKey)
    }
    
    private func loadHistory() {
        Task {
            let data = await CacheStore.shared.getAllRecords()
            await MainActor.run {
                records = data
                isLoading = false
            }
        }
    }
    
    private func removeRecord(_ item: VodRecord) {
        Task {
            await CacheStore.shared.removeRecord(vodId: item.vodId, sourceKey: item.sourceKey)
            await MainActor.run {
                records.removeAll { $0.bizKey == item.bizKey }
            }
        }
    }
    
    private func clearAllHistory() {
        Task {
            await CacheStore.shared.clearHistory()
            await MainActor.run {
                records.removeAll()
            }
        }
    }
}
