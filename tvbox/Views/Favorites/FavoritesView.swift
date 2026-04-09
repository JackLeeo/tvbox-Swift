import SwiftUI

/// 收藏页 - 对应 Android 版 CollectActivity
struct FavoritesView: View {
    /// 收藏数据，通过 @State 手动管理。
    @State private var favorites: [VodCollect] = []
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
                } else if favorites.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(favorites) { item in
                                NavigationLink(value: movieVideo(from: item)) {
                                    favoriteCard(item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        removeFavorite(item)
                                    } label: {
                                        Label("取消收藏", systemImage: "heart.slash")
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
            .navigationTitle("收藏")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: Movie.Video.self) { video in
                DetailView(video: video)
            }
        }
        .onAppear {
            loadFavorites()
        }
    }
    
    private var emptyState: some View {
        EmptyStateView(
            icon: "heart.text.square",
            title: "暂无收藏",
            message: "遇到喜欢的影片别忘了点下收藏按钮哦！"
        )
        .padding(40)
    }
    
    private func favoriteCard(_ item: VodCollect) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedAsyncImage(url: URL.posterURL(from: item.vodPic)) { image in
                image.resizable().aspectRatio(2/3, contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
                    .aspectRatio(2/3, contentMode: .fill)
                    .overlay(Image(systemName: "film").foregroundColor(.gray))
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(item.vodName)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(2)
        }
    }
    
    private func movieVideo(from item: VodCollect) -> Movie.Video {
        Movie.Video(id: item.vodId, name: item.vodName, pic: item.vodPic, sourceKey: item.sourceKey)
    }
    
    private func loadFavorites() {
        Task {
            let data = await CacheStore.shared.getAllCollects()
            await MainActor.run {
                favorites = data
                isLoading = false
            }
        }
    }
    
    private func removeFavorite(_ item: VodCollect) {
        Task {
            await CacheStore.shared.removeCollect(vodId: item.vodId, sourceKey: item.sourceKey)
            await MainActor.run {
                favorites.removeAll { $0.bizKey == item.bizKey }
            }
        }
    }
}
