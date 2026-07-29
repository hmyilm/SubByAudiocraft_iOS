import SwiftUI
import UIKit

// Uygulama genelinde tek noktadan yönetilen tasarım sistemi
enum Theme {
    static let yellow = Color(red: 254/255, green: 204/255, blue: 47/255)
    static let backgroundTop = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let backgroundBottom = Color(red: 0.09, green: 0.08, blue: 0.05)
    static let card = Color(white: 0.10)
    static let cardStroke = Color.white.opacity(0.08)
    static let field = Color(white: 0.16)
    static let corner: CGFloat = 20

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    static func haptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// Tek tip kart görünümü
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

// Birincil (sarı) buton: basılınca küçülür ve hafif titreşim verir
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.bold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(enabled ? Theme.yellow : Color(white: 0.2))
            )
            .foregroundColor(enabled ? .black : .gray)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed && enabled { Theme.haptic() }
            }
    }
}

// İkincil (koyu) buton
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(white: 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
            .foregroundColor(.white)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// Kapsül içinde değer rozeti (ör. "72")
struct ValueBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(white: 0.18)))
            .foregroundColor(Theme.yellow)
    }
}

// Kart başlığı: ikon + başlık
struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.yellow)
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)
            Spacer()
        }
    }
}
