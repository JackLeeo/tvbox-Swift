import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif

/// 直播页 - 对应 Android 版 LivePlayActivity
struct LiveView: View {
    /// 直播频道与选中状态管理。
    @StateObject private var viewModel = LiveViewModel()
    /// 全局应用状态（用于 macOS 全屏时调整分栏布局）。
    @EnvironmentObject var appState: AppState
    /// 系统播放器实例（仅在选择系统内核时使用）。
    @State private var avPlayer: AVPlayer?
    /// 直播播放器内核配置（新字段）。
    @AppStorage(HawkConfig.PLAY_TYPE_LIVE) private var livePlayTypeRaw = -1
    /// 兼容旧版本单播放器字段。
    @AppStorage(HawkConfig.PLAY_TYPE) private var legacyPlayTypeRaw = PlayerEngine.system.rawValue
    /// 是否展示左侧频道抽屉。
    @State private var showChannelDrawer = true
    /// 当前窗口是否处于全屏。
    @State private var isWindowFullScreen = false
    /// 底部频道信息卡最大宽度。
    private let currentChannelInfoMaxWidth: CGFloat = 600
    /// AVPlayer 状态观察者。
    @State private var itemStatusObserver: NSKeyValueObservation?
    /// 播放失败通知观察者。
    @State private var playbackFailedObserver: NSObjectProtocol?
    /// 播放卡顿通知观察者。
    @State private var playbackStalledObserver: NSObjectProtocol?
    /// 当前频道已失败的线路索引，用于自动切线去重。
    @State private var failedSourceIndices: Set<Int> = []
    /// 当前跟踪的频道 ID（频道切换时重置失败状态）。
    @State private var trackedChannelId: String = ""
    /// 底部频道信息是否显示。
    @State private var showCurrentChannelInfo = true
    /// 自动隐藏频道信息的定时器。
    @State private var channelInfoTimer: Timer?
    /// 频道信息自动隐藏延迟（秒）。
    private let channelInfoAutoHideDelay: TimeInterval = 3.0
    /// 用户交互令牌，递增后可通知 VLC 子视图重置自动隐藏逻辑。
    @State private var vlcInteractionToken = 0
    
