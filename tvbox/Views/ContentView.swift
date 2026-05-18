import SwiftUI

struct ContentView: View {
    private enum ApiInputTarget {
        case vod
        case live
    }
    
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @StateObject private var settingsVM = SettingsViewModel()
    @State private var selectedTab = 0
    @State private var showSetup = false
    @State private var setupInputTarget: ApiInputTarget = .vod
    @StateObject private var searchVM = SearchViewModel()
    @State private var hasSavedConfig = false

    var body: some View {
        Group {
            if appState.isConfigLoaded {
                mainTabView
            } else if hasSavedConfig && appState.loadingPhase != .idle {
                loadingView
            } else {
                setupView
            }
        }
        .overlay(multiRepoSelectionOverlay)
        .overlay(alignment: .top) {
            networkStatusBanner
        }
        .preferredColorScheme(.dark)
        .onChange(of: appState.pendingSearchKeyword) { keyword in
            if let keyword, !keyword.isEmpty {
                searchVM.keyword = keyword
                selectedTab = 2
                Task { await searchVM.search() }
                appState.pendingSearchKeyword = nil
            }
        }
        .onAppear {
            let defaults = UserDefaults.standard
            let savedVodUrl = defaults.string(forKey: HawkConfig.API_URL) ?? ""
            let savedLiveUrl = defaults.string(forKey: HawkConfig.LIVE_API_URL) ?? ""
            if !savedVodUrl.isEmpty {
                hasSavedConfig = true
                Task {
                    await appState.loadConfig(vodUrl: savedVodUrl, liveUrl: savedLiveUrl)
                }
            }
        }
    }

    private var loadingView: some View {
        ZStack {
            AppTheme.primaryGradient
                .ignoresSafeArea()

            VStack {
                HStack {
                    Circle()
                        .fill(AppTheme.accentColor.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 80)
                        .offset(x: -100, y: -100)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 80)
                        .offset(x: 100, y: 100)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: AppTheme.spacingXXL + AppTheme.spacingSM) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accentGradient)
                        .frame(width: 100, height: 100)
                        .blur(radius: 20)
                        .opacity(0.5)

                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(AppTheme.accentGradient)
                        .shadow(color: .red.opacity(0.3), radius: 15, x: 0, y: 10)
                }

                Text("TVBox")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .tracking(2)

