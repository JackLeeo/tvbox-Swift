import SwiftUI

struct HistoryView: View {
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

    private var sortedRecords: [VodRecord] {
        store.records.sorted(by: { $0.updateTime > $1.updateTime })
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedRecords.isEmpty {
                    AppErrorView(message: "暂无播放记录\n您还没有看任何视频，赶快去首页探索吧！")
                        .padding(AppTheme.spacingXXL * 2)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: AppTheme.spacingLG) {
                            ForEach(sortedRecords) { item in
                                NavigationLink(value: movieVideo(from: item)) {
                                    recordCard(item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.removeRecord(vodId: item.vodId, sourceKey: item.sourceKey)
                                    } label: {
                                        Label("删除记录", systemImage: "trash")
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
            .navigationTitle("历史记录")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if !sortedRecords.isEmpty {
                        Button {
                            store.clearHistory()
                        } label: {
                            Text("清空")
                                .foregroundColor(AppTheme.accentColor)
                        }
                    }
                }
            }
            .navigationDestination(for: Movie.Video.self) { video in
                DetailView(video: video)
            }
        }
    }

    private func recordCard(_ item: VodRecord) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingXS + 2) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: URL.posterURL(from: item.vodPic)) { image in
                    image.resizable().aspectRatio(2/3, contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(AppTheme.backgroundTertiary)
                        .aspectRatio(2/3, contentMode: .fill)
                        .overlay(Image(systemName: "film").foregroundColor(AppTheme.textTertiary))
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSM))

                if !item.playNote.isEmpty {
                    Text(item.playNote)
                        .font(.system(size: AppTheme.fontCaption - 2))
                        .foregroundColor(AppTheme.textPrimary)
                        .padding(.horizontal, AppTheme.spacingXS + 2)
                        .padding(.vertical, AppTheme.spacingXS - 1)
                        .background(AppTheme.backgroundPrimary.opacity(0.7))
                        .cornerRadius(AppTheme.spacingXS)
                        .padding(AppTheme.spacingXS)
                }
            }

            Text(item.vodName)
                .font(.system(size: AppTheme.fontCaption))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)

            Text(item.updateTime.displayString)
                .font(.system(size: AppTheme.fontCaption - 1))
                .foregroundColor(AppTheme.textTertiary)
        }
    }

    private func movieVideo(from item: VodRecord) -> Movie.Video {
        Movie.Video(id: item.vodId, name: item.vodName, pic: item.vodPic, sourceKey: item.sourceKey)
    }
}
