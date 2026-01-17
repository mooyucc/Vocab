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
    
    @Environment(\.modelContext) private var modelContext
    @State private var isFlipped = false
    @State private var forgotTrigger: Int = 0
    @State private var rememberedTrigger: Int = 0
    @State private var isUpdatingExample = false
    @State private var updateExampleError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // 进度指示器
            HStack {
                Text(LocalizedKey.dailyGoal)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(.tint)
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(.tint)
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(.tint.opacity(0.3))
                        .frame(width: 8, height: 8)
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
            HStack(spacing: 16) {
                Button(action: {
                    forgotTrigger += 1
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
                    onResult(true)
                    resetCard()
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
            .padding(.top, 32)
            .padding(.bottom, 100) // 为底部导航栏留出空间
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
                updateExampleError = error.localizedDescription
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
                .font(.system(size: 36, weight: .black, design: .rounded))
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
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
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
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.indigo, Color.purple]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("答案：\(word.term)，\(word.partOfSpeech)，\(word.definition)")
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
