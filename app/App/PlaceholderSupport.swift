import SwiftUI

@ViewBuilder
func placeholder(title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
        Text(detail)
            .foregroundStyle(Theme.textSecondary)
            .font(.callout)
        Spacer()
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.deepNavy)
}
