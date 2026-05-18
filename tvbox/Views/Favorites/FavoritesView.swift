import SwiftUI

struct FavoritesView: View {
    @ObservedObject private var store = CacheStore.shared

    #if os(iOS)
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: AppTheme.spacingMD)
    ]
    #else
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppTheme.spacingLG)
    ]
    #endif

    private var sortedFavorites: [VodCollect] {
        store.favorites.sorted(by: { $0.updateTime > $1.updateTime })
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedFavorites.isEmpty {
                    AppErrorView(message: "暂无收藏\n遇到喜欢的影片别忘了点下收藏按钮哦！")
                        .padding(AppTheme.spacingXXL * 2)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: AppTheme.spacingLG) {
                            ForEach(sortedFavorites) { item in
                                NavigationLink(value: movieVideo(from: item)) {
                                    favoriteCard(item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.removeCollect(vodId: item.vodId, sourceKey: item.sourceKey)
                                    } label: {
                                        Label("取消收藏", systemImage: "heart.slash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, AppTheme.spacingXL)
                        .padding(.vertical, AppTheme.spacingMD)
                    }
                }
            }
            .background(AppBackground())
            .navigationTitle("收藏")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: Movie.Video.self) { video in
                DetailView(video: video)
            }
        }
    }

    private func favoriteCard(_ item: VodCollect) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS + 2) {
            CachedAsyncImage(url: URL.posterURL(from: item.vodPic)) { image in
                image.resizable().aspectRatio(2/3, contentMode: .fill)
            } placeholder: {
                Rectangle().fill(AppTheme.backgroundTertiary)
                    .aspectRatio(2/3, contentMode: .fill)
                    .overlay(Image(systemName: "film").foregroundColor(AppTheme.textTertiary))
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSM))

            Text(item.vodName)
                .font(.system(size: AppTheme.fontCaption))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)
        }
    }

    private func movieVideo(from item: VodCollect) -> Movie.Video {
        Movie.Video(id: item.vodId, name: item.vodName, pic: item.vodPic, sourceKey: item.sourceKey)
    }
}
