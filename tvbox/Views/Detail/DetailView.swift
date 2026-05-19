import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct DetailView: View {
    let video: Movie.Video
    @StateObject private var viewModel = DetailViewModel()
    @StateObject private var sharedSystemController = SystemPlayerSessionController()
    @StateObject private var sharedVLCController = VLCPlayerController()
    @EnvironmentObject var appState: AppState
    @State private var showFullScreen = false
    #if os(macOS)
    @State private var pendingMacWindowFullScreen = false
    #endif
    @State private var lastPersistedProgress: Double = 0
    @State private var isCollected = false
    @State private var isFullScreenTransitioning = false
    @State private var isDescriptionExpanded = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.isPlaying, let url = viewModel.playUrl {
                    PlayerView(
                        urlString: url,
                        startPosition: viewModel.resumeSeconds,
                        onProgressChanged: handlePlaybackProgress,
                        onPlaybackEnded: playNextEpisodeIfNeeded,
                        onToggleFullScreen: {
                            openFullScreenPlayer()
                        },
                        canPlayNext: canPlayNextEpisode,
                        onPlayNext: playNextEpisodeIfNeeded,
                        canPlayPrevious: canPlayPreviousEpisode,
                        onPlayPrevious: { playPreviousEpisode() },
                        systemController: sharedSystemController,
                        vlcController: sharedVLCController,
                        httpHeaders: viewModel.playHeaders,
                        videoTitle: viewModel.vodInfo?.name ?? video.name,
                        currentEpisodeName: viewModel.vodInfo?.currentEpisode?.name ?? "",
                        showEpisodeButton: !viewModel.currentEpisodes.isEmpty,
                        onShowEpisodes: { scrollToEpisodes() },
                        onSwitchPlayer: { switchPlayerEngine() },
                        onBack: { showFullScreen = false }
                    )
                    .id("\(viewModel.selectedFlag)-\(viewModel.selectedEpisodeIndex)-\(url)")
                    .aspectRatio(16/9, contentMode: .fit)
                    .background(Color.black)
                    .overlay {
                        if showFullScreen {
                            Color.black
                        }
                    }
                }
                
                videoInfoSection
                    .padding(.horizontal, AppTheme.spacingLG)
                    .padding(.top, AppTheme.spacingLG)
                
                if viewModel.flags.count > 1 {
                    flagSelector
                        .padding(.horizontal, AppTheme.spacingLG)
                        .padding(.top, AppTheme.spacingMD)
                }
                
                if viewModel.hasQualityChoices {
                    qualitySelector
                        .padding(.horizontal, AppTheme.spacingLG)
                        .padding(.top, AppTheme.spacingMD)
                }
                
                if !viewModel.currentEpisodes.isEmpty {
                    episodeSection
                        .padding(.top, AppTheme.spacingMD)
                }
                
                if let info = viewModel.vodInfo, !info.des.isEmpty {
                    descriptionSection(info.des)
                        .padding(.horizontal, AppTheme.spacingLG)
                        .padding(.top, AppTheme.spacingMD)
                }
            }
            .padding(.bottom, 80)
        }
        .background(AppBackground())
        .navigationTitle(video.name)
        #if os(macOS)
        .toolbar((showFullScreen || pendingMacWindowFullScreen) ? .hidden : .visible, for: .windowToolbar)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: "\(video.sourceKey)-\(video.id)") {
            await viewModel.loadDetail(video: video)
            restorePlaybackFromHistory()
            refreshCollectState()
        }
        .onDisappear {
            viewModel.commitPlaybackProgressSnapshot()
            persistHistoryIfNeeded(force: true)
            showFullScreen = false
            sharedSystemController.stop()
            sharedVLCController.stop()
            #if os(macOS)
            pendingMacWindowFullScreen = false
            appState.exitPlayerFullScreen()
            #elseif os(iOS)
            rotateToPortrait()
            #endif
        }
        #if os(macOS)
        .overlay {
            if showFullScreen, let url = viewModel.playUrl {
                FullScreenPlayerView(
                    urlString: url,
                    startPosition: viewModel.resumeSeconds,
                    onProgressChanged: handlePlaybackProgress,
                    onPlaybackEnded: playNextEpisodeIfNeeded,
                    canPlayNext: canPlayNextEpisode,
                    onPlayNext: playNextEpisodeIfNeeded,
                    canPlayPrevious: canPlayPreviousEpisode,
                    onPlayPrevious: { playPreviousEpisode() },
                    systemController: sharedSystemController,
                    vlcController: sharedVLCController,
                    httpHeaders: viewModel.playHeaders,
                    onCloseRequested: closeMacFullScreenOverlay,
                    videoTitle: viewModel.vodInfo?.name ?? video.name,
                    currentEpisodeName: viewModel.vodInfo?.currentEpisode?.name ?? "",
                    showEpisodeButton: !viewModel.currentEpisodes.isEmpty,
                    onShowEpisodes: { scrollToEpisodes() },
                    onSwitchPlayer: { switchPlayerEngine() }
                )
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            guard pendingMacWindowFullScreen else { return }
            pendingMacWindowFullScreen = false
            showFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            pendingMacWindowFullScreen = false
            if showFullScreen {
                showFullScreen = false
            }
            appState.exitPlayerFullScreen()
        }
        #endif
        #if os(iOS)
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenPlayerView(
                urlString: viewModel.playUrl ?? "",
                startPosition: viewModel.resumeSeconds,
                onProgressChanged: handlePlaybackProgress,
                onPlaybackEnded: playNextEpisodeIfNeeded,
                canPlayNext: canPlayNextEpisode,
                onPlayNext: playNextEpisodeIfNeeded,
                canPlayPrevious: canPlayPreviousEpisode,
                onPlayPrevious: { playPreviousEpisode() },
                systemController: sharedSystemController,
                vlcController: sharedVLCController,
                httpHeaders: viewModel.playHeaders,
                onCloseRequested: {
                    showFullScreen = false
                },
                videoTitle: viewModel.vodInfo?.name ?? video.name,
                currentEpisodeName: viewModel.vodInfo?.currentEpisode?.name ?? "",
                showEpisodeButton: !viewModel.currentEpisodes.isEmpty,
                onShowEpisodes: { scrollToEpisodes() },
                onSwitchPlayer: { switchPlayerEngine() }
            )
            .onAppear {
                if #available(iOS 16.0, *) {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                    }
                }
            }
            .onDisappear {
                AppDelegate.orientationLock = .portrait
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                if #available(iOS 16.0, *) {
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                        }
                    }
                } else {
                    UIViewController.attemptRotationToDeviceOrientation()
                }
            }
        }
        #endif
    }
    
    @ViewBuilder
    private var videoInfoSection: some View {
        AppCard(cornerRadius: AppTheme.radiusLG) {
            VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
                Text(viewModel.vodInfo?.name ?? video.name)
                    .font(.system(size: AppTheme.fontTitle2, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)
                
                if let info = viewModel.vodInfo {
                    metadataFlow(info)
                }
                
                HStack(spacing: AppTheme.spacingMD) {
                    playButton
                    collectButton
                }
            }
        }
    }

    @ViewBuilder
    private func metadataFlow(_ info: VodInfo) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
            HStack(spacing: AppTheme.spacingSM) {
                if !info.year.isEmpty {
                    metadataPill(info.year)
                }
                if !info.typeName.isEmpty {
                    metadataPill(info.typeName)
                }
                if !info.area.isEmpty {
                    metadataPill(info.area)
                }
            }
            
            if !info.director.isEmpty {
                HStack(spacing: AppTheme.spacingXS) {
                    Text("导演")
                        .font(.system(size: AppTheme.fontCaption))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(info.director)
                        .font(.system(size: AppTheme.fontCaption))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            
            if !info.actor.isEmpty {
                HStack(spacing: AppTheme.spacingXS) {
                    Text("演员")
                        .font(.system(size: AppTheme.fontCaption))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(info.actor)
                        .font(.system(size: AppTheme.fontCaption))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: AppTheme.fontFootnote, weight: .medium))
            .foregroundColor(AppTheme.textSecondary)
            .padding(.horizontal, AppTheme.spacingSM)
            .padding(.vertical, AppTheme.spacingXS)
            .background(AppTheme.backgroundTertiary)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var playButton: some View {
        if !viewModel.isPlaying && viewModel.vodInfo != nil {
            Button {
                viewModel.selectEpisode(index: 0)
                saveHistoryForCurrentEpisode()
            } label: {
                HStack(spacing: AppTheme.spacingSM) {
                    Image(systemName: "play.fill")
                    Text("播放")
                }
                .font(.system(size: AppTheme.fontHeadline, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.spacingMD)
                .background(AppTheme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD))
            }
            .buttonStyle(.plain)
        }
    }
    
    private var collectButton: some View {
        Button {
            toggleCollect()
        } label: {
            HStack(spacing: AppTheme.spacingXS) {
                Image(systemName: isCollected ? "heart.fill" : "heart")
                Text(isCollected ? "已收藏" : "收藏")
            }
            .font(.system(size: AppTheme.fontSubhead, weight: .semibold))
            .foregroundColor(isCollected ? .white : AppTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacingMD)
            .background(
                Group {
                    if isCollected {
                        AppTheme.accentGradient
                    } else {
                        AppTheme.backgroundTertiary
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusMD)
                    .stroke(isCollected ? Color.clear : AppTheme.borderMedium, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var flagSelector: some View {
        AppCard(cornerRadius: AppTheme.radiusLG) {
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                AppSectionHeader(title: "播放线路", icon: "antenna.radiowaves.left")
                
                flagScrollView
            }
        }
    }

    @ViewBuilder
    private var flagScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacingSM) {
                ForEach(viewModel.flags, id: \.self) { flag in
                    pillChip(
                        title: flag,
                        isSelected: viewModel.selectedFlag == flag,
                        action: {
                            withAnimation {
                                viewModel.selectFlag(flag)
                            }
                            if viewModel.isPlaying {
                                saveHistoryForCurrentEpisode()
                            }
                        }
                    )
                }
            }
        }
    }
    
    @ViewBuilder
    private var qualitySelector: some View {
        AppCard(cornerRadius: AppTheme.radiusLG) {
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                AppSectionHeader(title: "视频清晰度", icon: "sparkles")
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingSM) {
                        ForEach(viewModel.qualityOptions) { option in
                            pillChip(
                                title: option.name,
                                isSelected: viewModel.selectedQualityId == option.id,
                                action: {
                                    withAnimation {
                                        viewModel.selectQuality(option)
                                    }
                                    if viewModel.isPlaying {
                                        saveHistoryForCurrentEpisode()
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pillChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: AppTheme.fontFootnote, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? AppTheme.accentColor : AppTheme.textSecondary)
                .padding(.horizontal, AppTheme.spacingLG)
                .padding(.vertical, AppTheme.spacingSM)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.accentColor.opacity(0.12) : AppTheme.backgroundTertiary)
                )
        }
        .buttonStyle(.plain)
    }
    
    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacingMD) {
            AppSectionHeader(title: "选集播放", icon: "list.bullet")
                .padding(.horizontal, AppTheme.spacingXL)
            
            EpisodeListView(
                episodes: viewModel.currentEpisodes,
                selectedIndex: viewModel.selectedEpisodeIndex,
                onSelect: { index in
                    withAnimation {
                        viewModel.selectEpisode(index: index)
                    }
                    saveHistoryForCurrentEpisode()
                }
            )
        }
    }
    
    private func descriptionSection(_ des: String) -> some View {
        AppCard(cornerRadius: AppTheme.radiusLG) {
            VStack(alignment: .leading, spacing: AppTheme.spacingSM) {
                AppSectionHeader(title: "影片简介", icon: "doc.text")
                
                Text(des)
                    .font(.system(size: AppTheme.fontBody))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineSpacing(AppTheme.spacingXS)
                    .lineLimit(isDescriptionExpanded ? nil : 3)
                
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isDescriptionExpanded.toggle()
                    }
                } label: {
                    Text(isDescriptionExpanded ? "收起" : "展开")
                        .font(.system(size: AppTheme.fontFootnote, weight: .medium))
                        .foregroundColor(AppTheme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var canPlayNextEpisode: Bool {
        viewModel.selectedEpisodeIndex + 1 < viewModel.currentEpisodes.count
    }

    private var canPlayPreviousEpisode: Bool {
        viewModel.selectedEpisodeIndex > 0
    }
    
    private func saveHistoryForCurrentEpisode(progressOverride: Double? = nil) {
        let episodeName = viewModel.vodInfo?.currentEpisode?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let episodeLabel = episodeName.isEmpty ? "第\(viewModel.selectedEpisodeIndex + 1)集" : episodeName
        let progress = max(progressOverride ?? viewModel.currentPlaybackSeconds(), 0)
        let timeLabel = progress > 0 ? Int(progress).durationString : ""
        let playNote = timeLabel.isEmpty ? episodeLabel : "\(episodeLabel) \(timeLabel)"
        
        let playbackState = VodPlaybackState(
            flag: viewModel.selectedFlag,
            episodeIndex: viewModel.selectedEpisodeIndex,
            progressSeconds: progress
        )
        
        Task { @MainActor in
            CacheStore.shared.addRecord(
                video,
                playNote: playNote,
                playbackState: playbackState
            )
        }
    }
    
    private func handlePlaybackProgress(_ seconds: Double, _: Double?) {
        viewModel.updatePlaybackProgress(seconds: seconds)
        persistHistoryIfNeeded(force: false, currentProgress: seconds)
    }
    
    private func persistHistoryIfNeeded(force: Bool, currentProgress: Double? = nil) {
        guard viewModel.isPlaying else { return }
        let progress = max(currentProgress ?? viewModel.currentPlaybackSeconds(), 0)
        guard progress.isFinite else { return }
        
        if !force && abs(progress - lastPersistedProgress) < 20 {
            return
        }
        
        lastPersistedProgress = progress
        saveHistoryForCurrentEpisode(progressOverride: progress)
    }
    
    private func restorePlaybackFromHistory() {
        guard let playbackState = CacheStore.shared.getPlaybackState(
            vodId: video.id,
            sourceKey: video.sourceKey
        ) else { return }
        
        viewModel.applyPlaybackState(playbackState)
        lastPersistedProgress = max(playbackState.progressSeconds, 0)
    }
    
    private func refreshCollectState() {
        isCollected = CacheStore.shared.isCollected(
            vodId: video.id,
            sourceKey: video.sourceKey
        )
    }
    
    private func toggleCollect() {
        if isCollected {
            CacheStore.shared.removeCollect(
                vodId: video.id,
                sourceKey: video.sourceKey
            )
        } else {
            CacheStore.shared.addCollect(video)
        }
        refreshCollectState()
    }
    
    private func playNextEpisodeIfNeeded() {
        var moved = false
        withAnimation {
            moved = viewModel.playNext()
        }
        
        if moved {
            saveHistoryForCurrentEpisode()
        }
    }
    
    private func playPreviousEpisode() {
        var moved = false
        withAnimation {
            moved = viewModel.playPrevious()
        }
        
        if moved {
            saveHistoryForCurrentEpisode()
        }
    }
    
    private func openFullScreenPlayer() {
        #if os(iOS)
        guard !isFullScreenTransitioning else { return }
        isFullScreenTransitioning = true

        AppDelegate.orientationLock = .landscape
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        if #available(iOS 16.0, *) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
                scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showFullScreen = true
            isFullScreenTransitioning = false
        }
        #else
        guard viewModel.playUrl != nil else { return }
        appState.enterPlayerFullScreen()
        
        if let window = NSApp.keyWindow ?? NSApp.mainWindow,
           window.styleMask.contains(.fullScreen) {
            showFullScreen = true
            return
        }
        
        pendingMacWindowFullScreen = requestMacWindowFullScreen(enter: true)
        if !pendingMacWindowFullScreen {
            showFullScreen = true
        }
        #endif
    }
    
    #if os(macOS)
    @discardableResult
    private func requestMacWindowFullScreen(enter: Bool) -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        guard enter != isFullScreen else { return false }
        window.toggleFullScreen(nil)
        return true
    }
    
    private func closeMacFullScreenOverlay() {
        pendingMacWindowFullScreen = false
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        if window?.styleMask.contains(.fullScreen) == true {
            requestMacWindowFullScreen(enter: false)
            return
        }
        showFullScreen = false
        appState.exitPlayerFullScreen()
    }
    #endif

    private func scrollToEpisodes() {
        if showFullScreen {
            #if os(iOS)
            showFullScreen = false
            #else
            showFullScreen = false
            appState.exitPlayerFullScreen()
            #endif
        }
    }

    private func switchPlayerEngine() {
        let current = UserDefaults.standard.integer(forKey: HawkConfig.PLAY_TYPE_VOD)
        let newEngine: PlayerEngine
        if PlayerEngine.fromStoredValue(current) == .vlc {
            newEngine = .system
        } else {
            if PlayerEngine.isVLCAvailable {
                newEngine = .vlc
            } else {
                return
            }
        }
        UserDefaults.standard.set(newEngine.rawValue, forKey: HawkConfig.PLAY_TYPE_VOD)
    }

    #if os(iOS)
    private func rotateToPortrait() {
        AppDelegate.orientationLock = .portrait
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        if #available(iOS 16.0, *) {
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            scene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
    #endif
}

struct FullScreenPlayerView: View {
    let urlString: String
    var startPosition: Double = 0
    var onProgressChanged: ((Double, Double?) -> Void)? = nil
    var onPlaybackEnded: (() -> Void)? = nil
    var canPlayNext: Bool = false
    var onPlayNext: (() -> Void)? = nil
    var canPlayPrevious: Bool = false
    var onPlayPrevious: (() -> Void)? = nil
    var systemController: SystemPlayerSessionController? = nil
    var vlcController: VLCPlayerController? = nil
    var httpHeaders: [String: String] = [:]
    var onCloseRequested: (() -> Void)? = nil
    var videoTitle: String = ""
    var currentEpisodeName: String = ""
    var showEpisodeButton: Bool = false
    var onShowEpisodes: (() -> Void)? = nil
    var onSwitchPlayer: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerView(
                urlString: urlString,
                startPosition: startPosition,
                onProgressChanged: onProgressChanged,
                onPlaybackEnded: onPlaybackEnded,
                onToggleFullScreen: {
                    onCloseRequested?()
                },
                canPlayNext: canPlayNext,
                onPlayNext: onPlayNext,
                canPlayPrevious: canPlayPrevious,
                onPlayPrevious: onPlayPrevious,
                systemController: systemController,
                vlcController: vlcController,
                isFullScreenMode: true,
                httpHeaders: httpHeaders,
                videoTitle: videoTitle,
                currentEpisodeName: currentEpisodeName,
                showEpisodeButton: showEpisodeButton,
                onShowEpisodes: onShowEpisodes,
                onSwitchPlayer: onSwitchPlayer,
                onBack: { onCloseRequested?() }
            )
        }
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
    }
}
