import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: AppTheme.spacingXXL) {
                Spacer()

                Image(systemName: "play.tv")
                    .font(.system(size: 64))
                    .foregroundColor(AppTheme.accentColor)

                Text("TVBox Swift")
                    .font(.system(size: AppTheme.fontTitle1, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary)

                Text("版本 1.0.0")
                    .font(.system(size: AppTheme.fontSubhead))
                    .foregroundColor(AppTheme.textSecondary)

                AppCard(cornerRadius: AppTheme.radiusLG) {
                    VStack(spacing: AppTheme.spacingLG) {
                        VStack(spacing: AppTheme.spacingSM) {
                            Text("二改作者")
                                .font(.system(size: AppTheme.fontCaption, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)

                            Text("包子")
                                .font(.system(size: AppTheme.fontHeadline, weight: .bold))
                                .foregroundColor(AppTheme.accentColor)
                        }

                        Divider().background(AppTheme.borderLight)

                        VStack(spacing: AppTheme.spacingSM) {
                            Text("致谢")
                                .font(.system(size: AppTheme.fontCaption, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary)

                            VStack(spacing: AppTheme.spacingXS) {
                                Text("感谢 FV 分屏作者 behuge")
                                    .font(.system(size: AppTheme.fontBody))
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("感谢苏苏、WKK 等越狱圈作者的付出")
                                    .font(.system(size: AppTheme.fontBody))
                                    .foregroundColor(AppTheme.textPrimary)
                            }
                        }
                    }
                    .padding(AppTheme.spacingXL)
                }
                .padding(.horizontal, AppTheme.spacingXL)

                Spacer()
            }
            .background(AppBackground())
            .navigationTitle("关于")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
