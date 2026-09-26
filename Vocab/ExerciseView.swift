//
//  ExerciseView.swift
//  Vocab
//
//  推荐复习单词的完形填空：默认用词条例句，工具栏可 AI 出新题。
//

import SwiftUI
import SwiftData

struct ExerciseView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isExerciseInProgress: Bool
    @Binding var selectedTab: AppView
    @Query private var words: [Word]
    
    @State private var items: [ClozeItem] = []
    @State private var bankOrder: [UUID] = []
    @State private var fills: [UUID: ClozeFill] = [:]
    @State private var selectedWordId: UUID?
    @State private var isChecked = false
    @State private var score = 0
    
    @State private var showFormPicker = false
    @State private var pendingSentenceId: UUID?
    @State private var pendingWordId: UUID?
    
    @State private var isGenerating = false
    @State private var showPaywall = false
    @State private var showAIReplaceConfirm = false
    @State private var showGenerateError = false
    @State private var generateErrorMessage = ""
    @State private var hasStarted = false
    
    init(
        isExerciseInProgress: Binding<Bool>,
        selectedTab: Binding<AppView> = .constant(.study)
    ) {
        _isExerciseInProgress = isExerciseInProgress
        _selectedTab = selectedTab
    }
    
    private var dueWords: [Word] {
        SpacedRepetition.dueWords(from: words)
    }
    
    private var bankItems: [ClozeItem] {
        bankOrder.compactMap { id in items.first(where: { $0.wordId == id }) }
    }
    
    private var emptyHintKey: LocalizedKey {
        if words.isEmpty { return .exerciseEmptyNoWords }
        if !words.contains(where: \.learned) { return .exerciseEmptyAllUnlearned }
        return .exerciseEmptyNoDue
    }
    
    private var allFilled: Bool {
        !items.isEmpty && fills.count == items.count
    }
    
    private var pendingTerm: String {
        items.first(where: { $0.wordId == pendingWordId })?.term ?? ""
    }
    
    private var pendingForms: [String] {
        items.first(where: { $0.wordId == pendingWordId })?.forms ?? []
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if !hasStarted {
                    if dueWords.isEmpty {
                        emptyDueView
                    } else {
                        startView
                    }
                } else if dueWords.isEmpty && items.isEmpty {
                    emptyDueView
                } else if items.isEmpty && !isGenerating {
                    emptyExamplesView
                } else {
                    exerciseContent
                }
            }
            .navigationTitle(LocalizedKey.tabExercise.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if hasStarted {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(LocalizedKey.exerciseEnd.rawValue.localized) {
                            endExercise()
                        }
                        .accessibilityLabel(LocalizedKey.exerciseEnd.rawValue.localized)
                    }
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {
                            requestAINewSet()
                        } label: {
                            if isGenerating {
                                ProgressView()
                            } else {
                                Image(systemName: "sparkles")
                            }
                        }
                        .disabled(isGenerating || (dueWords.isEmpty && items.isEmpty))
                        .accessibilityLabel(LocalizedKey.exerciseAINewSet.rawValue.localized)
                        .accessibilityHint(LocalizedKey.exerciseAINewSetHint.rawValue.localized)
                        
                        if !items.isEmpty {
                            Button {
                                rebuildLocalSet()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(isGenerating || dueWords.isEmpty)
                            .accessibilityLabel(LocalizedKey.exerciseReshuffle.rawValue.localized)
                        }
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
        }
        .toolbar(isExerciseInProgress ? .hidden : .visible, for: .tabBar)
        .background(Color.vocabCanvas)
        .confirmationDialog(
            String(format: LocalizedKey.exercisePickForm.rawValue.localized, pendingTerm),
            isPresented: $showFormPicker,
            titleVisibility: .visible
        ) {
            ForEach(pendingForms, id: \.self) { form in
                Button(form) {
                    confirmForm(form)
                }
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {
                pendingSentenceId = nil
                pendingWordId = nil
            }
        }
        .confirmationDialog(
            LocalizedKey.exerciseAIReplaceTitle.rawValue.localized,
            isPresented: $showAIReplaceConfirm,
            titleVisibility: .visible
        ) {
            Button(LocalizedKey.exerciseAINewSet.rawValue.localized) {
                Task { await generateAISet() }
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {}
        } message: {
            Text(LocalizedKey.exerciseAIReplaceMessage)
        }
        .alert(LocalizedKey.aiGenerateFailed.rawValue.localized, isPresented: $showGenerateError) {
            Button(LocalizedKey.ok.rawValue.localized, role: .cancel) {}
        } message: {
            Text(generateErrorMessage)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .overlay {
            if isGenerating {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                    ProgressView(LocalizedKey.exerciseGenerating.rawValue.localized)
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(LocalizedKey.exerciseGenerating.rawValue.localized)
            }
        }
    }
    
    // MARK: - Start
    
    private var startView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            
            Text(LocalizedKey.exerciseStartDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            Button(action: startExercise) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient.vocabTealProgress)
                            .frame(width: 128, height: 128)
                            .shadow(color: Color.vocabTeal.opacity(0.35), radius: 16, x: 0, y: 8)
                        VStack(spacing: 6) {
                            Image(systemName: "text.badge.checkmark")
                                .font(.system(size: 34, weight: .semibold))
                            Text(LocalizedKey.exerciseStart)
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                    }
                    Text("\(dueWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(VocabPressButtonStyle())
            .accessibilityLabel("\(LocalizedKey.exerciseStart.rawValue.localized)，\(dueWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty
    
    @ViewBuilder
    private var emptyDueView: some View {
        if words.isEmpty {
            EmptyLibraryPrompt(
                title: LocalizedKey.tabExercise.rawValue.localized,
                systemImage: "text.badge.checkmark"
            ) {
                selectedTab = .list
                dismiss()
            }
        } else {
            ContentUnavailableView {
                Label(LocalizedKey.tabExercise.rawValue.localized, systemImage: "text.badge.checkmark")
            } description: {
                Text(emptyHintKey)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var emptyExamplesView: some View {
        ContentUnavailableView {
            Label(LocalizedKey.tabExercise.rawValue.localized, systemImage: "text.badge.plus")
        } description: {
            Text(LocalizedKey.exerciseEmptyNoExamples)
        } actions: {
            Button {
                requestAINewSet()
            } label: {
                Label(LocalizedKey.exerciseAINewSet.rawValue.localized, systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vocabBrand)
            .controlSize(.large)
            .disabled(isGenerating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Content
    
    private var exerciseContent: some View {
        VStack(spacing: 0) {
            wordBankCard
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)
            
            Divider()
                .opacity(0.5)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        sentenceCard(item: item, index: index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, isChecked ? 16 : 72)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottom) {
                if !isChecked {
                    checkAnswersButton
                }
            }
        }
    }
    
    private var wordBankCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isChecked {
                Text(scoreHeadline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(score == items.count ? Color.vocabTeal : Color.vocabBrand)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            
            WordChipFlowLayout(spacing: 8) {
                ForEach(bankItems) { item in
                    wordChip(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(LocalizedKey.exerciseWordBank.rawValue.localized)
        .accessibilityHint(LocalizedKey.exerciseFillHint.rawValue.localized)
    }
    
    private var scoreHeadline: String {
        if score == items.count {
            return LocalizedKey.exerciseAllCorrect.rawValue.localized
        }
        return String(format: LocalizedKey.exerciseScore.rawValue.localized, score, items.count)
    }
    
    private func wordChip(_ item: ClozeItem) -> some View {
        let used = isWordUsed(item.wordId)
        let selected = selectedWordId == item.wordId
        return Button {
            handleWordTap(item)
        } label: {
            Text(item.term)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(chipBackground(used: used, selected: selected))
                .foregroundStyle(used ? Color.secondary : (selected ? Color.white : Color.primary))
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(used || isChecked || isGenerating)
        .opacity(used ? 0.45 : 1)
        .accessibilityLabel(item.term)
        .accessibilityAddTraits(.isButton)
    }
    
    @ViewBuilder
    private func chipBackground(used: Bool, selected: Bool) -> some View {
        if selected {
            Color.vocabTeal
        } else if used {
            Color.secondary.opacity(0.12)
        } else {
            Color.vocabSurface
        }
    }
    
    private func sentenceCard(item: ClozeItem, index: Int) -> some View {
        let fill = fills[item.wordId]
        let correct = isChecked && isCorrect(item)
        let wrong = isChecked && fill != nil && !isCorrect(item)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1).")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 22, alignment: .leading)
                
                clozeSentence(item: item, fill: fill, correct: correct, wrong: wrong)
            }
            
            if wrong {
                Text(String(format: LocalizedKey.exerciseCorrectAnswer.rawValue.localized, item.answer))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.leading, 30)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vocabSurface)
        .clipShape(RoundedRectangle(cornerRadius: VocabTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sentenceAccessibility(item: item, index: index, fill: fill))
        .accessibilityHint(LocalizedKey.exerciseFillHint.rawValue.localized)
        .accessibilityAddTraits(.isButton)
    }
    
    private func clozeSentence(item: ClozeItem, fill: ClozeFill?, correct: Bool, wrong: Bool) -> some View {
        let parts = item.blankedSentence.components(separatedBy: ClozeBuilder.blank)
        let before = parts.first ?? ""
        let after = parts.count > 1 ? parts.dropFirst().joined(separator: ClozeBuilder.blank) : ""
        let blankText = fill?.form ?? ClozeBuilder.blank
        let blankColor: Color = {
            if correct { return Color.vocabTeal }
            if wrong { return Color.vocabBrand }
            if fill != nil { return Color.vocabTeal }
            return Color.vocabTeal
        }()
        
        return Button {
            handleBlankTap(item)
        } label: {
            (
                Text(before).foregroundStyle(.primary)
                + Text(blankText)
                    .fontWeight(.semibold)
                    .foregroundColor(blankColor)
                    .underline(fill == nil)
                + Text(after).foregroundStyle(.primary)
            )
            .font(.body)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }
    
    private func sentenceAccessibility(item: ClozeItem, index: Int, fill: ClozeFill?) -> String {
        let filled = fill?.form ?? ClozeBuilder.blank
        let sentence = item.blankedSentence.replacingOccurrences(of: ClozeBuilder.blank, with: filled)
        return "\(index + 1). \(sentence)"
    }
    
    // MARK: - Check button
    
    private var checkAnswersButton: some View {
        Button(action: checkAnswers) {
            Label(LocalizedKey.exerciseCheck.rawValue.localized, systemImage: "checkmark")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.vocabTeal)
        .controlSize(.regular)
        .disabled(!allFilled || isGenerating)
        .padding(.horizontal, 32)
        .padding(.bottom, 12)
        .accessibilityLabel(LocalizedKey.exerciseCheck.rawValue.localized)
    }
    
    // MARK: - Actions
    
    private func isWordUsed(_ wordId: UUID) -> Bool {
        fills.values.contains(where: { $0.wordId == wordId })
    }
    
    private func isCorrect(_ item: ClozeItem) -> Bool {
        guard let fill = fills[item.wordId] else { return false }
        return fill.form.compare(item.answer, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
    
    private func handleWordTap(_ item: ClozeItem) {
        guard !isChecked, !isGenerating else { return }
        guard !isWordUsed(item.wordId) else { return }
        if selectedWordId == item.wordId {
            selectedWordId = nil
        } else {
            selectedWordId = item.wordId
        }
    }
    
    private func handleBlankTap(_ sentence: ClozeItem) {
        guard !isChecked, !isGenerating else { return }
        if fills[sentence.wordId] != nil {
            fills[sentence.wordId] = nil
            return
        }
        guard let selectedId = selectedWordId,
              let selectedItem = items.first(where: { $0.wordId == selectedId }) else {
            return
        }
        
        if selectedItem.needsFormPicker {
            pendingSentenceId = sentence.wordId
            pendingWordId = selectedId
            showFormPicker = true
        } else {
            fills[sentence.wordId] = ClozeFill(wordId: selectedId, form: selectedItem.term)
            selectedWordId = nil
        }
    }
    
    private func confirmForm(_ form: String) {
        guard let sentenceId = pendingSentenceId, let wordId = pendingWordId else { return }
        fills[sentenceId] = ClozeFill(wordId: wordId, form: form)
        selectedWordId = nil
        pendingSentenceId = nil
        pendingWordId = nil
    }
    
    private func checkAnswers() {
        guard allFilled, !isChecked else { return }
        score = items.filter { isCorrect($0) }.count
        isChecked = true
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(score == items.count ? .success : .warning)
    }
    
    private func applyItems(_ newItems: [ClozeItem]) {
        items = newItems
        bankOrder = newItems.map(\.wordId).shuffled()
        fills = [:]
        selectedWordId = nil
        isChecked = false
        score = 0
        pendingSentenceId = nil
        pendingWordId = nil
    }
    
    private func startExercise() {
        hasStarted = true
        isExerciseInProgress = true
        rebuildLocalSet()
    }
    
    private func endExercise() {
        hasStarted = false
        isExerciseInProgress = false
        isGenerating = false
        applyItems([])
    }
    
    private func rebuildLocalSet() {
        let built = ClozeBuilder.localItems(from: dueWords)
        applyItems(built)
    }
    
    private var sourceWordsForAI: [Word] {
        if !items.isEmpty {
            let mapped = items.compactMap { item in words.first(where: { $0.id == item.wordId }) }
            if !mapped.isEmpty { return mapped }
        }
        return Array(dueWords.shuffled().prefix(ClozeBuilder.maxCount))
    }
    
    private func requestAINewSet() {
        guard !isGenerating else { return }
        guard !dueWords.isEmpty || !items.isEmpty else { return }
        if !fills.isEmpty || isChecked {
            showAIReplaceConfirm = true
        } else {
            Task { await generateAISet() }
        }
    }
    
    @MainActor
    private func generateAISet() async {
        let source = sourceWordsForAI
        guard !source.isEmpty else { return }
        isGenerating = true
        defer { isGenerating = false }
        
        do {
            let inputs = source.map {
                ClozeWordInput(
                    term: $0.term,
                    partOfSpeech: $0.partOfSpeech,
                    definition: $0.definition,
                    currentExample: $0.example
                )
            }
            let generated = try await DeepseekService.shared.generateClozeSet(for: inputs)
            var unused = source
            var result: [ClozeItem] = []
            for generatedItem in generated {
                guard let index = unused.firstIndex(where: {
                    $0.term.compare(generatedItem.term, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) else { continue }
                let word = unused.remove(at: index)
                if let item = ClozeBuilder.item(
                    fromAI: word,
                    sentence: generatedItem.sentence,
                    answer: generatedItem.answer,
                    translation: generatedItem.translation,
                    forms: generatedItem.forms ?? []
                ) {
                    result.append(item)
                }
            }
            guard !result.isEmpty else {
                generateErrorMessage = LocalizedKey.exerciseAIParseFailed.rawValue.localized
                showGenerateError = true
                return
            }
            applyItems(result.shuffled())
        } catch {
            if let serviceError = error as? DeepseekServiceError, case .noRemainingCalls = serviceError {
                showPaywall = true
            } else {
                generateErrorMessage = error.localizedDescription
                showGenerateError = true
            }
        }
    }
}

// MARK: - Models

private struct ClozeFill {
    let wordId: UUID
    let form: String
}

private struct ClozeItem: Identifiable {
    var id: UUID { wordId }
    let wordId: UUID
    let term: String
    let blankedSentence: String
    let translation: String
    let answer: String
    let forms: [String]
    
    var needsFormPicker: Bool {
        Set(forms.map { $0.lowercased() }).count > 1 &&
        answer.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    }
}

private enum ClozeBuilder {
    static let blank = "______"
    static let maxCount = 10
    
    private struct SurfaceMatch {
        let form: String
        let range: Range<String.Index>
    }
    
    static func localItems(from words: [Word]) -> [ClozeItem] {
        var items: [ClozeItem] = []
        for word in words.shuffled() {
            guard items.count < maxCount else { break }
            if let item = localItem(from: word) {
                items.append(item)
            }
        }
        return items
    }
    
    static func localItem(from word: Word) -> ClozeItem? {
        let term = word.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let example = word.example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !example.isEmpty else { return nil }
        guard let match = findSurfaceForm(in: example, term: term) else { return nil }
        var blanked = example
        blanked.replaceSubrange(match.range, with: blank)
        return ClozeItem(
            wordId: word.id,
            term: term,
            blankedSentence: blanked,
            translation: word.exampleCn.trimmingCharacters(in: .whitespacesAndNewlines),
            answer: match.form,
            forms: forms(term: term, answer: match.form, partOfSpeech: word.partOfSpeech)
        )
    }
    
    static func item(
        fromAI word: Word,
        sentence: String,
        answer: String,
        translation: String,
        forms incomingForms: [String]
    ) -> ClozeItem? {
        let term = word.term.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !trimmedSentence.isEmpty, !trimmedAnswer.isEmpty else { return nil }
        
        let match: SurfaceMatch
        if let found = findExactForm(in: trimmedSentence, form: trimmedAnswer) {
            match = found
        } else if let found = findSurfaceForm(in: trimmedSentence, term: term) {
            match = found
        } else {
            return nil
        }
        
        var blanked = trimmedSentence
        blanked.replaceSubrange(match.range, with: blank)
        
        var merged = incomingForms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        merged.append(contentsOf: [term, match.form])
        
        return ClozeItem(
            wordId: word.id,
            term: term,
            blankedSentence: blanked,
            translation: translation.trimmingCharacters(in: .whitespacesAndNewlines),
            answer: match.form,
            forms: uniqued(merged)
        )
    }
    
    static func forms(term: String, answer: String, partOfSpeech: String) -> [String] {
        var result = [term, answer]
        if containsCJK(term) {
            return uniqued(result)
        }
        let pos = partOfSpeech.lowercased()
        if isVerb(pos) {
            result.append(contentsOf: englishVerbForms(term))
        } else if isNoun(pos) {
            result.append(englishPlural(term))
        } else if isAdjective(pos) {
            result.append(contentsOf: englishAdjForms(term))
        } else {
            result.append(contentsOf: englishVerbForms(term))
            result.append(englishPlural(term))
        }
        return Array(uniqued(result).prefix(5))
    }
    
    private static func findSurfaceForm(in sentence: String, term: String) -> SurfaceMatch? {
        if containsCJK(term) || containsCJK(sentence) {
            if let range = sentence.range(of: term, options: .caseInsensitive) {
                return SurfaceMatch(form: String(sentence[range]), range: range)
            }
            return nil
        }
        if let exact = findExactForm(in: sentence, form: term) {
            return exact
        }
        let pattern = #"[\p{L}\p{M}0-9']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsrange = NSRange(sentence.startIndex..., in: sentence)
        for match in regex.matches(in: sentence, range: nsrange) {
            guard let range = Range(match.range, in: sentence) else { continue }
            let token = String(sentence[range])
            if isLikelyInflection(token, of: term) {
                return SurfaceMatch(form: token, range: range)
            }
        }
        return nil
    }
    
    private static func findExactForm(in sentence: String, form: String) -> SurfaceMatch? {
        if containsCJK(form) {
            if let range = sentence.range(of: form, options: .caseInsensitive) {
                return SurfaceMatch(form: String(sentence[range]), range: range)
            }
            return nil
        }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: form) + "\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsrange = NSRange(sentence.startIndex..., in: sentence)
        guard let match = regex.firstMatch(in: sentence, range: nsrange),
              let range = Range(match.range, in: sentence) else {
            return nil
        }
        return SurfaceMatch(form: String(sentence[range]), range: range)
    }
    
    private static func isLikelyInflection(_ token: String, of term: String) -> Bool {
        let t = token.lowercased()
        let w = term.lowercased()
        if t == w { return true }
        guard w.count >= 2 else { return t.hasPrefix(w) }
        if t.hasPrefix(w), t.count - w.count <= 4 { return true }
        if w.hasSuffix("e") {
            let stem = String(w.dropLast())
            if t.hasPrefix(stem), t.count - stem.count <= 4 { return true }
        }
        if w.hasSuffix("y"), let last = w.dropLast().last, !"aeiou".contains(last) {
            let stem = String(w.dropLast())
            if t == stem + "ies" || t == stem + "ied" || t == stem + "ier" || t == stem + "iest" {
                return true
            }
        }
        return false
    }
    
    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3040...0x30FF).contains(scalar.value)
            || (0xAC00...0xD7AF).contains(scalar.value)
        }
    }
    
    private static func isVerb(_ pos: String) -> Bool {
        let p = pos.replacingOccurrences(of: " ", with: "")
        return p.hasPrefix("v.") || p.hasPrefix("vt") || p.hasPrefix("vi") || p.contains("verb")
    }
    
    private static func isNoun(_ pos: String) -> Bool {
        let p = pos.replacingOccurrences(of: " ", with: "")
        return p.hasPrefix("n.") || p.contains("noun")
    }
    
    private static func isAdjective(_ pos: String) -> Bool {
        pos.contains("adj")
    }
    
    private static func englishVerbForms(_ term: String) -> [String] {
        let lower = term.lowercased()
        var result: [String] = []
        if lower.hasSuffix("s") || lower.hasSuffix("x") || lower.hasSuffix("z")
            || lower.hasSuffix("ch") || lower.hasSuffix("sh") {
            result.append(term + "es")
        } else if lower.hasSuffix("y"), let last = lower.dropLast().last, !"aeiou".contains(last) {
            result.append(String(term.dropLast()) + "ies")
        } else {
            result.append(term + "s")
        }
        if lower.hasSuffix("ie") {
            result.append(String(term.dropLast(2)) + "ying")
        } else if lower.hasSuffix("e"), !lower.hasSuffix("ee") {
            result.append(String(term.dropLast()) + "ing")
        } else {
            result.append(term + "ing")
        }
        if lower.hasSuffix("e") {
            result.append(term + "d")
        } else if lower.hasSuffix("y"), let last = lower.dropLast().last, !"aeiou".contains(last) {
            result.append(String(term.dropLast()) + "ied")
        } else {
            result.append(term + "ed")
        }
        return result
    }
    
    private static func englishPlural(_ term: String) -> String {
        let lower = term.lowercased()
        if lower.hasSuffix("s") || lower.hasSuffix("x") || lower.hasSuffix("z")
            || lower.hasSuffix("ch") || lower.hasSuffix("sh") {
            return term + "es"
        }
        if lower.hasSuffix("y"), let last = lower.dropLast().last, !"aeiou".contains(last) {
            return String(term.dropLast()) + "ies"
        }
        return term + "s"
    }
    
    private static func englishAdjForms(_ term: String) -> [String] {
        let lower = term.lowercased()
        if lower.hasSuffix("y"), let last = lower.dropLast().last, !"aeiou".contains(last) {
            let stem = String(term.dropLast())
            return [stem + "ier", stem + "iest"]
        }
        if lower.hasSuffix("e") {
            return [term + "r", term + "st"]
        }
        return [term + "er", term + "est"]
    }
    
    private static func uniqued(_ forms: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for form in forms where !form.isEmpty {
            let key = form.lowercased()
            if seen.insert(key).inserted {
                result.append(form)
            }
        }
        return result
    }
}

private struct WordChipFlowLayout: Layout {
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
