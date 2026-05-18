import SwiftUI

struct SettingsView: View {
    enum ApiInputType {
        case vod
        case live

        var title: String {
            switch self {
            case .vod: return "点播接口地址"
            case .live: return "直播接口地址"
            }
        }

        var placeholder: String {
            switch self {
            case .vod: return "请输入点播接口地址"
            case .live: return "请输入直播接口地址（可留空跟随点播）"
            }
        }
    }

    @StateObject private var viewModel = SettingsViewModel()
    @StateObject private var apiConfig = ApiConfig.shared
    @EnvironmentObject var appState: AppState
    @State private var showApiInput = false
    @State private var editingApiType: ApiInputType = .vod
    @State private var showAbout = false
    @State private var sourceSearchText = ""
    @State private var showingPicker: PickerType = .none
    @State private var showHistorySheet = false
    @State private var showFavoritesSheet = false

    enum PickerType {
        case none
        case vodPlayer
        case livePlayer
        case decode
        case vlcBuffer
        case playTimeStep
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacingXXL) {
                    VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                        AppSectionHeader(title: "数据源")
                        AppCard(cornerRadius: AppTheme.radiusLG) {
                            VStack(spacing: 0) {
                                SettingsRow(
                                    icon: "film",
                                    title: "点播接口地址",
                                    value: viewModel.vodApiUrl.isEmpty ? "未配置" : viewModel.vodApiUrl
                                ) {
                                    editingApiType = .vod
                                    showApiInput = true
                                }
                                Divider().background(AppTheme.borderLight)
                                SettingsRow(
                                    icon: "tv",
                                    title: "直播接口地址",
                                    value: viewModel.liveApiUrl.isEmpty ? "跟随点播接口" : viewModel.liveApiUrl
                                ) {
                                    editingApiType = .live
                                    showApiInput = true
                                }
                                Divider().background(AppTheme.borderLight)
                                if !apiConfig.sourceBeanList.isEmpty {
                                    NavigationLink {
                                        sourcePickerView
                                    } label: {
                                        SettingsRow(icon: "server.rack", title: "主页数据源", value: apiConfig.homeSourceBean?.name ?? "", action: nil)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                        AppSectionHeader(title: "播放设置")
                        AppCard(cornerRadius: AppTheme.radiusLG) {
                            VStack(spacing: 0) {
                                SettingsRow(icon: "play.rectangle", title: "点播播放器", value: viewModel.vodPlayerEngine.title) {
                                    if viewModel.playerEngineOptions.count > 1 {
                                        showingPicker = .vodPlayer
                                    }
                                }
                                Divider().background(AppTheme.borderLight)
                                SettingsRow(icon: "dot.radiowaves.left.and.right", title: "直播播放器", value: viewModel.livePlayerEngine.title) {
                                    if viewModel.playerEngineOptions.count > 1 {
                                        showingPicker = .livePlayer
                                    }
                                }
                                Divider().background(AppTheme.borderLight)
                                SettingsRow(icon: "cpu", title: "视频解码", value: viewModel.decodeMode.title) {
                                    showingPicker = .decode
                                }
                                if PlayerEngine.isVLCAvailable {
                                    Divider().background(AppTheme.borderLight)
                                    SettingsRow(icon: "externaldrive.badge.wifi", title: "VLC缓冲", value: viewModel.vlcBufferMode.title) {
                                        showingPicker = .vlcBuffer
                                    }
                                }
                                Divider().background(AppTheme.borderLight)
                                SettingsRow(icon: "forward", title: "快进步长", value: "\(viewModel.playTimeStep)秒") {
                                    showingPicker = .playTimeStep
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                        AppSectionHeader(title: "功能")
                        AppCard(cornerRadius: AppTheme.radiusLG) {
                            VStack(spacing: 0) {
                                Button {
                                    showHistorySheet = true
                                } label: {
                                    SettingsRow(icon: "clock", title: "播放历史", value: "", action: nil)
                                }
                                Divider().background(AppTheme.borderLight)
                                Button {
                                    showFavoritesSheet = true
                                } label: {
                                    SettingsRow(icon: "heart", title: "我的收藏", value: "", action: nil)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                        AppSectionHeader(title: "缓存")
                        AppCard(cornerRadius: AppTheme.radiusLG) {
                            VStack(spacing: 0) {
                                SettingsRow(icon: "trash", title: "清除缓存", value: viewModel.cacheSizeString) {
                                    viewModel.clearCache()
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                        AppSectionHeader(title: "关于")
                        AppCard(cornerRadius: AppTheme.radiusLG) {
                            VStack(spacing: 0) {
                                SettingsRow(icon: "info.circle", title: "版本", value: "1.0.0", action: nil)
                                Divider().background(AppTheme.borderLight)
                                SettingsRow(icon: "globe", title: "站点数量", value: "\(apiConfig.sourceBeanList.count)", action: nil)
                                Divider().background(AppTheme.borderLight)
                                SettingsRow(icon: "wand.and.stars", title: "解析数量", value: "\(apiConfig.parseBeanList.count)", action: nil)
                                Divider().background(AppTheme.borderLight)
                                SettingsRow(icon: "tv", title: "直播分组", value: "\(apiConfig.liveChannelGroupList.count)", action: nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.spacingXL)
                .padding(.vertical, AppTheme.spacingXXL)
            }
            .background(AppBackground())
            .navigationTitle("设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showApiInput) {
                apiInputSheet
            }
            .sheet(isPresented: $showHistorySheet) {
                HistoryView()
            }
            .sheet(isPresented: $showFavoritesSheet) {
                FavoritesView()
            }
        }
        .overlay(pickerOverlay)
    }

    @ViewBuilder
    private var pickerOverlay: some View {
        switch showingPicker {
        case .vodPlayer:
            SelectionModal(
                title: "选择点播播放器",
                icon: "play.rectangle.fill",
                items: viewModel.playerEngineOptions,
                selectedItem: viewModel.vodPlayerEngine,
                itemTitle: { $0.title },
                onSelect: { engine in
                    viewModel.setVodPlayerEngine(engine)
                    showingPicker = .none
                },
                onCancel: { showingPicker = .none }
            )
        case .livePlayer:
            SelectionModal(
                title: "选择直播播放器",
                icon: "dot.radiowaves.left.and.right",
                items: viewModel.playerEngineOptions,
                selectedItem: viewModel.livePlayerEngine,
                itemTitle: { $0.title },
                onSelect: { engine in
                    viewModel.setLivePlayerEngine(engine)
                    showingPicker = .none
                },
                onCancel: { showingPicker = .none }
            )
        case .decode:
            SelectionModal(
                title: "视频解码模式",
                icon: "cpu.fill",
                items: viewModel.decodeModeOptions,
                selectedItem: viewModel.decodeMode,
                itemTitle: { $0.title },
                onSelect: { mode in
                    viewModel.setDecodeMode(mode)
                    showingPicker = .none
                },
                onCancel: { showingPicker = .none }
            )
        case .vlcBuffer:
            SelectionModal(
                title: "VLC 缓冲策略",
                icon: "externaldrive.fill",
                items: viewModel.vlcBufferModeOptions,
                selectedItem: viewModel.vlcBufferMode,
                itemTitle: { $0.title },
                onSelect: { mode in
                    viewModel.setVLCBufferMode(mode)
                    showingPicker = .none
                },
                onCancel: { showingPicker = .none }
            )
        case .playTimeStep:
            SelectionModal(
                title: "快进步长",
                icon: "forward.fill",
                items: viewModel.playTimeStepOptions,
                selectedItem: viewModel.playTimeStep,
                itemTitle: { "\($0) 秒" },
                onSelect: { step in
                    viewModel.setPlayTimeStep(step)
                    showingPicker = .none
                },
                onCancel: { showingPicker = .none }
            )
        case .none:
            EmptyView()
        }
    }

    private var apiInputSheet: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacingLG) {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(AppTheme.textSecondary)
                    TextField(editingApiType.placeholder, text: currentApiBinding)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        #endif
                }
                .padding(AppTheme.spacingMD)
                .background(AppTheme.backgroundElevated)
                .cornerRadius(AppTheme.radiusMD)

                HStack {
                    Button {
                        if let text = readPasteboardText() {
                            currentApiBinding.wrappedValue = text
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                            .font(.system(size: AppTheme.fontSubhead))
                    }

                    Spacer()
                }

                if !viewModel.apiHistory.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                        Text("历史记录")
                            .font(.system(size: AppTheme.fontCaption))
                            .foregroundColor(AppTheme.textSecondary)

                        ForEach(viewModel.apiHistory, id: \.self) { url in
                            HStack {
                                Button {
                                    currentApiBinding.wrappedValue = url
                                } label: {
                                    HStack(spacing: AppTheme.spacingSM) {
                                        Image(systemName: "clock")
                                            .font(.system(size: AppTheme.fontCaption))
                                        Text(url)
                                            .font(.system(size: AppTheme.fontCaption))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(AppTheme.textSecondary)
                                }

                                Spacer()

                                Button {
                                    viewModel.removeApiHistory(url)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: AppTheme.fontCaption))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                            }
                        }
                    }
                }

                if let error = viewModel.configError {
                    Text(error)
                        .font(.system(size: AppTheme.fontCaption))
                        .foregroundColor(AppTheme.accentColor)
                }

                Spacer()
            }
            .padding(AppTheme.spacingLG)
            .navigationTitle(editingApiType.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showApiInput = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.loadConfig()
                            if viewModel.configSuccess {
                                appState.applyLoadedConfigState()
                                showApiInput = false
                            }
                        }
                    } label: {
                        if viewModel.isLoadingConfig {
                            ProgressView()
                        } else {
                            Text("确认")
                        }
                    }
                    .disabled(
                        viewModel.isLoadingConfig
                        || viewModel.vodApiUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .overlay(multiRepoSelectionOverlay)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
    }

    @ViewBuilder
    private var multiRepoSelectionOverlay: some View {
        if let pending = viewModel.pendingMultiRepoSelection {
            SelectionModal(
                title: "选择\(pending.target.title)仓库",
                icon: "list.bullet.rectangle.portrait.fill",
                items: pending.options,
                selectedItem: nil,
                itemTitle: { $0.name },
                onSelect: { option in
                    Task {
                        await viewModel.selectPendingMultiRepoOption(option)
                        if viewModel.configSuccess {
                            appState.applyLoadedConfigState()
                            showApiInput = false
                        }
                    }
                },
                onCancel: {
                    viewModel.cancelPendingMultiRepoSelection()
                }
            )
        }
    }

    private var currentApiBinding: Binding<String> {
        switch editingApiType {
        case .vod:
            return $viewModel.vodApiUrl
        case .live:
            return $viewModel.liveApiUrl
        }
    }

    private func readPasteboardText() -> String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }

    private var filteredSources: [SourceBean] {
        let sources = apiConfig.sourceBeanList
        if sourceSearchText.isEmpty {
            return sources
        } else {
            return sources.filter { $0.name.localizedCaseInsensitiveContains(sourceSearchText) || $0.api.localizedCaseInsensitiveContains(sourceSearchText) }
        }
    }

    private var sourcePickerView: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.textSecondary)
                TextField("搜索数据源", text: $sourceSearchText)
                    .textFieldStyle(.plain)
                if !sourceSearchText.isEmpty {
                    Button(action: { sourceSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.spacingMD)
            .background(AppTheme.backgroundElevated)
            .cornerRadius(AppTheme.radiusMD)
            .padding(.horizontal, AppTheme.spacingXL)
            .padding(.vertical, AppTheme.spacingMD)

            ScrollView {
                LazyVStack(spacing: AppTheme.spacingMD) {
                    ForEach(filteredSources) { source in
                        Button {
                            apiConfig.setHomeSource(source)
                            appState.currentSourceKey = source.key
                        } label: {
                            HStack(alignment: .center, spacing: AppTheme.spacingLG) {
                                VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                                    HStack(spacing: AppTheme.spacingSM) {
                                        Text(source.name)
                                            .font(.system(size: AppTheme.fontHeadline, weight: .semibold))
                                            .foregroundColor(AppTheme.textPrimary)

                                        Text(source.typeDescription)
                                            .font(.system(size: AppTheme.fontCaption, weight: .bold))
                                            .foregroundColor(AppTheme.accentColor)
                                            .padding(.horizontal, AppTheme.spacingSM)
                                            .padding(.vertical, AppTheme.spacingXS)
                                            .background(
                                                Capsule().fill(AppTheme.backgroundTertiary)
                                            )
                                    }

                                    Text(source.api)
                                        .font(.system(size: AppTheme.fontFootnote))
                                        .foregroundColor(AppTheme.textTertiary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                HStack(spacing: AppTheme.spacingMD) {
                                    if source.isSearchable {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: AppTheme.fontBody, weight: .medium))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }

                                    if source.key == apiConfig.homeSourceBean?.key {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: AppTheme.fontTitle2))
                                            .foregroundColor(AppTheme.accentColor)
                                    } else {
                                        Circle()
                                            .strokeBorder(AppTheme.borderMedium, lineWidth: 1)
                                            .frame(width: AppTheme.spacingXL, height: AppTheme.spacingXL)
                                    }
                                }
                            }
                            .padding(AppTheme.spacingLG)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.radiusLG)
                                    .fill(AppTheme.backgroundElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusLG)
                                    .stroke(
                                        source.key == apiConfig.homeSourceBean?.key ? AppTheme.borderActive : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.spacingXL)
                .padding(.bottom, AppTheme.spacingXXL)
            }
        }
        .background(AppBackground())
        .navigationTitle("选择数据源")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let value: String
    let action: (() -> Void)?

    var body: some View {
        Group {
            if let action = action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: AppTheme.spacingLG) {
            Image(systemName: icon)
                .font(.system(size: AppTheme.fontHeadline))
                .foregroundColor(AppTheme.accentColor)
                .frame(width: AppTheme.spacingLG + AppTheme.spacingSM)

            Text(title)
                .font(.system(size: AppTheme.fontBody))
                .foregroundColor(AppTheme.textPrimary)

            Spacer()

            Text(value)
                .font(.system(size: AppTheme.fontSubhead))
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(1)

            Image(systemName: "chevron.right")
                .font(.system(size: AppTheme.fontFootnote, weight: .bold))
                .foregroundColor(AppTheme.textDisabled)
        }
        .padding(.horizontal, AppTheme.spacingSM)
        .padding(.vertical, AppTheme.spacingSM)
        .contentShape(Rectangle())
    }
}
