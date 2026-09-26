//
//  GuessWordGameView.swift
//  Vocab
//
//  推荐复习猜词：字母自动揭开，抢答后输入整词。
//

import SwiftUI
import SwiftData

struct GuessWordGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isSessionActive: Bool
    @Binding var endSessionRequested: Bool
    @Binding var selectedTab: AppView
    
    @Query private var words: [Word]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    
    @FocusState private var isAnswerFocused: Bool
    
    @State private var sessionScreen: SessionScreen = .ready
    @State private var queue: [Word] = []
    @State private var currentIndex = 0
    @State private var units: [GuessLetterUnit] = []
    @State private var pendingReveal: [Int] = []
    @State private var shownIndices: Set<Int> = []
    @State private var phase: RoundPhase = .revealing
    @State private var answer = ""
    @State private var attempts = 0
    @State private var lockedScore: Int?
    @State private var sessionScore = 0
    @State private var combo = 0
    @State private var showCombo = false
    @State private var history: [GuessScoreRecord] = []
    @State private var lastRecord: GuessScoreRecord?
    @State private var didLoadHistory = false
    @State private var showEndConfirm = false
    
    @State private var revealTask: Task<Void, Never>?
    @State private var revealPulse = 0
    @State private var buzzPulse = 0
    @State private var correctPulse = 0
    @State private var errorPulse = 0
    @State private var playPulse = 0
    
    init(
        isSessionActive: Binding<Bool> = .constant(false),
        endSessionRequested: Binding<Bool> = .constant(false),
        selectedTab: Binding<AppView> = .constant(.study)
    ) {
        _isSessionActive = isSessionActive
        _endSessionRequested = endSessionRequested
        _selectedTab = selectedTab
    }
    
    private var dueWords: [Word] {
        SpacedRepetition.dueWords(from: words)
    }
    
    private var emptyHintKey: LocalizedKey {
        if words.isEmpty { return .exerciseEmptyNoWords }
        if !words.contains(where: \.learned) { return .exerciseEmptyAllUnlearned }
        return .exerciseEmptyNoDue
    }
    
    private var currentWord: Word? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }
    
    private var revealableTotal: Int {
        units.filter(\.isRevealable).count
    }
    
    private var revealedCount: Int {
        shownIndices.filter { units.indices.contains($0) && units[$0].isRevealable }.count
    }
    
    private var potentialScore: Int {
        if let lockedScore { return lockedScore }
        return GuessWordRules.score(revealed: revealedCount, total: revealableTotal)
    }
    
    private var sessionMaxScore: Int {
        queue.count * 100
    }
    
    var body: some View {
        let due = dueWords
        let eligibleCount = GuessWordRules.eligibleCount(in: due)
        return NavigationStack {
            Group {
                if due.isEmpty {
                    emptyDueView
                } else if eligibleCount == 0 {
                    emptyEligibleView
                } else {
                    switch sessionScreen {
                    case .ready:
                        readyView(eligibleCount: eligibleCount)
                    case .complete:
                        completedView
                    case .playing:
                        if currentWord != nil {
                            playView
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(LocalizedKey.tabGuess.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sessionScreen == .playing {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(LocalizedKey.exerciseEnd.rawValue.localized) {
                            showEndConfirm = true
                        }
                        .accessibilityLabel(LocalizedKey.exerciseEnd.rawValue.localized)
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(LocalizedKey.cancel.rawValue.localized)
                    }
                }
            }
            .toolbar(phase == .answering && sessionScreen == .playing ? .hidden : .automatic, for: .tabBar)
        }
        .background(Color.vocabCanvas)
        .alert(
            LocalizedKey.guessLeaveTitle.rawValue.localized,
            isPresented: $showEndConfirm
        ) {
            Button(LocalizedKey.guessLeaveConfirm.rawValue.localized) {
                finishSession()
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {}
        } message: {
            Text(LocalizedKey.guessLeaveMessage)
        }
        .onAppear {
            if !didLoadHistory {
                reloadHistory()
                didLoadHistory = true
            }
            resumeRevealIfNeeded()
        }
        .onChange(of: endSessionRequested) { _, requested in
            guard requested else { return }
            endSessionRequested = false
            finishSession()
        }
        .onDisappear {
            cancelReveal()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                resumeRevealIfNeeded()
            } else {
                cancelReveal()
            }
        }
    }
    
    // MARK: - Empty
    
    @ViewBuilder
    private var emptyDueView: some View {
        if words.isEmpty {
            EmptyLibraryPrompt(
                title: LocalizedKey.tabGuess.rawValue.localized,
                systemImage: "puzzlepiece.extension"
            ) {
                selectedTab = .list
                dismiss()
            }
        } else {
            ContentUnavailableView {
                Label(LocalizedKey.tabGuess.rawValue.localized, systemImage: "puzzlepiece.extension")
            } description: {
                Text(emptyHintKey)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var emptyEligibleView: some View {
        ContentUnavailableView {
            Label(LocalizedKey.tabGuess.rawValue.localized, systemImage: "puzzlepiece.extension")
        } description: {
            Text(LocalizedKey.guessEmptyNoEligible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func readyView(eligibleCount: Int) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            
            Text(LocalizedKey.guessReadyRules)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            Button(action: startSession) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient.vocabGoldProgress)
                            .frame(width: 128, height: 128)
                            .shadow(color: Color.vocabGold.opacity(0.4), radius: 16, x: 0, y: 8)
                        VStack(spacing: 6) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 34, weight: .semibold))
                            Text(LocalizedKey.guessStart)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(Color.vocabInk)
                        .padding(.horizontal, 12)
                    }
                    Text("\(eligibleCount)\(LocalizedKey.wordsToReview.rawValue.localized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(VocabPressButtonStyle())
            .accessibilityLabel("\(LocalizedKey.guessStart.rawValue.localized)，\(eligibleCount)\(LocalizedKey.wordsToReview.rawValue.localized)")
            
            if lastRecord != nil || !history.isEmpty {
                historyBlock
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var historyBlock: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let last = lastRecord {
                    scoreStatCard(
                        title: LocalizedKey.guessLastScore.rawValue.localized,
                        score: last.score,
                        maxScore: last.maxScore
                    )
                }
                if let best = history.first {
                    scoreStatCard(
                        title: LocalizedKey.guessBestScore.rawValue.localized,
                        score: best.score,
                        maxScore: best.maxScore
                    )
                }
            }
            
            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedKey.guessRecentScores)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(history) { record in
                                HStack {
                                    Text(DateFormatter.localizedDateString(from: record.date))
                                    Spacer()
                                    Text("\(record.score) / \(record.maxScore)")
                                        .monospacedDigit()
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vocabSurface)
        .clipShape(RoundedRectangle(cornerRadius: VocabTheme.Radius.card, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(LocalizedKey.guessRecentScores.rawValue.localized)
            }
        }
        .padding(.top, 8)
    }
    
    private func scoreStatCard(title: String, score: Int, maxScore: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(String(format: LocalizedKey.guessCompletedScore.rawValue.localized, score, maxScore))
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .background(Color.vocabGold.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: VocabTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(String(format: LocalizedKey.guessCompletedScore.rawValue.localized, score, maxScore))")
    }
    
    private var completedView: some View {
        ContentUnavailableView {
            Label(LocalizedKey.guessCompletedTitle.rawValue.localized, systemImage: "flag.checkered")
        } description: {
            Text(String(format: LocalizedKey.guessCompletedScore.rawValue.localized, sessionScore, sessionMaxScore))
        } actions: {
            Button {
                startSession()
            } label: {
                Text(LocalizedKey.guessPlayAgain)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vocabBrand)
            .controlSize(.regular)
            
            Button {
                returnToReady()
            } label: {
                Text(LocalizedKey.done)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Play
    
    private var playView: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
            
            VStack(spacing: 20) {
                Spacer(minLength: 8)
                definitionBlock
                letterBoard
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(boardAccessibilityLabel)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 20)
            
            if phase == .revealing {
                revealingActions
            } else if phase == .resolved {
                resolvedActions
            }
        }
        .safeAreaInset(edge: .bottom) {
            if phase == .answering {
                answeringBar
            }
        }
        .applySensoryFeedback(trigger: revealPulse, style: .soft)
        .applySensoryFeedback(trigger: buzzPulse, style: .solid)
        .applySensoryFeedback(trigger: playPulse, style: .soft)
        .modifier(GuessResultFeedback(correctTrigger: correctPulse, errorTrigger: errorPulse))
    }
    
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(format: LocalizedKey.sessionProgress.rawValue.localized, currentIndex + 1, queue.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            
            Spacer(minLength: 0)
            
            if showCombo && combo > 1 {
                Text(String(format: LocalizedKey.comboStreak.rawValue.localized, combo))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.vocabGold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.vocabGold.opacity(0.16))
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            
            Text("\(potentialScore)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.vocabGold)
                .contentTransition(.numericText())
                .accessibilityLabel(
                    String(format: LocalizedKey.guessPotentialScoreA11y.rawValue.localized, potentialScore)
                )
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .snappy, value: potentialScore)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.7), value: showCombo)
    }
    
    @ViewBuilder
    private var definitionBlock: some View {
        if let word = currentWord {
            VStack(spacing: 8) {
                if !word.partOfSpeech.isEmpty {
                    Text(word.partOfSpeech)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(word.definition)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .combine)
        }
    }
    
    private var letterBoard: some View {
        let usesMono = GuessWordRules.usesMonospace(units)
        return GuessLetterFlowLayout(spacing: units.count > 12 ? 6 : 8) {
            ForEach(units) { unit in
                letterSlot(unit, usesMono: usesMono)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func letterSlot(_ unit: GuessLetterUnit, usesMono: Bool) -> some View {
        let visible = isVisible(unit)
        let font: Font = {
            if units.count > 14 {
                return usesMono ? .system(.title3, design: .monospaced).weight(.semibold) : .title3.weight(.semibold)
            }
            return usesMono ? .system(.title, design: .monospaced).weight(.semibold) : .title.weight(.semibold)
        }()
        let color: Color = resolvedIsCorrect ? Color.vocabTeal : .primary
        
        let glyphColor: Color = {
            if !unit.isRevealable { return .secondary }
            if !visible { return .clear }
            return color
        }()
        
        return Text(visible || !unit.isRevealable ? String(unit.character) : " ")
            .font(font)
            .foregroundStyle(glyphColor)
            .frame(minWidth: unit.isRevealable ? 22 : 10, minHeight: 40)
            .overlay(alignment: .bottom) {
                if unit.isRevealable {
                    Capsule()
                        .fill(visible ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.4))
                        .frame(height: 2)
                }
            }
    }
    
    private var revealingActions: some View {
        VStack(spacing: 12) {
            Button(action: buzz) {
                Text(LocalizedKey.guessBuzz)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vocabBrand)
            .controlSize(.regular)
            .accessibilityLabel(LocalizedKey.guessBuzz.rawValue.localized)
            .accessibilityHint(LocalizedKey.guessBuzzHint.rawValue.localized)
            
            Button(action: skip) {
                Text(LocalizedKey.guessSkip)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel(LocalizedKey.guessSkip.rawValue.localized)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
    
    private var answeringBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attempts > 0 {
                Text(LocalizedKey.guessTryAgain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
            }
            
            HStack(spacing: 10) {
                TextField(LocalizedKey.guessAnswerPlaceholder.rawValue.localized, text: $answer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isAnswerFocused)
                    .onSubmit(submitAnswer)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Color.vocabSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                Button(action: submitAnswer) {
                    Text(LocalizedKey.guessSubmit)
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 72, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.vocabBrand)
                .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            Button(action: skip) {
                Text(LocalizedKey.guessSkip)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }
    
    private var resolvedActions: some View {
        VStack(spacing: 12) {
            if let word = currentWord {
                HStack(spacing: 10) {
                    Text(resolvedTitle)
                        .font(.headline)
                        .foregroundStyle(resolvedIsCorrect ? Color.vocabTeal : Color.primary)
                    
                    GuessSpeakButton(term: word.term) {
                        playPulse += 1
                    }
                }
                
                if !resolvedIsCorrect {
                    Text(String(format: LocalizedKey.exerciseCorrectAnswer.rawValue.localized, word.term))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Button(action: goNext) {
                Text(LocalizedKey.guessNext)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vocabBrand)
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
    
    private var resolvedIsCorrect: Bool {
        (lockedScore ?? 0) > 0 && attempts < GuessWordRules.maxAttempts && phase == .resolved
    }
    
    private var resolvedTitle: String {
        resolvedIsCorrect
            ? LocalizedKey.guessCorrect.rawValue.localized
            : LocalizedKey.guessWrong.rawValue.localized
    }
    
    private var boardAccessibilityLabel: String {
        if phase == .revealing {
            return String(format: LocalizedKey.guessRevealedA11y.rawValue.localized, revealedCount)
        }
        return currentWord?.term ?? ""
    }
    
    // MARK: - Session
    
    private func startSession() {
        cancelReveal()
        let eligible = GuessWordRules.eligible(from: dueWords)
        queue = Array(eligible.shuffled().prefix(GuessWordRules.maxCount))
        sessionScore = 0
        combo = 0
        showCombo = false
        answer = ""
        attempts = 0
        lockedScore = nil
        isAnswerFocused = false
        guard !queue.isEmpty else {
            sessionScreen = .ready
            isSessionActive = false
            return
        }
        sessionScreen = .playing
        isSessionActive = true
        startRound(at: 0)
    }
    
    private func finishSession() {
        guard sessionScreen == .playing else { return }
        cancelReveal()
        isAnswerFocused = false
        SpeechManager.shared.stopSpeaking()
        GuessScoreStore.append(score: sessionScore, maxScore: max(sessionMaxScore, 100))
        reloadHistory()
        sessionScreen = .complete
        isSessionActive = false
    }
    
    private func returnToReady() {
        cancelReveal()
        isAnswerFocused = false
        isSessionActive = false
        reloadHistory()
        sessionScreen = .ready
    }
    
    private func reloadHistory() {
        history = GuessScoreStore.load()
        lastRecord = GuessScoreStore.last()
    }
    
    private func startRound(at index: Int) {
        cancelReveal()
        currentIndex = index
        let term = queue[index].term
        units = GuessWordRules.units(for: term)
        pendingReveal = units.indices.filter { units[$0].isRevealable }.shuffled()
        shownIndices = []
        phase = .revealing
        answer = ""
        attempts = 0
        lockedScore = nil
        isAnswerFocused = false
        startRevealLoop(isResume: false)
    }
    
    private func resumeRevealIfNeeded() {
        guard sessionScreen == .playing, phase == .revealing, currentWord != nil else { return }
        guard revealTask == nil else { return }
        startRevealLoop(isResume: revealedCount > 0)
    }
    
    // MARK: - Reveal
    
    private func startRevealLoop(isResume: Bool) {
        revealTask?.cancel()
        revealTask = Task { @MainActor in
            do {
                if !isResume {
                    try await Task.sleep(for: .milliseconds(GuessWordRules.initialDelayMs))
                }
                while !Task.isCancelled {
                    guard phase == .revealing else { return }
                    guard let next = pendingReveal.first else {
                        try await Task.sleep(for: .milliseconds(400))
                        guard phase == .revealing else { return }
                        finishUnanswered()
                        return
                    }
                    revealLetter(next)
                    pendingReveal.removeFirst()
                    if pendingReveal.isEmpty {
                        try await Task.sleep(for: .milliseconds(450))
                        guard phase == .revealing else { return }
                        finishUnanswered()
                        return
                    }
                    try await Task.sleep(for: .milliseconds(
                        GuessWordRules.revealDelayMs(revealed: revealedCount, total: revealableTotal)
                    ))
                }
            } catch {}
        }
    }
    
    private func revealLetter(_ index: Int) {
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.3, dampingFraction: 0.72)
        withAnimation(animation) {
            shownIndices.insert(index)
            return
        }
        revealPulse += 1
    }
    
    private func isVisible(_ unit: GuessLetterUnit) -> Bool {
        !unit.isRevealable || shownIndices.contains(unit.id)
    }
    
    // MARK: - Actions
    
    private func buzz() {
        guard phase == .revealing else { return }
        cancelReveal()
        lockedScore = GuessWordRules.score(revealed: revealedCount, total: revealableTotal)
        phase = .answering
        buzzPulse += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            isAnswerFocused = true
        }
    }
    
    private func submitAnswer() {
        guard phase == .answering, let word = currentWord else { return }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if GuessWordRules.matches(trimmed, term: word.term) {
            let earned = lockedScore ?? 0
            sessionScore += earned
            combo += 1
            showCombo = combo > 1
            word.reviewCount += 1
            correctPulse += 1
            revealAll()
            phase = .resolved
            isAnswerFocused = false
        } else {
            attempts += 1
            errorPulse += 1
            if attempts >= GuessWordRules.maxAttempts {
                combo = 0
                showCombo = false
                lockedScore = 0
                revealAll()
                phase = .resolved
                isAnswerFocused = false
            } else {
                answer = ""
            }
        }
    }
    
    private func skip() {
        guard phase == .revealing || phase == .answering else { return }
        cancelReveal()
        combo = 0
        showCombo = false
        lockedScore = 0
        attempts = GuessWordRules.maxAttempts
        revealAll()
        phase = .resolved
        isAnswerFocused = false
    }
    
    private func finishUnanswered() {
        combo = 0
        showCombo = false
        lockedScore = 0
        attempts = GuessWordRules.maxAttempts
        revealAll()
        phase = .resolved
    }
    
    private func revealAll() {
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.32, dampingFraction: 0.78)
        withAnimation(animation) {
            shownIndices = Set(units.indices)
        }
    }
    
    private func goNext() {
        guard sessionScreen == .playing, phase == .resolved else { return }
        isAnswerFocused = false
        answer = ""
        let next = currentIndex + 1
        if next >= queue.count {
            finishSession()
        } else {
            startRound(at: next)
        }
    }
    
    private func cancelReveal() {
        revealTask?.cancel()
        revealTask = nil
    }
}

// MARK: - Rules

private enum SessionScreen {
    case ready
    case playing
    case complete
}

private enum RoundPhase {
    case revealing
    case answering
    case resolved
}

private struct GuessLetterUnit: Identifiable {
    let id: Int
    let character: Character
    let isRevealable: Bool
}

@MainActor
private enum GuessScoreStore {
    private static let historyKey = "guessScoreHistory"
    private static let lastKey = "guessScoreLast"
    private static let limit = 10
    
    static func load() -> [GuessScoreRecord] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let records = try? JSONDecoder().decode([GuessScoreRecord].self, from: data) else {
            return []
        }
        return ranked(records)
    }
    
    static func last() -> GuessScoreRecord? {
        if let data = UserDefaults.standard.data(forKey: lastKey),
           let record = try? JSONDecoder().decode(GuessScoreRecord.self, from: data) {
            return record
        }
        return load().max(by: { $0.date < $1.date })
    }
    
    static func append(score: Int, maxScore: Int) {
        let record = GuessScoreRecord(id: UUID(), date: Date(), score: score, maxScore: maxScore)
        if let lastData = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(lastData, forKey: lastKey)
        }
        var records = load()
        records.append(record)
        records = Array(ranked(records).prefix(limit))
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    private static func ranked(_ records: [GuessScoreRecord]) -> [GuessScoreRecord] {
        records.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.date > rhs.date
        }
    }
}

private struct GuessScoreRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let score: Int
    let maxScore: Int
}

@MainActor
private enum GuessWordRules {
    static let maxCount = 10
    static let minRevealable = 3
    static let maxAttempts = 2
    static let initialDelayMs = 1400
    
    static func eligible(from words: [Word]) -> [Word] {
        words.filter(isEligible)
    }
    
    static func eligibleCount(in words: [Word]) -> Int {
        var count = 0
        for word in words where isEligible(word) {
            count += 1
        }
        return count
    }
    
    static func isEligible(_ word: Word) -> Bool {
        let term = word.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !term.contains(where: \.isWhitespace) else { return false }
        let definition = word.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !definition.isEmpty else { return false }
        var revealable = 0
        for character in term where character.isLetter || character.isNumber {
            revealable += 1
            if revealable >= minRevealable { return true }
        }
        return false
    }
    
    static func units(for term: String) -> [GuessLetterUnit] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.enumerated().map { index, character in
            GuessLetterUnit(
                id: index,
                character: character,
                isRevealable: character.isLetter || character.isNumber
            )
        }
    }
    
    static func score(revealed: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        let unrevealed = max(0, total - revealed)
        return Int((100.0 * Double(unrevealed) / Double(total)).rounded())
    }
    
    static func revealDelayMs(revealed: Int, total: Int) -> Int {
        let progress = Double(revealed) / Double(max(total, 1))
        var seconds = 1.4 - 0.7 * progress
        if total <= 4 {
            seconds *= 1.35
        } else if total >= 10 {
            seconds *= 0.85
        }
        return max(650, Int((seconds * 1000).rounded()))
    }
    
    static func matches(_ input: String, term: String) -> Bool {
        input.compare(
            term.trimmingCharacters(in: .whitespacesAndNewlines),
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
    }
    
    static func usesMonospace(_ units: [GuessLetterUnit]) -> Bool {
        let letters = units.filter(\.isRevealable)
        return !letters.isEmpty && letters.allSatisfy { unit in
            unit.character.isASCII && (unit.character.isLetter || unit.character.isNumber)
        }
    }
}

// MARK: - Layout

private struct GuessLetterFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
            subviews: subviews
        )
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y),
                proposal: ProposedViewSize(size)
            )
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

private struct GuessSpeakButton: View {
    let term: String
    var onPlay: () -> Void
    
    @ObservedObject private var speechManager = SpeechManager.shared
    
    var body: some View {
        Button {
            onPlay()
            speechManager.speak(term)
        } label: {
            Image(systemName: speechManager.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(LocalizedKey.playPronunciation.rawValue.localized)
    }
}

private struct GuessResultFeedback: ViewModifier {
    let correctTrigger: Int
    let errorTrigger: Int
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .sensoryFeedback(.success, trigger: correctTrigger)
                .sensoryFeedback(.error, trigger: errorTrigger)
        } else {
            content
                .onChange(of: correctTrigger) { _, _ in
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                .onChange(of: errorTrigger) { _, _ in
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Word.self, WordSheet.self, configurations: config)
    let word = Word(
        term: "elephant",
        definition: "一种大型哺乳动物，有长鼻子",
        partOfSpeech: "n.",
        pronunciation: "/ˈelɪfənt/",
        example: "An elephant is walking.",
        exampleCn: "一头大象在走路。",
        learned: true,
        spacedReviewCount: 1,
        spacedLastReviewed: Calendar.current.date(byAdding: .day, value: -2, to: Date())
    )
    container.mainContext.insert(word)
    return GuessWordGameView()
        .modelContainer(container)
}
