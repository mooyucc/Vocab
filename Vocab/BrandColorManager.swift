//
//  BrandColorManager.swift
//  Vocab
//
//  品牌颜色管理器，用于管理品牌颜色
//

import SwiftUI
import Combine

/// 品牌颜色管理器
class BrandColorManager: ObservableObject {
    static let shared = BrandColorManager()
    
    /// 默认品牌颜色（蓝色，适合学习应用）
    let defaultBrandColor = Color.blue
    
    /// 当前品牌颜色（可观察属性，变化时自动通知所有视图）
    @Published var currentBrandColor: Color
    
    private init() {
        self.currentBrandColor = defaultBrandColor
    }
}

/// Color 扩展，支持十六进制颜色
extension Color {
    /// 从十六进制字符串创建颜色
    /// - Parameter hex: 十六进制颜色字符串（例如 "FE6A57" 或 "#FE6A57"）
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

/// 与进度页「总进度」卡片一致的品牌渐变（进度卡片、主操作按钮、词库「+」等复用）
extension LinearGradient {
    static let vocabBrandProgress = LinearGradient(
        gradient: Gradient(colors: [Color(hex: "FE6A57"), Color(hex: "FE2E69")]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
