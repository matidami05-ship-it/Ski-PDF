import SwiftUI

/// Colours from the Ski PDF design: dark navy surfaces with a soft periwinkle accent.
enum Theme {
    static let background = Color(red: 0.102, green: 0.110, blue: 0.141)   // #1A1C24
    static let card = Color(red: 0.255, green: 0.267, blue: 0.314)         // #414450
    static let cardPressed = Color(red: 0.30, green: 0.31, blue: 0.36)
    static let iconTile = Color(red: 0.204, green: 0.243, blue: 0.369)     // #343E5E
    static let accent = Color(red: 0.722, green: 0.784, blue: 0.957)       // #B8C8F4
    static let section = Color(red: 0.686, green: 0.749, blue: 0.937)
    static let divider = Color.white.opacity(0.12)
    static let danger = Color(red: 0.91, green: 0.28, blue: 0.33)
}

/// A rounded panel used for option groups on tool screens.
struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.section)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The big primary action at the bottom of tool screens.
struct PrimaryButton: View {
    let title: String
    var systemImage: String = "sparkles"
    var busy: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(.black) } else { Image(systemName: systemImage) }
                Text(busy ? "Working…" : title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(disabled ? Theme.card : Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(disabled ? Color.white.opacity(0.4) : Color.black)
        }
        .disabled(disabled || busy)
    }
}

extension View {
    /// Standard tool screen background.
    func toolBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
    }
}
