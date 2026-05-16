import Foundation
import SwiftUI

@MainActor
class SearchViewModel: ObservableObject {
    @Published var keyword: String = ""
    @Published var searchHistory: [String] = []
    @Published var resultsBySite: [String: [Movie.Video]] = [:]
    @Published var searchingStatus: [String: Bool] = [:]
    @Published var resultCount: [String: Int] = [:]
    @Published var activeSites: [SourceBean] = []
    @Published var selectedSiteKey: String?
    @Published var isSearching: Bool = false

    private let sourceService = SourceService.shared
    private var latestSearchRequestId: UUID = UUID()

    init() {
        loadSearchHistory()
    }

    var currentResults: [Movie.Video] {
        guard let key = selectedSiteKey else { return [] }
        return resultsBySite[key] ?? []
    }

    var isCurrentSiteSearching: Bool {
        guard let key = selectedSiteKey else { return false }
        return searchingStatus[key] ?? false
    }

    func search() async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let requestId = UUID()
        latestSearchRequestId = requestId

        addToHistory(trimmed)

        let sources = ApiConfig.shared.getSearchableSources()
        let validSources = sources.filter { $0.isSupportedInSwift && $0.key != "douban" && $0.key != "baseset" }

        isSearching = true
        resultsBySite.removeAll()
        searchingStatus.removeAll()
        resultCount.removeAll()
        activeSites = validSources

        if selectedSiteKey == nil || !validSources.contains(where: { $0.key == selectedSiteKey }) {
            selectedSiteKey = validSources.first?.key
        }

        for source in validSources {
            searchingStatus[source.key] = true
            resultCount[source.key] = 0
        }

        await withTaskGroup(of: (String, [Movie.Video]).self) { group in
            for source in validSources {
                group.addTask { [sourceService] in
                    do {
                        let videos = try await sourceService.search(sourceBean: source, keyword: trimmed)
                        return (source.key, videos)
                    } catch {
                        return (source.key, [])
                    }
                }
            }

            for await (siteKey, videos) in group {
                guard requestId == self.latestSearchRequestId else { return }
                self.resultsBySite[siteKey] = videos
                self.resultCount[siteKey] = videos.count
                self.searchingStatus[siteKey] = false
            }
        }

        guard requestId == latestSearchRequestId else { return }
        isSearching = false
    }

    func searchInSource(_ source: SourceBean) async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        searchingStatus[source.key] = true
        resultCount[source.key] = 0
        if !activeSites.contains(where: { $0.key == source.key }) {
            activeSites.append(source)
        }
        selectedSiteKey = source.key

        do {
            let videos = try await sourceService.search(sourceBean: source, keyword: trimmed)
            resultsBySite[source.key] = videos
            resultCount[source.key] = videos.count
        } catch {
            resultsBySite[source.key] = []
            resultCount[source.key] = 0
        }
        searchingStatus[source.key] = false
    }

    func selectSite(_ key: String) {
        selectedSiteKey = key
    }

    private func loadSearchHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: HawkConfig.SEARCH_HISTORY) ?? []
    }

    private func addToHistory(_ keyword: String) {
        searchHistory.removeAll { $0 == keyword }
        searchHistory.insert(keyword, at: 0)
        if searchHistory.count > 20 {
            searchHistory = Array(searchHistory.prefix(20))
        }
        UserDefaults.standard.set(searchHistory, forKey: HawkConfig.SEARCH_HISTORY)
    }

    func clearHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: HawkConfig.SEARCH_HISTORY)
    }
}
