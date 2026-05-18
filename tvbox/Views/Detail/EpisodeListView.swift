import SwiftUI

struct EpisodeListView: View {
    let episodes: [VodInfo.Episode]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    
    @State private var currentGroup = 0
    private let groupSize = 50
    private let gridColumns = [GridItem(.adaptive(minimum: 78), spacing: AppTheme.spacingSM + AppTheme.spacingXS)]
    
    private var groupCount: Int {
        max(1, (episodes.count + groupSize - 1) / groupSize)
    }
    
    private var currentEpisodes: [VodInfo.Episode] {
        let start = currentGroup * groupSize
        let end = min(start + groupSize, episodes.count)
        guard start < episodes.count else { return [] }
        return Array(episodes[start..<end])
    }
    
    var body: some View {
        VStack(spacing: AppTheme.spacingMD) {
            if groupCount > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.spacingSM) {
                        ForEach(0..<groupCount, id: \.self) { group in
                            let start = group * groupSize + 1
                            let end = min((group + 1) * groupSize, episodes.count)
                            SelectableChip(
                                title: "\(start)-\(end)",
                                isSelected: currentGroup == group,
                                action: {
                                    withAnimation {
                                        currentGroup = group
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.spacingXL)
                }
            }
            
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: AppTheme.spacingSM + AppTheme.spacingXS) {
                ForEach(Array(currentEpisodes.enumerated()), id: \.offset) { index, episode in
                    let actualIndex = currentGroup * groupSize + index
                    Button {
                        onSelect(actualIndex)
                    } label: {
                        Text(episode.name)
                            .font(.system(size: AppTheme.fontSubhead, weight: actualIndex == selectedIndex ? .bold : .medium))
                            .foregroundColor(actualIndex == selectedIndex ? .white : AppTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                ZStack {
                                    if actualIndex == selectedIndex {
                                        AppTheme.accentGradient
                                    } else {
                                        AppTheme.backgroundTertiary
                                    }
                                }
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSM))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.spacingXL)
        }
    }
}