    /// 当前实际生效的播放器内核。
    /// 优先读取直播专用字段，再回退老字段，最后使用默认值。
    private var selectedEngine: PlayerEngine {
        let defaults = UserDefaults.standard
        let rawValue: Int
        if defaults.object(forKey: HawkConfig.PLAY_TYPE_LIVE) != nil {
            rawValue = livePlayTypeRaw
        } else if defaults.object(forKey: HawkConfig.PLAY_TYPE) != nil {
            rawValue = legacyPlayTypeRaw
        } else {
            rawValue = PlayerEngine.isVLCAvailable
                ? PlayerEngine.vlc.rawValue
                : PlayerEngine.system.rawValue
        }
        return PlayerEngine.fromStoredValue(rawValue)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.channelGroups.isEmpty {
                    emptyState
                } else {
                    // 播放器
                    if selectedEngine == .vlc {
                        if let urlString = viewModel.currentChannel?.currentUrl, !urlString.isEmpty {
                            VLCLivePlayerView(
                                urlString: urlString,
                                activityToken: vlcInteractionToken,
                                onPlaybackFailed: {
                                    handlePlaybackFailure(trigger: "vlc_error")
                                },
                                onToggleFullScreen: {
                                    toggleWindowFullScreen()
                                }
                            )
                            .ignoresSafeArea()
                            .id("vlc-live-\(urlString)-\(viewModel.currentChannel?.id ?? "")")
                        }
                    } else if let player = avPlayer {
                        PlatformVideoPlayer(player: player)
                            .ignoresSafeArea()
                    }
                    
                    // 覆盖 UI
                    overlayUI
                }
            }
            .navigationTitle("直播")
            #if os(macOS)
            .toolbar(isWindowFullScreen ? .hidden : .visible, for: .windowToolbar)
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                // 首次进入时加载频道并展示频道信息卡。
                viewModel.loadChannels()
                wakeUpCurrentChannelInfo()
            }
            .onChange(of: viewModel.currentChannel?.currentUrl) { _, newValue in
                if selectedEngine == .system {
                    playChannel(url: newValue)
                } else {
                    cleanupPlayer()
                }
                wakeUpCurrentChannelInfo()
            }
            .onChange(of: viewModel.currentChannel?.id) { _, _ in
                // 切台后清空失败线路记录，避免复用上个频道的失败状态。
                resetFailureTracking(for: viewModel.currentChannel)
                wakeUpCurrentChannelInfo()
            }
            .onChange(of: selectedEngine) { _, _ in
                if selectedEngine == .system {
                    playChannel(url: viewModel.currentChannel?.currentUrl)
                } else {
                    cleanupPlayer()
                }
            }
            .onDisappear {
                cleanupPlayer()
                cancelChannelInfoAutoHide()
                #if os(macOS)
                appState.exitPlayerFullScreen()
                isWindowFullScreen = false
                #endif
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                isWindowFullScreen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                isWindowFullScreen = false
                appState.exitPlayerFullScreen()
            }
            .onExitCommand {
                if showChannelDrawer {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChannelDrawer = false
                    }
                }
            }
            #endif
        }
    }
    
    // MARK: - 空状态
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("暂无直播源")
                .font(.headline)
                .foregroundColor(.gray)
            Text("请在设置中配置包含直播源的接口")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - 覆盖 UI
    
    private var overlayUI: some View {
        ZStack(alignment: .leading) {
            if showChannelDrawer {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showChannelDrawer = false
                        }
                    }
            }
            
            VStack(spacing: 0) {
                HStack {
                    channelDrawerToggleButton
                    Spacer()
                }
                .padding(.top, 18)
                .padding(.horizontal, 16)
                
                Spacer()
                
                // 底部当前频道信息
                if let channel = viewModel.currentChannel, showCurrentChannelInfo {
                    currentChannelInfo(channel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            
            if showChannelDrawer {
                channelDrawer
                    .padding(.leading, 12)
                    .padding(.vertical, 20)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showCurrentChannelInfo)
        .simultaneousGesture(
            TapGesture().onEnded {
                reportUserActivity()
            }
        )
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active(_):
                reportUserActivity()
            case .ended:
                break
            }
        }
        #endif
    }
    
    private var channelDrawer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("频道菜单", systemImage: "list.bullet.rectangle.portrait")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChannelDrawer = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            
            HStack(spacing: 0) {
                channelGroupList
                    .frame(width: 150)
                
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                channelList
                    .frame(width: 240)
            }
        }
        .frame(width: 390)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassCard(cornerRadius: 14)
    }
    
    private var channelDrawerToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showChannelDrawer.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showChannelDrawer ? "sidebar.left" : "sidebar.right")
                Text(showChannelDrawer ? "收起菜单" : "频道菜单")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .keyboardShortcut("m", modifiers: [.command])
        #endif
    }
    
    private func currentChannelInfo(_ channel: LiveChannelItem) -> some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Circle().fill(Color.orange).frame(width: 8, height: 8)
                    Text(channel.channelName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                if channel.sourceNum > 1 {
                    Text("正在播放：线路 \(channel.sourceIndex + 1) / \(channel.sourceNum)")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // 切换线路按钮
                if channel.sourceNum > 1 {
                    Button {
                        wakeUpCurrentChannelInfo()
                        resetFailureTracking(for: viewModel.currentChannel)
                        viewModel.switchSource()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "shuffle")
                            Text("切换线路")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(AppTheme.accentGradient)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                
                #if os(macOS)
                Button {
                    wakeUpCurrentChannelInfo()
                    toggleWindowFullScreen()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text("全屏")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(20)
        .glassCard(cornerRadius: AppTheme.glassRadius)
        .frame(maxWidth: currentChannelInfoMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(20)
    }
    
    private func wakeUpCurrentChannelInfo() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showCurrentChannelInfo = true
        }
        channelInfoTimer?.invalidate()
        guard viewModel.currentChannel != nil else { return }
        
        channelInfoTimer = Timer.scheduledTimer(withTimeInterval: channelInfoAutoHideDelay, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                showCurrentChannelInfo = false
            }
        }
    }
    
    private func cancelChannelInfoAutoHide() {
        channelInfoTimer?.invalidate()
        channelInfoTimer = nil
    }
    
    private func reportUserActivity() {
        // 任意交互都刷新显示时间，并触发 VLC 子层同步交互状态。
        wakeUpCurrentChannelInfo()
        vlcInteractionToken &+= 1
    }
    
    // MARK: - 频道分组
    
    private var channelGroupList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.channelGroups.enumerated()), id: \.offset) { index, group in
                    Button {
                        withAnimation {
                            viewModel.selectGroup(index)
                        }
                    } label: {
                        Text(group.groupName)
                            .font(.system(size: 14, weight: viewModel.selectedGroupIndex == index ? .bold : .medium))
                            .foregroundColor(viewModel.selectedGroupIndex == index ? .orange : .white.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                viewModel.selectedGroupIndex == index
                                    ? Color.white.opacity(0.1)
                                    : Color.clear
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 频道列表
    
    private var channelList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.currentChannels.enumerated()), id: \.offset) { index, channel in
                    Button {
                        withAnimation {
                            viewModel.selectedChannelIndex = index
                            viewModel.selectChannel(channel)
                        }
                    } label: {
                        HStack {
                            Text(channel.channelName)
                                .font(.system(size: 14, weight: viewModel.currentChannel?.channelName == channel.channelName ? .bold : .medium))
                                .foregroundColor(viewModel.currentChannel?.channelName == channel.channelName ? .orange : .white.opacity(0.8))
                            Spacer()
                            if channel.sourceNum > 1 {
                                Text("\(channel.sourceNum)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.3))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            viewModel.currentChannel?.channelName == channel.channelName
                                ? Color.orange.opacity(0.15)
                                : Color.clear
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 播放
    
    private func playChannel(url: String?) {
        guard let urlStr = url, let url = URL(string: urlStr) else {
            handlePlaybackFailure(trigger: "invalid_url")
            return
        }
        
        cleanupPlayer()
        
        let playerItem = AVPlayerItem(url: url)
        // 直播场景优先实时性，避免过多缓冲导致内存上涨
        playerItem.preferredForwardBufferDuration = 3
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        observePlaybackFailure(for: playerItem)
        
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.play()
        avPlayer = newPlayer
    }
    
    private func cleanupPlayer() {
        // 先移除观察者再释放播放器，避免悬空回调。
        if let observer = playbackFailedObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackFailedObserver = nil
        }
        if let observer = playbackStalledObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackStalledObserver = nil
        }
        itemStatusObserver = nil
        
        avPlayer?.pause()
        avPlayer?.replaceCurrentItem(with: nil)
        avPlayer = nil
    }
    
    private func observePlaybackFailure(for item: AVPlayerItem) {
        // KVO 监听 item 状态失败。
        itemStatusObserver = item.observe(\.status, options: [.new]) { observedItem, _ in
            if observedItem.status == .failed {
                DispatchQueue.main.async {
                    handlePlaybackFailure(trigger: "status_failed")
                }
            }
        }
        
        // 播放到结尾失败回调。
        playbackFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            handlePlaybackFailure(trigger: "item_failed")
        }
        
        // 播放卡顿回调。
        playbackStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { _ in
            handlePlaybackFailure(trigger: "playback_stalled")
        }
    }
    
    private func resetFailureTracking(for channel: LiveChannelItem?) {
        failedSourceIndices = []
        trackedChannelId = channel?.id ?? ""
    }
    
    private func handlePlaybackFailure(trigger: String) {
        guard let channel = viewModel.currentChannel else { return }
        guard channel.sourceNum > 1 else { return }
        
        if trackedChannelId != channel.id {
            resetFailureTracking(for: channel)
        }
        
        let failedIndex = channel.sourceIndex
        guard !failedSourceIndices.contains(failedIndex) else { return }
        failedSourceIndices.insert(failedIndex)
        
        guard switchToNextAvailableSource(totalSources: channel.sourceNum) else {
            print("直播线路全部尝试失败: channel=\(channel.channelName), trigger=\(trigger)")
            return
        }
    }
    
    private func switchToNextAvailableSource(totalSources: Int) -> Bool {
        guard failedSourceIndices.count < totalSources else { return false }
        
        // 最多轮询 `totalSources` 次，找到一条尚未失败的线路即返回。
        for _ in 0..<totalSources {
            viewModel.switchSource()
            guard let nextIndex = viewModel.currentChannel?.sourceIndex else { return false }
            if !failedSourceIndices.contains(nextIndex) {
                return true
            }
        }
        
        return false
    }
    
    #if os(macOS)
    private func toggleWindowFullScreen() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        let enteringFullScreen = !window.styleMask.contains(.fullScreen)
        if enteringFullScreen {
            isWindowFullScreen = true
            appState.enterPlayerFullScreen()
        }
        window.toggleFullScreen(nil)
    }
    #else
    private func toggleWindowFullScreen() {}
    #endif
}
