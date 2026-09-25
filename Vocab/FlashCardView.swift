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
    let deckLayerCount: Int
    let onResult: (Bool) -> Void
    let showActionButtons: Bool
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFlipped = false
    @State private var forgotTrigger: Int = 0
    @State private var rememberedTrigger: Int = 0
    @State private var thresholdHapticTrigger: Int = 0
    @State private var isUpdatingExample = false
    @State private var updateExampleError: String?
    @State private var showPaywall = false
    
    @State private var dragOffset: CGFloat = 0
    @State private var cardOpacity: Double = 1
    @State private var isCommitting = false
    @State private var didPassThreshold = false
    @State private var commitGeneration = 0
    
    private let swipeMinimumDistance: CGFloat = 16
    private let swipeLockDistance: CGFloat = 10
    
    private var swipeEnabled: Bool {
        showActionButtons && !voiceOverEnabled
    }
    
    init(
        word: Word,
        deckLayerCount: Int = 0,
        onResult: @escaping (Bool) -> Void,
        showActionButtons: Bool = true
    ) {
        self.word = word
        self.deckLayerCount = deckLayerCount
        self.onResult = onResult
        self.showActionButtons = showActionButtons
    }
    
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let cardHeight = geometry.size.height
                ZStack {
                    ForEach(deckDepths, id: \.self) { depth in
                        deckLayer(depth: depth)
                    }
                    
                    ZStack {
                        CardFront(
                            word: word,
                            isFlipped: isFlipped,
                            showsSwipeHint: swipeEnabled
                        )
                        .rotation3DEffect(
                            .degrees(reduceMotion ? 0 : (isFlipped ? 180 : 0)),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .opacity(isFlipped ? 0 : 1)
                        
                        CardBack(
                            word: word,
                            isUpdatingExample: isUpdatingExample,
                            onUpdateExample: updateExample,
                            scrollDisabled: abs(dragOffset) > swipeLockDistance
                        )
                        .rotation3DEffect(
                            .degrees(reduceMotion ? 0 : (isFlipped ? 0 : -180)),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .opacity(isFlipped ? 1 : 0)
                        
                        if swipeEnabled {
                            swipeDecisionOverlay
                                .allowsHitTesting(false)
                        }
                    }
                    .id(word.id)
                    .opacity(cardOpacity)
                    .offset(y: dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset) / 28), anchor: .center)
                    .zIndex(10)
                    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .onTapGesture {
                        guard !isCommitting, abs(dragOffset) < swipeLockDistance else { return }
                        flipCard()
                    }
                    .gesture(
                        swipeGesture(cardHeight: cardHeight),
                        including: swipeEnabled ? .all : .none
                    )
                    .modifier(
                        SwipeReviewAccess(
                            enabled: showActionButtons,
                            onRemembered: { commitResult(remembered: true, cardHeight: cardHeight) },
                            onForgot: { commitResult(remembered: false, cardHeight: cardHeight) }
                        )
                    )
                }
            }
            .padding(.top, deckTopInset)
            .padding(.trailing, deckLayerCount > 0 ? 10 : 0)
            .padding(.bottom, swipeEnabled ? 12 : 0)
            .applySensoryFeedback(trigger: thresholdHapticTrigger, style: .solid)
            
            if showActionButtons && voiceOverEnabled {
                voiceOverActionButtons
            } else if !showActionButtons {
                Spacer()
                    .frame(height: 20)
            }
        }
        .onChange(of: word.id) { _, _ in
            SpeechManager.shared.stopSpeaking()
            resetForNextWord()
        }
        .onDisappear {
            SpeechManager.shared.stopSpeaking()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    // MARK: - Swipe
    
    private func swipeGesture(cardHeight: CGFloat) -> some Gesture {
        let threshold = swipeThreshold(for: cardHeight)
        return DragGesture(minimumDistance: swipeMinimumDistance)
            .onChanged { value in
                guard !isCommitting else { return }
                dragOffset = value.translation.height
                let passed = abs(dragOffset) >= threshold
                if passed != didPassThreshold {
                    didPassThreshold = passed
                    if passed {
                        thresholdHapticTrigger += 1
                    }
                }
            }
            .onEnded { value in
                guard !isCommitting else { return }
                let projected = value.predictedEndTranslation.height
                let threshold = swipeThreshold(for: cardHeight)
                if projected < -threshold {
                    commitResult(remembered: true, cardHeight: cardHeight)
                } else if projected > threshold {
                    commitResult(remembered: false, cardHeight: cardHeight)
                } else {
                    didPassThreshold = false
                    if reduceMotion {
                        dragOffset = 0
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            dragOffset = 0
                        }
                    }
                }
            }
    }
    
    private func swipeThreshold(for cardHeight: CGFloat) -> CGFloat {
        max(100, cardHeight * 0.22)
    }
    
    private var swipeProgress: CGFloat {
        min(1, abs(dragOffset) / 100)
    }
    
    private var stackLift: CGFloat {
        guard swipeEnabled, deckLayerCount > 0, !reduceMotion else { return 0 }
        return min(0.35, abs(dragOffset) / 220)
    }
    
    private var deckDepths: [Int] {
        guard deckLayerCount > 0 else { return [] }
        return Array((1...deckLayerCount).reversed())
    }
    
    /// 叠层向上 offset / scale 不占布局，需预留顶部空间避免盖住进度条
    private var deckTopInset: CGFloat {
        guard deckLayerCount > 0 else { return 0 }
        let depth = CGFloat(deckLayerCount)
        return 8 * depth + 24
    }
    
    private var deckFill: Color {
        colorScheme == .dark
            ? Color(.secondarySystemGroupedBackground)
            : Color.white
    }
    
    private func deckLayer(depth: Int) -> some View {
        let effectiveDepth = CGFloat(depth) - stackLift
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(deckFill)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
            .scaleEffect(1 + 0.028 * effectiveDepth)
            .offset(x: 5 * effectiveDepth, y: -8 * effectiveDepth)
            .opacity(0.72 - 0.18 * Double(depth - 1))
            .zIndex(Double(deckLayerCount - depth))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    
    private var swipeDecisionOverlay: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(swipeTint.opacity(0.16 * swipeProgress))
    }
    
    private var swipeTint: Color {
        if dragOffset < 0 { return .green }
        if dragOffset > 0 { return .red }
        return .clear
    }
    
    private var voiceOverActionButtons: some View {
        HStack(spacing: 16) {
            Button(action: {
                forgotTrigger += 1
                commitResult(remembered: false, cardHeight: 400)
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
                commitResult(remembered: true, cardHeight: 400)
            }) {
                HStack {
                    Image(systemName: "checkmark")
                    Text(LocalizedKey.remembered)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vocabBrand)
            .controlSize(.large)
            .applySensoryFeedback(trigger: rememberedTrigger, style: .solid)
            .accessibilityLabel(LocalizedKey.remembered.rawValue.localized)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 30)
    }
    
    private func commitResult(remembered: Bool, cardHeight: CGFloat) {
        guard !isCommitting else { return }
        isCommitting = true
        
        if remembered {
            rememberedTrigger += 1
        } else {
            forgotTrigger += 1
        }
        
        commitGeneration += 1
        let generation = commitGeneration
        let target = (remembered ? -1.0 : 1.0) * (cardHeight + 140)
        
        if reduceMotion {
            onResult(remembered)
            return
        }
        
        withAnimation(.spring(response: 0.28, dampingFraction: 1.0)) {
            dragOffset = target
            cardOpacity = 0
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard generation == commitGeneration else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dragOffset = 0
                isFlipped = false
            }
            onResult(remembered)
            await Task.yield()
            if generation == commitGeneration {
                resetForNextWord()
            }
        }
    }
    
    private func flipCard() {
        if reduceMotion {
            isFlipped.toggle()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isFlipped.toggle()
            }
        }
    }
    
    private func resetForNextWord() {
        commitGeneration += 1
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isFlipped = false
            isCommitting = false
            didPassThreshold = false
            dragOffset = 0
            cardOpacity = 1
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
                    currentExample: word.example
                )
                
                word.example = result.example
                word.exampleCn = result.exampleCn
                try? modelContext.save()
            } catch {
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
    var showsSwipeHint: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
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
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(3)
            
            HStack(spacing: 12) {
                Text(word.pronunciation.isEmpty ? "/.../" : word.pronunciation)
                    .font(.subheadline)
                    .fontDesign(.serif)
                    .foregroundStyle(.secondary)
                    .italic()
                
                Button(action: {
                    playButtonTrigger += 1
                    speechManager.speak(word.term)
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
            
            VStack(spacing: 6) {
                Text(LocalizedKey.clickToFlip)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
                if showsSwipeHint {
                    Text(LocalizedKey.swipeReviewHint)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.10), lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.45 : 0.14),
            radius: 18,
            x: 0,
            y: 8
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(LocalizedKey.question.rawValue.localized)：\(word.term)，\(word.pronunciation.isEmpty ? "/.../" : word.pronunciation)")
    }
    
    private var cardFill: Color {
        colorScheme == .dark
            ? Color(.secondarySystemGroupedBackground)
            : Color.white
    }
}

struct CardBack: View {
    let word: Word
    let isUpdatingExample: Bool
    let onUpdateExample: () -> Void
    var scrollDisabled: Bool = false
    
    @ObservedObject private var speechManager = SpeechManager.shared
    @State private var readExampleTrigger: Int = 0
    
    private var exampleTextForSpeech: String {
        word.example.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
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
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(word.example)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(word.exampleCn)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if !word.root.isEmpty || !word.synonyms.isEmpty || !word.antonyms.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if !word.root.isEmpty {
                                Text("\(LocalizedKey.root.rawValue.localized)：\(word.root)")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            if !word.synonyms.isEmpty {
                                Text("\(LocalizedKey.synonyms.rawValue.localized)：\(word.synonyms)")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            if !word.antonyms.isEmpty {
                                Text("\(LocalizedKey.antonyms.rawValue.localized)：\(word.antonyms)")
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDisabled(scrollDisabled)
            .scrollBounceBehavior(.basedOnSize)
            .frame(minHeight: 88, maxHeight: .infinity, alignment: .top)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            HStack(spacing: 8) {
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingExample)
                .accessibilityLabel(LocalizedKey.aiUpdateExample.rawValue.localized)
                
                Button(action: {
                    readExampleTrigger += 1
                    speechManager.speak(exampleTextForSpeech)
                }) {
                    HStack {
                        Image(systemName: speechManager.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Text(LocalizedKey.readExampleSentence)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(exampleTextForSpeech.isEmpty)
                .buttonStyle(.plain)
                .applySensoryFeedback(trigger: readExampleTrigger, style: .soft)
                .accessibilityLabel(LocalizedKey.readExampleSentence.rawValue.localized)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(LinearGradient.vocabBrandProgress)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(LocalizedKey.answer.rawValue.localized)：\(word.term)，\(word.partOfSpeech)，\(word.definition)")
    }
}

private struct SwipeReviewAccess: ViewModifier {
    let enabled: Bool
    let onRemembered: () -> Void
    let onForgot: () -> Void
    
    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityHint(LocalizedKey.swipeReviewHint.rawValue.localized)
                .accessibilityAction(named: LocalizedKey.remembered.rawValue.localized, onRemembered)
                .accessibilityAction(named: LocalizedKey.forgot.rawValue.localized, onForgot)
        } else {
            content
        }
    }
}

enum HapticIntensity {
    case soft
    case solid
    case rigid
}

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
