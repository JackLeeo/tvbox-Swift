import Foundation
import SwiftUI
import Combine

/// 首页 ViewModel
@MainActor
class HomeViewModel: ObservableObject {
    /// 分类列表（包含手动注入的"推荐"分类）。
    @Published var sorts: [MovieSort.SortData] = []
    /// 当前选中的分类。
    @Published var selectedSort: MovieSort.SortData?
    /// 首页推荐内容（对应"推荐"分类）。
    @Published var homeVideos: [Movie.Video] = []
    /// 普通分类的视频列表（分页加载）。
    @Published var categoryVideos: [Movie.Video] = []
    /// 页面加载状态（分类加载与分页共用）。
    @Published var isLoading = false
    /// 当前分类的分页页码。
    @Published var currentPage = 1
    /// 是否还有下一页。
    @Published var hasMore = true
    /// 错误提示文案。
    @Published var errorMessage: String?
    @Published var selectedFilters: [String: String] = [:]
    
    var currentFilters: [MovieSort.SortFilter] {
        guard let sortId = selectedSort?.id else { return [] }
        return sorts.first(where: { $0.id == sortId })?.filters ?? []
    }
    
    /// 源数据访问服务。
    private let sourceService = SourceService.shared
    /// 标记上次加载是否因网络错误失败（用于网络恢复自动重试）。
    private var lastLoadFailedDueToNetwork = false
    private var networkRestoredCancellable: AnyCancellable?
    
    init() {
        setupNetworkRestoredAutoRetry()
    }
    
    /// 加载分类列表
    func loadSorts() async {
        guard let source = ApiConfig.shared.homeSourceBean else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await sourceService.getSort(sourceBean: source)
            
            self.sorts = result.sorts
            self.homeVideos = result.homeVideos
            lastLoadFailedDueToNetwork = false
            
            if selectedSort == nil {
                selectedSort = allSorts.first
            }
        } catch {
            errorMessage = error.localizedDescription
            lastLoadFailedDueToNetwork = error.isNetworkConnectionError
        }
        
        isLoading = false
    }
    
    /// 网络恢复时，若上次因网络错误导致首页为空，自动重新加载。
    private func setupNetworkRestoredAutoRetry() {
        networkRestoredCancellable = NetworkMonitor.shared.networkRestoredPublisher
            .sink { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.lastLoadFailedDueToNetwork || (self.sorts.isEmpty && self.homeVideos.isEmpty) else { return }
                    await self.refresh()
                }
            }
    }
    
    /// 选择分类
    func selectSort(_ sort: MovieSort.SortData) {
        selectedSort = sort
        errorMessage = nil
        categoryVideos = []
        currentPage = 1
        hasMore = true
        selectedFilters = [:]
        
        Task {
            await loadCategoryVideos(page: 1, sort: sort)
        }
    }
    
    /// 加载分类视频列表
    private func loadCategoryVideos(page: Int, sort: MovieSort.SortData) async {
        guard let source = ApiConfig.shared.homeSourceBean else { return }
        guard !isLoading else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let filters = selectedFilters.isEmpty ? nil : selectedFilters
            let videos = try await sourceService.getList(sourceBean: source, sortData: sort, page: page, filters: filters)
            
            // 分类切换过程中，丢弃旧请求结果
            guard selectedSort?.id == sort.id else { return }
            
            if page == 1 {
                categoryVideos = videos
            } else {
                categoryVideos.append(contentsOf: videos)
            }
            // 以"返回非空"作为是否继续分页的轻量判断。
            currentPage = page
            hasMore = !videos.isEmpty
        } catch {
            guard selectedSort?.id == sort.id else { return }
            errorMessage = error.localizedDescription
        }
    }
    
    /// 加载下一页
    func loadMore() async {
        guard let lastItem = categoryVideos.last else { return }
        await loadMoreIfNeeded(currentItem: lastItem)
    }
    
    /// 当最后一个元素出现时触发加载下一页
    func loadMoreIfNeeded(currentItem: Movie.Video) async {
        guard hasMore, !isLoading else { return }
        guard categoryVideos.last?.id == currentItem.id else { return }
        guard let sort = selectedSort else { return }
        
        let nextPage = currentPage + 1
        await loadCategoryVideos(page: nextPage, sort: sort)
    }
    
    func selectFilter(key: String, value: String) {
        if value.isEmpty {
            selectedFilters.removeValue(forKey: key)
        } else {
            selectedFilters[key] = value
        }
        
        categoryVideos = []
        currentPage = 1
        hasMore = true
        
        if let sort = selectedSort {
            Task {
                await loadCategoryVideos(page: 1, sort: sort)
            }
        }
    }
    
    func refresh() async {
        currentPage = 1
        hasMore = true
        categoryVideos = []
        errorMessage = nil
        await loadSorts()
        
        guard let sort = selectedSort else { return }
        
        if let matchedSort = sorts.first(where: { $0.id == sort.id }) {
            selectedSort = matchedSort
            await loadCategoryVideos(page: 1, sort: matchedSort)
        } else if let firstCategory = sorts.first {
            selectedSort = firstCategory
            await loadCategoryVideos(page: 1, sort: firstCategory)
        }
    }
}
