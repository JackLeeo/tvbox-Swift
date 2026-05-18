import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil
    
    var body: some View {
        VStack(spacing: AppTheme.spacingXL) {
            ZStack {
                Circle()
                    .fill(AppTheme.accentColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle().stroke(AppTheme.accentColor.opacity(0.3), lineWidth: 1)
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(AppTheme.accentGradient)
            }
            .padding(.bottom, AppTheme.spacingSM)
            
            Text(title)
                .font(.system(size: AppTheme.fontTitle3, weight: .bold))
                .foregroundColor(AppTheme.textPrimary.opacity(0.9))
                .tracking(1)
            
            if let message = message {
                Text(message)
                    .font(.system(size: AppTheme.fontBody))
                    .foregroundColor(AppTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.spacingXXL + AppTheme.spacingSM)
            }
        }
        .padding(AppTheme.spacingXXL + AppTheme.spacingLG)
        .glassCard(cornerRadius: 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
