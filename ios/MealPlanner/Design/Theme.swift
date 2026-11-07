import SwiftUI
import UIKit
import MealCore

/// Визуальная система «Рацион»: тёплая бумага + глубокий зелёный + шафран. Без фиолетовых градиентов.
enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let paper = dyn(0xF6F1E7, 0x0F1512)       // фон
    static let card = dyn(0xFFFFFF, 0x18211C)        // карточки
    static let ink = dyn(0x1B2A24, 0xF0EBDD)         // основной текст
    static let muted = dyn(0x6C7A72, 0x9AA8A0)       // вторичный текст
    static let accent = dyn(0x1F5F46, 0x6FBF98)      // глубокий зелёный
    static let saffron = dyn(0xE29A2D, 0xF0B050)     // шафран — акцент для денег/выделения
    static let tomato = dyn(0xC8472F, 0xE8745C)      // предупреждения
    static let sage = dyn(0xDCE7D8, 0x24332B)        // мягкий фон-плашка
    static let line = dyn(0xE3DCCB, 0x2A362F)

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .serif) }
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight, design: .rounded).monospacedDigit() }
    static let body = Font.system(.body, design: .default)
    static let caption = Font.system(.footnote, design: .default)
    static let corner: CGFloat = 20
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
    func screenBackground() -> some View { background(Theme.paper.ignoresSafeArea()) }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(.white) }
                else if let s = systemImage { Image(systemName: s) }
                Text(title).font(.system(.headline, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(Color.white)
            .background(Theme.accent, in: Capsule())
        }
        .disabled(isLoading)
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let s = systemImage { Image(systemName: s) }
                Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(Theme.accent)
            .background(Theme.sage, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let text: String
    var selected = false
    var systemImage: String?
    var body: some View {
        HStack(spacing: 4) {
            if let s = systemImage { Image(systemName: s).font(.caption) }
            Text(text).font(.system(.subheadline, design: .rounded))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .foregroundStyle(selected ? Color.white : Theme.ink)
        .background(selected ? Theme.accent : Theme.sage, in: Capsule())
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View { Text(text).font(Theme.display(22)).foregroundStyle(Theme.ink) }
}

/// «Тарелка бюджета»: кольцо с использованной и оставшейся частью.
struct BudgetPlate: View {
    let spent: Money
    let budget: Money
    var over: Bool { spent > budget }
    var fraction: Double { budget.kopecks > 0 ? min(1, Double(spent.kopecks) / Double(budget.kopecks)) : 0 }
    var body: some View {
        ZStack {
            Circle().stroke(Theme.sage, lineWidth: 18)
            Circle().trim(from: 0, to: fraction)
                .stroke(over ? Theme.tomato : Theme.accent, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: fraction)
            VStack(spacing: 2) {
                Text(over ? "Перерасход" : "Остаток").font(Theme.caption).foregroundStyle(Theme.muted)
                Text((budget - spent).formatted()).font(Theme.number(26)).foregroundStyle(over ? Theme.tomato : Theme.ink)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("из \(budget.formatted())").font(Theme.caption).foregroundStyle(Theme.muted)
            }.padding(24)
        }
        .frame(width: 190, height: 190)
    }
}

struct QualityBadge: View {
    let quality: PriceQuality
    var body: some View {
        Text(quality.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(quality == .estimate ? Theme.tomato : Theme.accent)
            .background((quality == .estimate ? Theme.tomato : Theme.accent).opacity(0.12), in: Capsule())
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(Theme.accent)
            Text(title).font(Theme.display(20)).foregroundStyle(Theme.ink)
            Text(text).font(Theme.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity)
    }
}
