//
//  FlashCardView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

struct FlashCardView: View {
    let word: Word
    let onResult: (Bool) -> Void
    let showActionButtons: Bool
    
    @Query private var allWords: [Word]
    @Environment(\.modelContext) private var modelContext
    @State private var isFlipped = false
    @State private var forgotTrigger: Int = 0
    @State private var rememberedTrigger: Int = 0
    @State private var isUpdatingExample = false
    @State private var updateExampleError: String?
    @State private var showPaywall = false
    
    @State private var rememberedCombo: Int = 0
    @State private var showComboLabel: Bool = false
    @State private var showHeartAnimation: Bool = false
    
    /// 心形展示时长，结束后切到下一张卡（与心形动画时长一致，避免播到一半被切掉）
    private static let heartDisplayDuration: TimeInterval = 1.0
    
    init(word: Word, onResult: @escaping (Bool) -> Void, showActionButtons: Bool = true) {
        self.word = word
        self.onResult = onResult
        self.showActionButtons = showActionButtons
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部能量与连击指示
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.yellow)
                    (Text(LocalizedKey.vocabularyEnergy.rawValue.localized) + Text(" ") + Text("\(VocabularyEnergy.totalPoints(for: allWords))"))
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .orange.opacity(0.6), radius: 8, x: 0, y: 4)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(LocalizedKey.vocabularyEnergy.rawValue.localized) \(VocabularyEnergy.totalPoints(for: allWords))"
                )
                
                Spacer()
                
                if showComboLabel && rememberedCombo > 1 {
                    Text("连击 x\(rememberedCombo)")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .orange.opacity(0.6), radius: 8, x: 0, y: 4)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            
            // 卡片
            GeometryReader { geometry in
                ZStack {
                    // 正面
                    CardFront(word: word, isFlipped: isFlipped)
                        .rotation3DEffect(
                            .degrees(isFlipped ? 180 : 0),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .opacity(isFlipped ? 0 : 1)
                    
                    // 背面
                    CardBack(
                        word: word,
                        isUpdatingExample: isUpdatingExample,
                        onUpdateExample: updateExample
                    )
                        .rotation3DEffect(
                            .degrees(isFlipped ? 0 : -180),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .opacity(isFlipped ? 1 : 0)
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        isFlipped.toggle()
                    }
                }
            }
            
            // 控制按钮
            if showActionButtons {
                ZStack {
                    HStack(spacing: 16) {
                        Button(action: {
                            forgotTrigger += 1
                            rememberedCombo = 0
                            showComboLabel = false
                            onResult(false)
                            resetCard()
                        }) {
                            HStack {
                                Image(systemName: "xmark")
                                Text(LocalizedKey.forgot)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .controlSize(.large)
                        .applySensoryFeedback(trigger: forgotTrigger, style: .soft)
                        .accessibilityLabel(LocalizedKey.forgot.rawValue.localized)
                        
                        Button(action: {
                            rememberedTrigger += 1
                            handleRemembered()
                            // 心形播完再切卡，避免动画被截断；切卡前先隐藏心形，不再使用 3.6s 悬空定时器
                            DispatchQueue.main.asyncAfter(deadline: .now() + Self.heartDisplayDuration) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    showHeartAnimation = false
                                }
                                onResult(true)
                                // 不调用 resetCard()，避免当前卡「翻回正面」与切卡动画重叠
                            }
                        }) {
                            HStack {
                                Image(systemName: "checkmark")
                                Text(LocalizedKey.remembered)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .applySensoryFeedback(trigger: rememberedTrigger, style: .solid)
                        .accessibilityLabel(LocalizedKey.remembered.rawValue.localized)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 60) // 为底部导航栏留出空间，同时让按钮更靠近底部
                }
            } else {
                // 在查看模式下，为底部留出一些空间
                Spacer()
                    .frame(height: 20)
            }
        }
        .overlay(alignment: .bottom) {
            // 小红心放在整卡顶层 overlay，避免与顶部「连击」布局冲突或被按钮区域裁剪
            if showHeartAnimation {
                HStack(spacing: 0) {
                    Spacer()
                    VStack(spacing: 0) {
                        Spacer()
                        HeartBurstView()
                            .offset(y: -8)
                        Spacer()
                            .frame(height: 100)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: word.id) { oldValue, newValue in
            // 停止当前播放的语音
            SpeechManager.shared.stopSpeaking()
            resetCard()
        }
        .onDisappear {
            // 视图消失时停止播放
            SpeechManager.shared.stopSpeaking()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    private func handleRemembered() {
        rememberedCombo += 1
        
        // 心形与连击分开动画，避免同一 spring 造成视觉重叠；心形优先、连击稍缓入
        withAnimation(.spring(response: 0.85, dampingFraction: 0.72)) {
            showHeartAnimation = true
        }
        withAnimation(.easeOut(duration: 0.35)) {
            showComboLabel = true
        }
    }
    
    private func resetCard() {
        withAnimation {
            isFlipped = false
        }
    }
    
    @MainActor
    private func updateExample() {
        guard !isUpdatingExample else { return }
        
        isUpdatingExample = true
        updateExampleError = nil
        
        Task {
            do {
                let result = try await DeepseekService.shared.generateNewExample(
                    for: word.term,
                    partOfSpeech: word.partOfSpeech,
                    definition: word.definition,
                    currentExample: word.example  // 传入当前例句，避免生成相似的
                )
                
                word.example = result.example
                word.exampleCn = result.exampleCn
                try? modelContext.save()
            } catch {
                // 检查是否是次数不足的错误
                if let serviceError = error as? DeepseekServiceError,
                   case .noRemainingCalls = serviceError {
                    await MainActor.run {
                        showPaywall = true
                    }
                } else {
                    updateExampleError = error.localizedDescription
                }
            }
            
            isUpdatingExample = false
        }
    }
}

struct CardFront: View {
    let word: Word
    let isFlipped: Bool
    
    @ObservedObject private var speechManager = SpeechManager.shared
    @State private var playButtonTrigger: Int = 0
    
    var body: some View {
        VStack(spacing: 24) {
            Text(isFlipped ? LocalizedKey.answer.rawValue.localized : LocalizedKey.question.rawValue.localized)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.tint.opacity(0.1))
                .clipShape(Capsule())
            
            Text(word.term)
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(.primary)
            
            HStack(spacing: 12) {
                Text(word.pronunciation.isEmpty ? "/.../" : word.pronunciation)
                    .font(.subheadline)
                    .fontDesign(.serif)
                    .foregroundStyle(.secondary)
                    .italic()
                
                // 播放按钮
                Button(action: {
                    playButtonTrigger += 1
                    speechManager.speak(word.term, language: "en-US")
                }) {
                    Image(systemName: speechManager.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(.tint.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .applySensoryFeedback(trigger: playButtonTrigger, style: .soft)
                .accessibilityLabel(LocalizedKey.playPronunciation.rawValue.localized)
            }
            
            Spacer()
            
            Text(LocalizedKey.clickToFlip)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(LocalizedKey.question.rawValue.localized)：\(word.term)，\(word.pronunciation.isEmpty ? "/.../" : word.pronunciation)")
    }
}

struct CardBack: View {
    let word: Word
    let isUpdatingExample: Bool
    let onUpdateExample: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(word.partOfSpeech)
                    .font(.subheadline)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(.white.opacity(0.9))
                
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 4, height: 4)
                
                Text(word.pronunciation)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Text(word.definition)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(word.example)
                    .font(.headline)
                    .foregroundStyle(.white)
                
                Text(word.exampleCn)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            // Ai 更新例句按钮
            Button(action: {
                onUpdateExample()
            }) {
                HStack {
                    if isUpdatingExample {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    Text(LocalizedKey.aiUpdateExample)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isUpdatingExample)
            .accessibilityLabel(LocalizedKey.aiUpdateExample.rawValue.localized)
            
            // 词根 & 近义词 / 反义词（放在卡片底部辅助信息区域）
            if !word.root.isEmpty || !word.synonyms.isEmpty || !word.antonyms.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !word.root.isEmpty {
                        Text("词根：\(word.root)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if !word.synonyms.isEmpty {
                        Text("近义词：\(word.synonyms)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if !word.antonyms.isEmpty {
                        Text("反义词：\(word.antonyms)")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "FE6A57"), Color(hex: "FE2E69")]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("答案：\(word.term)，\(word.partOfSpeech)，\(word.definition)")
    }
}

struct HeartBurstView: View {
    @State private var animate = false
    
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 40))
            .foregroundStyle(.pink)
            .scaleEffect(animate ? 1.4 : 0.4)
            .opacity(animate ? 0 : 1)
            .offset(y: animate ? -70 : 0)
            .allowsHitTesting(false)
            .onAppear {
                // 约 1s 内完成弹出+上飘+淡出，与 heartDisplayDuration 一致，切卡时动画已收尾
                withAnimation(.easeInOut(duration: 1.0)) {
                    animate = true
                }
            }
    }
}

// 触觉反馈强度枚举
enum HapticIntensity {
    case soft
    case solid
    case rigid
}

// iOS 17+ 触觉反馈扩展
extension View {
    @ViewBuilder
    func applySensoryFeedback(trigger: Int, style: HapticIntensity) -> some View {
        if #available(iOS 17.0, *) {
            let flexibility: SensoryFeedback.Flexibility = {
                switch style {
                case .soft:
                    return .soft
                case .solid:
                    return .solid
                case .rigid:
                    return .rigid
                }
            }()
            self.sensoryFeedback(.impact(flexibility: flexibility), trigger: trigger)
        } else {
            // iOS 16 及以下版本：使用 UIKit 触觉反馈
            self.onChange(of: trigger) { _ in
                let uikitStyle: UIImpactFeedbackGenerator.FeedbackStyle = {
                    switch style {
                    case .soft:
                        return .light
                    case .solid:
                        return .medium
                    case .rigid:
                        return .heavy
                    }
                }()
                let generator = UIImpactFeedbackGenerator(style: uikitStyle)
                generator.impactOccurred()
            }
        }
    }
}
