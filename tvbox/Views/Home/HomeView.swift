import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var appState: AppState
    @State private var categoryScrollAnchorId: String?
    @State private var categoryDragTranslation: CGFloat = 0
    @State private var safariUrl: URL?
    @State private var isReconnecting = false

    #if os(iOS)
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 160), spacing: AppTheme.cardSpacing)
    ]
    #else
    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: AppTheme.cardSpacing)
    ]
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar

                if !viewModel.sorts.isEmpty {
                    categoryTabBar
                }

                if !viewModel.currentFilters.isEmpty {
                    filterBar
                }

                contentArea
            }
            .background { AppBackground() }
        }
        .task {
            await viewModel.loadSorts()
            if let first = viewModel.sorts.first {
                viewModel.selectSort(first)
            }
        }
        .onChange(of: ApiConfig.shared.homeSourceBean?.key) { _ in
            Task { await viewModel.refresh() }
        }
        .sheet(item: $safariUrl) { url in
            SafariWebView(url: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .spiderServiceDidReconnect)) { _ in
            isReconnecting = false
            Task { await viewModel.refresh() }
        }
        .onChange(of: appState.loadingPhase) { newPhase in
            if newPhase == .reconnecting {
                isReconnecting = true
            } else if isReconnecting {
                if newPhase == .completed || newPhase.isFailed {
                    isReconnecting = false
                }
            }
        }
        .overlay {
            if isReconnecting {
                VStack(spacing: AppTheme.spacingMD) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(AppTheme.accentColor)
                    Text("正在重连服务...")
                        .font(.system(size: AppTheme.fontSubhead))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.horizontal, AppTheme.spacingXXL)
                .padding(.vertical, AppTheme.spacingLG)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                        .fill(AppTheme.backgroundElevated)
                )
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: AppTheme.spacingLG) {
            Menu {
                ForEach(ApiConfig.shared.sourceBeanList) { source in
                    Button {
                        ApiConfig.shared.setHomeSource(source)
                        Task { await viewModel.refresh() }
                    } label: {
                        HStack {
                            Text(source.name)
                            if source.key == ApiConfig.shared.homeSourceBean?.key {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: AppTheme.spacingSM) {
                    Image(systemName: "sparkles")
                        .foregroundColor(AppTheme.accentColor)
                    Text(ApiConfig.shared.homeSourceBean?.name ?? "TVBox")
                        .font(.system(size: AppTheme.fontHeadline, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: AppTheme.fontCaption, weight: .bold))
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(.leading, AppTheme.spacingXS)
                }
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.vertical, AppTheme.spacingSM)
                .background(AppTheme.backgroundElevated)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(AppTheme.borderLight, lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            HomeClockView()
        }
        .padding(.horizontal, AppTheme.spacingXL)
        .padding(.top, AppTheme.spacingLG)
        .padding(.bottom, AppTheme.spacingSM)
    }

    private var categoryTabBar: some View {
        ScrollViewReader { proxy in
            HStack(spacing: AppTheme.spacingSM) {
                categoryMoveButton(
                    systemName: "chevron.left",
                    enabled: canMoveCategory(by: -1)
                ) {
                    moveCategoryTabs(by: -3, proxy: proxy)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingMD) {
                        ForEach(viewModel.sorts) { sort in
                            SelectableChip(
                                title: sort.name,
                                isSelected: viewModel.selectedSort?.id == sort.id
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.selectSort(sort)
                                }
                                categoryScrollAnchorId = sort.id
                                scrollCategoryBar(to: sort.id, proxy: proxy)
                            }
                            .id(sort.id)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingSM)
                }
                .simultaneousGesture(categoryDragGesture(proxy: proxy))
                .onAppear {
                    syncCategoryScrollAnchorIfNeeded()
                    scrollCategoryBar(to: categoryScrollAnchorId, proxy: proxy, animated: false)
                }
                .onChange(of: viewModel.sorts.map(\.id)) { newValue in
                    syncCategoryScrollAnchorIfNeeded()
                    scrollCategoryBar(to: categoryScrollAnchorId, proxy: proxy, animated: false)
                }
                .onChange(of: viewModel.selectedSort?.id) { newId in
                    guard let newId else { return }
                    categoryScrollAnchorId = newId
                    scrollCategoryBar(to: newId, proxy: proxy)
                }

                categoryMoveButton(
                    systemName: "chevron.right",
                    enabled: canMoveCategory(by: 1)
                ) {
                    moveCategoryTabs(by: 3, proxy: proxy)
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
        }
        .padding(.vertical, AppTheme.spacingSM)
    }

    private func categoryMoveButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: AppTheme.fontFootnote, weight: .semibold))
                .foregroundColor(enabled ? AppTheme.textPrimary : AppTheme.textDisabled)
                .frame(width: 26, height: 26)
                .background(AppTheme.backgroundElevated)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func canMoveCategory(by direction: Int) -> Bool {
        guard !viewModel.sorts.isEmpty else { return false }
        let currentIndex = categoryIndex(for: categoryScrollAnchorId) ?? 0
        if direction < 0 {
            return currentIndex > 0
        }
        return currentIndex < viewModel.sorts.count - 1
    }

    private func categoryIndex(for id: String?) -> Int? {
        guard let id else { return nil }
        return viewModel.sorts.firstIndex(where: { $0.id == id })
    }

    private func syncCategoryScrollAnchorIfNeeded() {
        guard !viewModel.sorts.isEmpty else {
            categoryScrollAnchorId = nil
            return
        }

        if let selectedId = viewModel.selectedSort?.id,
           viewModel.sorts.contains(where: { $0.id == selectedId }) {
            categoryScrollAnchorId = selectedId
            return
        }

        if let anchorId = categoryScrollAnchorId,
           viewModel.sorts.contains(where: { $0.id == anchorId }) {
            return
        }

        categoryScrollAnchorId = viewModel.sorts.first?.id
    }

    private func moveCategoryTabs(by delta: Int, proxy: ScrollViewProxy) {
        guard !viewModel.sorts.isEmpty else { return }
        let currentIndex = categoryIndex(for: categoryScrollAnchorId) ?? 0
        let newIndex = min(max(0, currentIndex + delta), viewModel.sorts.count - 1)
        guard newIndex != currentIndex else { return }

        let targetId = viewModel.sorts[newIndex].id
        categoryScrollAnchorId = targetId
        scrollCategoryBar(to: targetId, proxy: proxy)
    }

    private func scrollCategoryBar(to id: String?, proxy: ScrollViewProxy, animated: Bool = true) {
        guard let id else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .center)
            }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func categoryDragGesture(proxy: ScrollViewProxy) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let delta = value.translation.width - categoryDragTranslation
                if delta <= -28 {
                    moveCategoryTabs(by: 1, proxy: proxy)
                    categoryDragTranslation = value.translation.width
                } else if delta >= 28 {
                    moveCategoryTabs(by: -1, proxy: proxy)
                    categoryDragTranslation = value.translation.width
                }
            }
            .onEnded { _ in
                categoryDragTranslation = 0
            }
    }

    private var filterBar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppTheme.spacingSM) {
                ForEach(viewModel.currentFilters, id: \.key) { filter in
                    HStack(spacing: AppTheme.spacingSM) {
                        Text(filter.name)
                            .font(.system(size: AppTheme.fontCaption, weight: .medium))
                            .foregroundColor(AppTheme.textSecondary)
                            .frame(width: 36, alignment: .leading)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppTheme.spacingSM) {
                                SelectableChip(
                                    title: "全部",
                                    isSelected: viewModel.selectedFilters[filter.key] == nil
                                ) {
                                    viewModel.selectFilter(key: filter.key, value: "")
                                }

                                ForEach(filter.values, id: \.v) { value in
                                    SelectableChip(
                                        title: value.n,
                                        isSelected: viewModel.selectedFilters[filter.key] == value.v
                                    ) {
                                        viewModel.selectFilter(key: filter.key, value: value.v)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.vertical, AppTheme.spacingXS)
        }
        .frame(maxHeight: 120)
    }

    private var contentArea: some View {
        Group {
            if viewModel.isLoading && viewModel.categoryVideos.isEmpty && viewModel.homeVideos.isEmpty {
                VStack {
                    Spacer()
                    AppLoadingView()
                    Spacer()
                }
            } else if let error = viewModel.errorMessage, viewModel.categoryVideos.isEmpty {
                VStack {
                    Spacer()
                    if let source = ApiConfig.shared.homeSourceBean, source.isIndexSite {
                        AppErrorView(message: "该线路为索引服务，请点击影视跳转搜索")
                    } else {
                        AppErrorView(message: error, onRetry: { Task { await viewModel.refresh() } })
                    }

                    if let source = ApiConfig.shared.homeSourceBean, !source.isSupportedInSwift {
                        Text("当前源类型: \(source.typeDescription)")
                            .font(.system(size: AppTheme.fontCaption))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    Spacer()
                }
            } else {
                let videos = viewModel.categoryVideos

                ScrollView {
                    LazyVGrid(columns: columns, spacing: AppTheme.cardSpacing) {
                        ForEach(videos) { video in
                            Group {
                                if let source = ApiConfig.shared.homeSourceBean, source.isIndexSite {
                                    Button {
                                        navigateToSearch(with: video.name)
                                    } label: {
                                        VodCardView(video: video)
                                    }
                                    .buttonStyle(.plain)
                                } else if let source = ApiConfig.shared.homeSourceBean, source.isConfigCenter {
                                    Button {
                                        openConfigCenterUrl(from: video)
                                    } label: {
                                        VodCardView(video: video)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink(value: video) {
                                        VodCardView(video: video)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(currentItem: video) }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXL)
                    .padding(.vertical, AppTheme.spacingMD)

                    if viewModel.hasMore {
                        ProgressView()
                            .padding()
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationDestination(for: Movie.Video.self) { video in
            DetailView(video: video)
        }
    }

    private func navigateToSearch(with keyword: String) {
        appState.pendingSearchKeyword = keyword
    }

    private func openConfigCenterUrl(from video: Movie.Video) {
        var openUrl: String?
        if video.pic.hasPrefix("http") {
            openUrl = video.pic
            if let proxyMatch = video.pic.range(of: "/proxy/([A-Za-z0-9+/=]+)", options: .regularExpression) {
                let proxySubstring = String(video.pic[proxyMatch])
                if let base64Range = proxySubstring.range(of: "/proxy/") {
                    let encoded = String(proxySubstring[base64Range.upperBound...])
                    if let decoded = Data(base64Encoded: encoded),
                       let decodedStr = String(data: decoded, encoding: .utf8),
                       decodedStr.hasPrefix("http") {
                        openUrl = decodedStr
                    }
                }
            }
        }

        if let urlString = openUrl, let url = URL(string: urlString) {
            safariUrl = url
        }
    }
}

private struct HomeClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(timeline.date.homeDateString)
                .font(.system(size: AppTheme.fontFootnote, weight: .medium, design: .monospaced))
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.vertical, AppTheme.spacingMD)
                .glassCard(cornerRadius: AppTheme.radiusMD)
        }
    }
}
