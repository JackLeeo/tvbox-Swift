import SwiftUI

struct VodCardView: View {
    let video: Movie.Video
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: URL.posterURL(from: video.pic)) { image in
                    image
                        .resizable()
                        .aspectRatio(2 / 3, contentMode: .fill)
                } placeholder: {
                    placeholderImage
                        .overlay(ProgressView().tint(.white))
                }
                .frame(maxWidth: .infinity)
                .clipped()

                if !video.note.isEmpty {
                    Text(video.note)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(AppTheme.accentColor.opacity(0.85))
                        )
                        .padding(AppTheme.spacingXS)
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: AppTheme.radiusSM, topTrailingRadius: AppTheme.radiusSM))

            VStack(alignment: .leading, spacing: 2) {
                Text(video.name)
                    .font(.system(size: AppTheme.fontFootnote, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)
                    .lineSpacing(1)

                if !metaText.isEmpty {
                    Text(metaText)
                        .font(.system(size: AppTheme.fontCaption - 1))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, AppTheme.spacingXS + 2)
            .padding(.vertical, AppTheme.spacingXS + 2)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusSM)
                .fill(AppTheme.backgroundSecondary)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSM))
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var metaText: String {
        let parts = [video.type, video.year].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private var placeholderImage: some View {
        Rectangle()
            .fill(AppTheme.backgroundTertiary)
            .aspectRatio(2 / 3, contentMode: .fill)
            .overlay(
                Image(systemName: "film.fill")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.textTertiary)
            )
    }
}
