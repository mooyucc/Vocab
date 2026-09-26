//
//  BrandColorManager.swift
//  Vocab
//
//  品牌颜色管理器，用于管理品牌颜色
//

import SwiftUI
import Combine
import UIKit

/// 品牌颜色管理器
class BrandColorManager: ObservableObject {
    static let shared = BrandColorManager()
    
    /// 默认品牌颜色（玫瑰粉，与进度卡 / 主 CTA 一致）
    let defaultBrandColor = Color.vocabBrand
    
    /// 当前品牌颜色（可观察属性，变化时自动通知所有视图）
    @Published var currentBrandColor: Color
    
    private init() {
        self.currentBrandColor = defaultBrandColor
    }
}

enum VocabTheme {
    enum Radius {
        static let chip: CGFloat = 12
        static let card: CGFloat = 24
        static let sheet: CGFloat = 28
        static let hero: CGFloat = 32
    }
}

/// 斜纹底（词库进度卡 / 背单词橙环等复用；颜色由调用方控制）
struct DiagonalStripePattern: View {
    var lineColor: Color = .white
    var spacing: CGFloat = 9
    var lineWidth: CGFloat = 1.25
    
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// Color 扩展，支持十六进制颜色
extension Color {
    /// 品牌主色（附图玫瑰粉）
    static let vocabBrand = Color(hex: "E36C85")
    /// 品牌辅色（渐变末端）
    static let vocabBrandDeep = Color(hex: "C94D68")
    
    static let vocabCanvas = Color(uiColor: .vocab(light: "FDFEEA", dark: "1C1B19"))
    static let vocabSurface = Color(uiColor: .vocab(light: "FFFBF5", dark: "2A2826"))
    static let vocabInk = Color(uiColor: .vocab(light: "2C2A28", dark: "F4F0E8"))
    static let vocabTeal = Color(uiColor: .vocab(light: "519286", dark: "6BA89C"))
    static let vocabGold = Color(uiColor: .vocab(light: "F1B145", dark: "F5C05C"))
    static let vocabBlush = Color(uiColor: .vocab(light: "F3C5C8", dark: "E8A8AD"))
    
    static let vocabFillBlush = Color(uiColor: .vocab(light: "E8A8AD", dark: "6B3F44"))
    static let vocabFillTeal = Color(uiColor: .vocab(light: "519286", dark: "2A5F56"))
    static let vocabFillCoral = Color(uiColor: .vocab(light: "E36C85", dark: "6B3F44"))
    static let vocabFillGold = Color(uiColor: .vocab(light: "F1B145", dark: "6B5420"))
    
    /// 词库页沉浸底（附图青绿，亮暗模式同色）
    static let vocabLibraryCanvas = Color(hex: "1F5C55")
    static let vocabLibraryBlob = Color(hex: "2E7A70")
    static let vocabLibraryStripe = Color(hex: "163F3B")
    static let vocabLibraryControl = Color.white.opacity(0.14)
    
    /// 从十六进制字符串创建颜色
    /// - Parameter hex: 十六进制颜色字符串（例如 "E36C85" 或 "#E36C85"）
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // ARGB
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

private extension UIColor {
    convenience init(vocabHex: String) {
        let hex = vocabHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
    
    static func vocab(light: String, dark: String) -> UIColor {
        UIColor { trait in
            UIColor(vocabHex: trait.userInterfaceStyle == .dark ? dark : light)
        }
    }
}

/// 品牌渐变（词库「+」、闪卡等复用）
extension LinearGradient {
    static var vocabBrandProgress: LinearGradient {
        LinearGradient(
            colors: [.vocabBrand, .vocabBrandDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var vocabTealProgress: LinearGradient {
        LinearGradient(
            colors: [Color.vocabTeal, Color.vocabTeal.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var vocabGoldProgress: LinearGradient {
        LinearGradient(
            colors: [Color.vocabGold, Color(hex: "D4922E")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct VocabPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// 设置等 Form：系统分组底色 + 品牌主题色
    func vocabFormCanvas() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .listRowBackground(Color(.secondarySystemGroupedBackground))
            .tint(Color.vocabBrand)
    }
}
