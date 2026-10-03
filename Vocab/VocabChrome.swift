//
//  VocabChrome.swift
//  Vocab
//
//  全 App 深色氛围 / 玻璃卡片 / 发丝线标准（以背单词 Hub 为参考）
//

import SwiftUI

enum VocabChrome {
    static let atmosphereStripeSpacing: CGFloat = 11
    static let hairlineHeight: CGFloat = 0.5
    static let hairlineOpacity: Double = 0.12
    static let glassStrokeOpacity: Double = 0.1
    static let containerFillOpacity: Double = 0.06
    static let containerStrokeOpacity: Double = 0.08
}

// MARK: - Atmosphere

/// 深色全屏氛围底：近黑 + 斜纹 + 极淡双色光斑（利于玻璃折射）
struct VocabAtmosphereBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var accent: Color = .vocabBrand
    var secondaryAccent: Color = .vocabBrandDeep
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                
                Ellipse()
                    .fill(accent.opacity(0.18))
                    .frame(width: geo.size.width * 1.0, height: geo.size.width * 0.7)
                    .blur(radius: 48)
                    .offset(x: geo.size.width * 0.28, y: -geo.size.height * 0.08)
                
                Ellipse()
                    .fill(secondaryAccent.opacity(0.12))
                    .frame(width: geo.size.width * 0.85, height: geo.size.width * 0.6)
                    .blur(radius: 56)
                    .offset(x: -geo.size.width * 0.3, y: geo.size.height * 0.22)
                
                Ellipse()
                    .fill(accent.opacity(0.08))
                    .frame(width: geo.size.width * 0.95, height: geo.size.width * 0.55)
                    .blur(radius: 52)
                    .offset(x: geo.size.width * 0.05, y: geo.size.height * 0.38)
                
                Ellipse()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: geo.size.width * 0.9, height: geo.size.width * 0.5)
                    .blur(radius: 40)
                    .offset(x: 0, y: geo.size.height * 0.55)
                
                DiagonalStripePattern(lineColor: .white, spacing: VocabChrome.atmosphereStripeSpacing, lineWidth: 1)
                    .opacity(0.035)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: accent)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: secondaryAccent)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Hairline

/// 卡片内分区发丝线（inset：与内容同 padding，勿贴满圆角边）
struct VocabCardHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(VocabChrome.hairlineOpacity))
            .frame(height: VocabChrome.hairlineHeight)
            .accessibilityHidden(true)
    }
}

// MARK: - Glass

/// 玻璃底：iOS 26 Liquid Glass，旧版 Material + 压暗
struct VocabGlassBackground: View {
    var cornerRadius: CGFloat = VocabTheme.Radius.card
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: shape)
                .overlay { shape.fill(Color.black.opacity(0.22)) }
                .overlay { shape.strokeBorder(Color.white.opacity(VocabChrome.glassStrokeOpacity), lineWidth: 0.5) }
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay { shape.fill(Color.black.opacity(0.28)) }
                .overlay { shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5) }
        }
    }
}

/// 半透明列表/分组容器（手风琴外壳等）
struct VocabChromeContainerBackground: View {
    var cornerRadius: CGFloat = VocabTheme.Radius.sheet
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(VocabChrome.containerFillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(VocabChrome.containerStrokeOpacity), lineWidth: 0.5)
            )
    }
}

private struct VocabGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var glowColor: Color?
    
    func body(content: Content) -> some View {
        content
            .background {
                VocabGlassBackground(cornerRadius: cornerRadius)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(alignment: .bottom) {
                if let glowColor {
                    Ellipse()
                        .fill(glowColor.opacity(0.55))
                        .frame(height: 36)
                        .blur(radius: 22)
                        .padding(.horizontal, 28)
                        .offset(y: 10)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct VocabCapsuleChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
        }
    }
}

extension View {
    /// 玻璃卡片：可选底部同色光晕
    func vocabGlassCard(
        cornerRadius: CGFloat = VocabTheme.Radius.card,
        glow: Color? = nil
    ) -> some View {
        modifier(VocabGlassCardModifier(cornerRadius: cornerRadius, glowColor: glow))
    }
    
    /// 深色底上的玻璃 / 半透明胶囊
    func vocabCapsuleChrome() -> some View {
        modifier(VocabCapsuleChromeModifier())
    }
}
