import SwiftUI

struct SearchView: View {
    @StateObject var viewModel: SearchViewModel

    #if os(iOS)
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: AppTheme.spacingMD)
    ]
    #else
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppTheme.spacingLG)
    ]
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if viewModel.activeSites.isEmpty && !viewModel.isSearching {
                    searchHistorySection
                } else {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            siteListPanel
                                .frame(width: min(max(geo.size.width * 0.28, 120), 220))
                            Divider()
                            resultsPanel
                        }
                    }
                }
            }
            .background(AppBackground())
            .navigationTitle("搜索")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var searchBar: some View {
        HStack(spacing: AppTheme.spacingMD) {
            HStack(spacing: AppTheme.spacingSM + AppTheme.spacingXS) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: AppTheme.fontHeadline, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)

                TextField("搜索影片...", text: $viewModel.keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: AppTheme.fontHeadline))
                    .foregroundColor(AppTheme.textPrimary)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await viewModel.search() }
                    }
                    #if os(iOS)
                    .autocapitalization(.none)
                    #endif

                if !viewModel.keyword.isEmpty {
                    Button {
                        withAnimation {
                            viewModel.keyword = ""
                            viewModel.resultsBySite.removeAll()
                            viewModel.searchingStatus.removeAll()
                            viewModel.resultCount.removeAll()
                            viewModel.activeSites = []
                            viewModel.selectedSiteKey = nil
                            viewModel.isSearching = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.vertical, AppTheme.spacingMD)
            .background(AppTheme.backgroundSecondary)
            .cornerRadius(AppTheme.radiusLG)

            Button {
                Task { await viewModel.search() }
            } label: {
                Text("搜索")
                    .font(.system(size: AppTheme.fontHeadline, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppTheme.spacingLG)
                    .padding(.vertical, AppTheme.spacingMD)
                    .background(AppTheme.accentGradient)
                    .cornerRadius(AppTheme.radiusMD)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.spacingXL)
        .padding(.top, AppTheme.spacingXL)
        .padding(.bottom, AppTheme.spacingMD)
    }

    private var siteListPanel: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.spacingXS) {
                ForEach(viewModel.activeSites) { site in
                    siteRow(site)
                }
            }
            .padding(.vertical, AppTheme.spacingSM)
        }
        .background(AppTheme.backgroundSecondary)
    }

    private func siteRow(_ site: SourceBean) -> some View {
        let isSelected = viewModel.selectedSiteKey == site.key
        let isSearching = viewModel.searchingStatus[site.key] ?? false
        let count = viewModel.resultCount[site.key] ?? 0

        return Button {
            viewModel.selectSite(site.key)
        } label: {
            HStack(spacing: AppTheme.spacingSM) {
                VStack(alignment: .leading, spacing: AppTheme.spacingXS) {
                    Text(site.name)
                        .font(.system(size: AppTheme.fontSubhead))
                        .foregroundColor(isSelected ? AppTheme.accentColor : AppTheme.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: AppTheme.spacingXS) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(AppTheme.textTertiary)
                            Text("搜索中...")
                                .font(.system(size: AppTheme.fontCaption))
                                .foregroundColor(AppTheme.textTertiary)
                        } else {
                            Text("\(count) 条结果")
                                .font(.system(size: AppTheme.fontCaption))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, AppTheme.spacingMD)
            .padding(.vertical, AppTheme.spacingSM + AppTheme.spacingXS)
            .background(isSelected ? AppTheme.accentColor.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSM))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppTheme.spacingSM)
    }

    private var resultsPanel: some View {
        Group {
            if viewModel.selectedSiteKey == nil {
                VStack {
                    Spacer()
                    AppErrorView(message: "请输入搜索关键词")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isCurrentSiteSearching && viewModel.currentResults.isEmpty {
                VStack {
                    Spacer()
                    AppLoadingView(message: "搜索中...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.currentResults.isEmpty {
                VStack {
                    Spacer()
                    AppErrorView(message: "暂无搜索结果")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: AppTheme.spacingLG) {
                        ForEach(viewModel.currentResults) { video in
                            NavigationLink(value: video) {
                                VodCardView(video: video)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXL)
                    .padding(.vertical, AppTheme.spacingMD)
                }
                .navigationDestination(for: Movie.Video.self) { video in
                    DetailView(video: video)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchHistorySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            if !viewModel.searchHistory.isEmpty {
                HStack {
                    Text("搜索历史")
                        .font(.system(size: AppTheme.fontHeadline, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Button {
                        viewModel.clearHistory()
                    } label: {
                        HStack(spacing: AppTheme.spacingXS) {
                            Image(systemName: "trash")
                            Text("清空")
                        }
                        .font(.system(size: AppTheme.fontCaption))
                        .foregroundColor(AppTheme.textTertiary)
                    }
                }
                .padding(.horizontal, AppTheme.spacingXL)
                .padding(.top, AppTheme.spacingLG)

                if #available(iOS 16.0, *) {
                    FlowLayout(spacing: AppTheme.spacingSM) {
                        ForEach(viewModel.searchHistory, id: \.self) { keyword in
                            SelectableChip(
                                title: keyword,
                                isSelected: false
                            ) {
                                viewModel.keyword = keyword
                                Task { await viewModel.search() }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXL)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: AppTheme.spacingSM) {
                        ForEach(viewModel.searchHistory, id: \.self) { keyword in
                            SelectableChip(
                                title: keyword,
                                isSelected: false
                            ) {
                                viewModel.keyword = keyword
                                Task { await viewModel.search() }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXL)
                }
            }

            Spacer()
        }
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = AppTheme.spacingSM

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangement(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangement(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
