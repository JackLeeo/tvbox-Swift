import SwiftUI

/// 首页 - 对应 Android 版 HomeActivity + UserFragment
struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var appState: AppState
    @State private var categoryScrollAnchorId: String?
    @State private var categoryDragTranslation: CGFloat = 0
    
    // 网格布局
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
            VStack(spacing: 0) {
                // 顶部栏
                headerBar
                
                // 分类标签栏
                if !viewModel.sorts.isEmpty {
                    categoryTabBar
                }
                
                // 内容区
                contentArea
            }
            .background(AppTheme.primaryGradient)
        }
        .task {
            await viewModel.loadSorts()
            if let first = viewModel.sorts.first {
                viewModel.selectSort(first)
            }
        }
    }
    
    // MARK: - 顶部栏
    
    private var headerBar: some View {
        HStack(spacing: 15) {
            // 应用名（可切换源）- 已移除过滤，显示所有源
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
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.orange)
                    Text(ApiConfig.shared.homeSourceBean?.name ?? "TVBox")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.leading, 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            Spacer()
            
            // 日期时间
            HomeClockView()
        }
        .padding(.horizontal, 20)
        .padding(.top, 15)
        .padding(.bottom, 10)
    }
    
    // MARK: - 分类标签栏
    
    private var categoryTabBar: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 8) {
                categoryMoveButton(
                    systemName: "chevron.left",
                    enabled: canMoveCategory(by: -1)
                ) {
                    moveCategoryTabs(by: -3, proxy: proxy)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.sorts) { sort in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.selectSort(sort)
                                }
                                categoryScrollAnchorId = sort.id
                                scrollCategoryBar(to: sort.id, proxy: proxy)
                            } label: {
                                Text(sort.name)
                                    .font(.system(size: 14, weight: viewModel.selectedSort?.id == sort.id ? .bold : .medium))
                                    .foregroundColor(viewModel.selectedSort?.id == sort.id ? .orange : .white.opacity(0.8))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(
                                        ZStack {
                                            if viewModel.selectedSort?.id == sort.id {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.orange.opacity(0.15))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                                                    )
                                            } else {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.white.opacity(0.05))
                                            }
                                        }
                                    )
                            }
                            .buttonStyle(.plain)
                            .id(sort.id)
                        }
                    }
                    .padding(.horizontal, 8)
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
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 8)
    }
    
    private func categoryMoveButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(enabled ? 0.9 : 0.35))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.08))
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
    
    // MARK: - 内容区
    
    private var contentArea: some View {
        Group {
            if viewModel.isLoading && viewModel.categoryVideos.isEmpty && viewModel.homeVideos.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.orange)
                    Text("加载中...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 12)
                    Spacer()
                }
            } else if let error = viewModel.errorMessage, viewModel.categoryVideos.isEmpty && viewModel.homeVideos.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button("重试") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    Spacer()
                }
            } else {
                let videos = viewModel.selectedSort?.id == "home"
                    ? viewModel.homeVideos
                    : viewModel.categoryVideos
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(videos) { video in
                            NavigationLink(value: video) {
                                VodCardView(video: video)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                Task { await viewModel.loadMoreIfNeeded(currentItem: video) }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    
                    // 加载更多
                    if viewModel.selectedSort?.id != "home" && viewModel.hasMore {
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
}

private struct HomeClockView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            Text(timeline.date.homeDateString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: 12)
        }
    }
}