                if appState.loadingPhase.isLoading {
                    AppLoadingView(message: appState.loadingPhase.displayText)
                        .padding(.top, AppTheme.spacingSM)
                } else if case .failed = appState.loadingPhase {
                    AppErrorView(
                        message: appState.loadingPhase.displayText,
                        onRetry: { hasSavedConfig = false }
                    )
                    .padding(.top, AppTheme.spacingSM)
                }
            }
        }
    }

    @ViewBuilder
    private var multiRepoSelectionOverlay: some View {
        if let pending = settingsVM.pendingMultiRepoSelection {
            SelectionModal(
                title: "选择\(pending.target.title)仓库",
                icon: "list.bullet.rectangle.portrait.fill",
                items: pending.options,
                selectedItem: nil,
                itemTitle: { $0.name },
                onSelect: { option in
                    Task {
                        await settingsVM.selectPendingMultiRepoOption(option)
                        if settingsVM.configSuccess {
                            appState.applyLoadedConfigState()
                        }
                    }
                },
                onCancel: {
                    settingsVM.cancelPendingMultiRepoSelection()
                }
            )
        }
    }
    
    private var mainTabView: some View {
        #if os(iOS)
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(0)
            
            LiveView()
                .tabItem {
                    Label("直播", systemImage: "tv.fill")
                }
                .tag(1)
            
            SearchView(viewModel: searchVM)
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(2)
            
            FavoritesView()
                .tabItem {
                    Label("收藏", systemImage: "heart.fill")
                }
                .tag(3)
            
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(AppTheme.accentColor)
        #else
        NavigationSplitView(columnVisibility: $appState.splitViewVisibility) {
            List(selection: $selectedTab) {
                Label("首页", systemImage: "house.fill")
                    .tag(0)
                Label("直播", systemImage: "tv.fill")
                    .tag(1)
                Label("搜索", systemImage: "magnifyingglass")
                    .tag(2)
                Label("收藏", systemImage: "heart.fill")
                    .tag(3)
                Label("历史", systemImage: "clock.fill")
                    .tag(5)
                Label("设置", systemImage: "gearshape.fill")
                    .tag(4)
            }
            .navigationTitle("TVBox")
            .listStyle(.sidebar)
        } detail: {
            switch selectedTab {
            case 0: HomeView()
            case 1: LiveView()
            case 2: SearchView(viewModel: searchVM)
            case 3: FavoritesView()
            case 4: SettingsView()
            case 5: HistoryView()
            default: HomeView()
            }
        }
        #endif
    }
    
    private var setupView: some View {
        ZStack {
            AppTheme.primaryGradient
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Circle()
                        .fill(AppTheme.accentColor.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 80)
                        .offset(x: -100, y: -100)
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 300, height: 300)
                        .blur(radius: 80)
                        .offset(x: 100, y: 100)
                }
            }
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: AppTheme.spacingXXL + AppTheme.spacingSM) {
                    VStack(spacing: AppTheme.spacingXL) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.accentGradient)
                                .frame(width: 100, height: 100)
                                .blur(radius: 20)
                                .opacity(0.5)
                            
                            Image(systemName: "play.tv.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(AppTheme.accentGradient)
                                .shadow(color: .red.opacity(0.3), radius: 15, x: 0, y: 10)
                        }
                        
                        VStack(spacing: AppTheme.spacingSM) {
                            Text("TVBox")
                                .font(.system(size: 48, weight: .heavy, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)
                                .tracking(2)
                            
                            Text("极致视听 · 简洁至上")
                                .font(.system(size: AppTheme.fontSubhead))
                                .foregroundColor(AppTheme.textSecondary)
                                .tracking(4)
                        }
                    }
                    .padding(.top, 60)
                    
                    VStack(spacing: AppTheme.spacingXXL) {
                        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                            Text("接口配置")
                                .font(.system(size: AppTheme.fontHeadline))
                                .foregroundColor(AppTheme.textPrimary)
                                .padding(.leading, AppTheme.spacingXS)
                            
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(AppTheme.accentColor)
                                TextField("请输入点播接口地址 (URL)", text: $settingsVM.vodApiUrl)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .onTapGesture {
                                        setupInputTarget = .vod
                                    }
                                    #if os(iOS)
                                    .autocapitalization(.none)
                                    .keyboardType(.URL)
                                    #endif
                                
                                Button {
                                    if let text = readPasteboardText() {
                                        settingsVM.vodApiUrl = text
                                    }
                                } label: {
                                    Image(systemName: "doc.on.clipboard")
                                        .foregroundColor(AppTheme.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .glassCard(cornerRadius: 15)
                            
                            HStack {
                                Image(systemName: "tv")
                                    .foregroundColor(AppTheme.accentColor)
                                TextField("请输入直播接口地址 (URL，可留空跟随点播)", text: $settingsVM.liveApiUrl)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(AppTheme.textPrimary)
                                    .onTapGesture {
                                        setupInputTarget = .live
                                    }
                                    #if os(iOS)
                                    .autocapitalization(.none)
                                    .keyboardType(.URL)
                                    #endif
                                
                                Button {
                                    if let text = readPasteboardText() {
                                        settingsVM.liveApiUrl = text
                                    }
                                } label: {
                                    Image(systemName: "doc.on.clipboard")
                                        .foregroundColor(AppTheme.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .glassCard(cornerRadius: 15)
                        }
                        
                        Button {
                            Task {
                                await settingsVM.loadConfig()
                                if settingsVM.configSuccess {
                                    appState.applyLoadedConfigState()
                                }
                            }
                        } label: {
                            HStack {
                                if settingsVM.isLoadingConfig {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, AppTheme.spacingSM)
                                }
                                Text(settingsVM.isLoadingConfig ? "正在解析配置..." : "开启影音之旅")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppTheme.spacingLG)
                            .background(AppTheme.accentGradient)
                            .foregroundColor(AppTheme.textPrimary)
                            .clipShape(Capsule())
                            .shadow(color: .red.opacity(0.4), radius: AppTheme.spacingMD, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            settingsVM.isLoadingConfig
                            || settingsVM.vodApiUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        
                        if !settingsVM.apiHistory.isEmpty {
                            VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                                Text("最近使用")
                                    .font(.system(size: AppTheme.fontCaption))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .padding(.horizontal, AppTheme.spacingXS)
                                
                                ForEach(settingsVM.apiHistory.prefix(3), id: \.self) { url in
                                    Button {
                                        switch setupInputTarget {
                                        case .vod:
                                            settingsVM.vodApiUrl = url
                                        case .live:
                                            settingsVM.liveApiUrl = url
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "clock.arrow.2.circlepath")
                                                .font(.system(size: AppTheme.fontCaption))
                                            Text(url)
                                                .font(.system(size: AppTheme.fontCaption))
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 8))
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, AppTheme.spacingLG)
                                        .foregroundColor(AppTheme.textSecondary)
                                        .glassCard(cornerRadius: 10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    
                    if let error = settingsVM.configError {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(error)
                        }
                        .font(.system(size: AppTheme.fontCaption))
                        .foregroundColor(.red)
                        .padding()
                        .glassCard(cornerRadius: 10)
                        .padding(.horizontal, 30)
                    }
                    
                    Spacer(minLength: 50)
                }
            }
        }
    }
    
    @ViewBuilder
    private var networkStatusBanner: some View {
        if !networkMonitor.isConnected {
            HStack(spacing: AppTheme.spacingSM) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: AppTheme.fontSubhead, weight: .semibold))
                Text("网络连接已断开")
                    .font(.system(size: AppTheme.fontSubhead, weight: .medium))
                if appState.isRetryingConfig {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(.white)
                }
            }
            .foregroundColor(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.spacingLG)
            .padding(.vertical, AppTheme.spacingSM)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.85))
            )
            .shadow(color: .black.opacity(0.3), radius: AppTheme.spacingSM, y: AppTheme.spacingXS)
            .padding(.top, AppTheme.spacingSM)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: networkMonitor.isConnected)
        }
    }
    
    private func readPasteboardText() -> String? {
        #if os(iOS)
        UIPasteboard.general.string
        #else
        NSPasteboard.general.string(forType: .string)
        #endif
    }
}
