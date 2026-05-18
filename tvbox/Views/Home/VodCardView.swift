import SwiftUI

struct VodCardView: View {
    let video: Movie.Video
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: URL.posterURL(from: video.pic)) { image in
                    image
                        .resizable()
                        .aspectRatio(16 / 10, contentMode: .fill)
                } placeholder: {
                    placeholderImage
                        .overlay(ProgressView().tint(.white))
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                .shadow(color: AppTheme.borderLight, radius: 4, x: 0, y: 2)

                if !video.note.isEmpty {
                    LinearGradient(
                        colors: [.black.opacity(0.8), .clear],
                        startPoint: .bottom,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
                }

                if !video.note.isEmpty {
                    Text(video.note)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(AppTheme.accentColor.opacity(0.9))
                        )
                        .padding(8)
                }
            }
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(video.name)
                    .font(.system(size: AppTheme.fontFootnote, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)

                if !video.type.isEmpty {
                    Text(video.type)
                        .font(.system(size: AppTheme.fontCaption))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: AppTheme.cardRadius)
            .fill(AppTheme.backgroundTertiary)
            .aspectRatio(16 / 10, contentMode: .fill)
            .overlay(
                Image(systemName: "film.fill")
                    .font(.system(size: 30))
                    .foregroundColor(AppTheme.textTertiary)
            )
    }
}
