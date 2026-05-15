import SwiftUI

struct SearchView: View {
    @StateObject var viewModel: SearchViewModel

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
                searchBar

                if viewModel.activeSites.isEmpty && !viewModel.isSearching {
                    searchHistorySection
                } else {
                    HStack(spacing: 0) {
                        siteListPanel
                        Divider()
                        resultsPanel
                    }
                }
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.1))
            .navigationTitle("搜索")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))

                TextField("搜索影片...", text: $viewModel.keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
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
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(LinearGradient(colors: [.orange.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )

            Button {
                Task { await viewModel.search() }
            } label: {
                Text("搜索")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private var siteListPanel: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(viewModel.activeSites) { site in
                    siteRow(site)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 180)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
    }

    private func siteRow(_ site: SourceBean) -> some View {
        let isSelected = viewModel.selectedSiteKey == site.key
        let isSearching = viewModel.searchingStatus[site.key] ?? false
        let count = viewModel.resultCount[site.key] ?? 0

        return Button {
            viewModel.selectSite(site.key)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(site.name)
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.gray)
                            Text("搜索中...")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        } else {
                            Text("\(count) 条结果")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.orange.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var resultsPanel: some View {
        Group {
            if viewModel.selectedSiteKey == nil {
                emptyState(icon: "magnifyingglass", text: "请输入搜索关键词")
            } else if viewModel.isCurrentSiteSearching && viewModel.currentResults.isEmpty {
                Spacer()
                ProgressView("搜索中...")
                    .tint(.orange)
                Spacer()
            } else if viewModel.currentResults.isEmpty {
                emptyState(icon: "magnifyingglass", text: "暂无搜索结果")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.currentResults) { video in
                            NavigationLink(value: video) {
                                VodCardView(video: video)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .navigationDestination(for: Movie.Video.self) { video in
                    DetailView(video: video)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.searchHistory.isEmpty {
                HStack {
                    Text("搜索历史")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        viewModel.clearHistory()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("清空")
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if #available(iOS 16.0, *) {
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.searchHistory, id: \.self) { keyword in
                            Button {
                                viewModel.keyword = keyword
                                Task { await viewModel.search() }
                            } label: {
                                Text(keyword)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                        ForEach(viewModel.searchHistory, id: \.self) { keyword in
                            Button {
                                viewModel.keyword = keyword
                                Task { await viewModel.search() }
                            } label: {
                                Text(keyword)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            Spacer()
        }
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

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
