import SwiftUI

struct BigAccessibleButton: View {
    let title: String
    let subtitle: String?
    var superLarge: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Text(title)
                    .font(superLarge ? .system(size: 24, weight: .bold) : .title2.bold())
                    .multilineTextAlignment(.center)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(superLarge ? .system(size: 16, weight: .medium) : .body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, minHeight: superLarge ? 112 : 88)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
    }
}
