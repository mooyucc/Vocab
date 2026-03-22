//
//  WordSupplementView.swift
//  Vocab
//
//  一键更新/补充词根、近义词、反义词、例句（按当前学习语言），带进度条
//  仅更新：缺少内容 或 内容与学习语言不一致 的单词
//

import SwiftUI
import SwiftData

// MARK: - 学习语言与内容一致性检测（基于字符脚本）

private enum LearningLanguageScript {
    case latinBased   // 英语、法语、西班牙语等
    case cjk          // 简体/繁体中文
    case japanese     // 日语（平假名/片假名/汉字）
    case korean       // 韩语（谚文）
    
    static func from(_ language: AppLanguage) -> LearningLanguageScript {
        switch language {
        case .english, .french, .spanish: return .latinBased
        case .chinese, .chineseTraditional: return .cjk
        case .japanese: return .japanese
        case .korean: return .korean
        }
    }
}

private struct ScriptCounts {
    var latin = 0
    var cjk = 0
    var hiraganaKatakana = 0
    var hangul = 0
    var other = 0
    
    static func count(_ text: String) -> ScriptCounts {
        var s = ScriptCounts()
        for scalar in text.unicodeScalars {
            let u = scalar.value
            if (0x0041...0x005A).contains(u) || (0x0061...0x007A).contains(u) || (0x00C0...0x024F).contains(u) {
                s.latin += 1
            } else if (0x4E00...0x9FFF).contains(u) {
                s.cjk += 1
            } else if (0x3040...0x309F).contains(u) || (0x30A0...0x30FF).contains(u) {
                s.hiraganaKatakana += 1
            } else if (0xAC00...0xD7AF).contains(u) {
                s.hangul += 1
            } else if CharacterSet.letters.contains(scalar) || CharacterSet.whitespaces.contains(scalar) || CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                s.other += 1
            }
        }
        return s
    }
    
    /// 内容是否看起来与学习语言一致（空字符串视为一致，不触发更新）
    func appearsInLanguage(_ script: LearningLanguageScript) -> Bool {
        let totalLetter = latin + cjk + hiraganaKatakana + hangul + other
        if totalLetter == 0 { return true }
        switch script {
        case .latinBased:
            // 学习语言为英文等：不应出现大量 CJK/日文/韩文
            let nonLatin = cjk + hiraganaKatakana + hangul
            return nonLatin == 0 || (Double(nonLatin) / Double(totalLetter) < 0.15)
        case .cjk:
            // 学习语言为中文：应有 CJK，且非“几乎全是拉丁”
            if cjk == 0 { return false }
            return Double(latin) / Double(totalLetter) <= 0.6
        case .japanese:
            // 学习语言为日语：应有平假名/片假名/汉字
            if hiraganaKatakana + cjk == 0 { return false }
            return Double(latin) / Double(totalLetter) <= 0.6
        case .korean:
            // 学习语言为韩语：应有谚文
            if hangul == 0 { return false }
            return Double(latin) / Double(totalLetter) <= 0.6
        }
    }
}

private func textAppearsInLearningLanguage(_ text: String, learningLanguage: AppLanguage) -> Bool {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return true }
    let counts = ScriptCounts.count(t)
    return counts.appearsInLanguage(LearningLanguageScript.from(learningLanguage))
}

// MARK: - View

struct WordSupplementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Word.createdAt, order: .reverse) private var allWords: [Word]
    
    @State private var isRunning = false
    @State private var isCompleted = false
    @State private var isCancelled = false
    @State private var currentIndex = 0
    @State private var totalCount = 0
    @State private var errorMessage: String?
    @State private var showPaywall = false
    
    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(currentIndex) / Double(totalCount)
    }
    
/// 需要补充的单词：缺少内容 或 例句/词根/近义词/反义词与学习语言不一致
    private var wordsNeedingSupplement: [Word] {
        let target = AppSettingsManager.shared.targetLanguage
        return allWords.filter { word in
            let missing = word.root.isEmpty || word.synonyms.isEmpty || word.antonyms.isEmpty
            let exampleWrong = !word.example.isEmpty && !textAppearsInLearningLanguage(word.example, learningLanguage: target)
            let rootWrong = !word.root.isEmpty && !textAppearsInLearningLanguage(word.root, learningLanguage: target)
            let synonymsWrong = !word.synonyms.isEmpty && !textAppearsInLearningLanguage(word.synonyms, learningLanguage: target)
            let antonymsWrong = !word.antonyms.isEmpty && !textAppearsInLearningLanguage(word.antonyms, learningLanguage: target)
            return missing || exampleWrong || rootWrong || synonymsWrong || antonymsWrong
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if allWords.isEmpty && !isRunning && !isCompleted {
                    emptyState
                } else if !isRunning && !isCompleted && wordsNeedingSupplement.isEmpty {
                    noUpdateNeededState
                } else if isCompleted {
                    completedState
                } else if let error = errorMessage {
                    errorState(message: error)
                } else if isRunning {
                    progressState
                } else {
                    confirmState
                }
            }
            .padding()
            .navigationTitle(LocalizedKey.supplementRootSynonyms.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isRunning {
                        Button(LocalizedKey.cancel.rawValue.localized) {
                            dismiss()
                        }
                    } else {
                        Button(LocalizedKey.cancel.rawValue.localized) {
                            isCancelled = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(LocalizedKey.supplementNoWords.rawValue.localized)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// 所有单词均已包含词根与近反义词，无需更新
    private var noUpdateNeededState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(LocalizedKey.supplementNoUpdateNeeded.rawValue.localized)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var confirmState: some View {
        let toUpdate = wordsNeedingSupplement
        let toUpdateCount = toUpdate.count
        let totalCount = allWords.count
        return VStack(alignment: .leading, spacing: 20) {
            Text(LocalizedKey.supplementRootSynonymsDescription.rawValue.localized)
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text(String(format: LocalizedKey.supplementCountHint.rawValue.localized, totalCount, toUpdateCount, toUpdateCount))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 20)
            Button {
                startSupplement()
            } label: {
                Text(LocalizedKey.supplementStart.rawValue.localized)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(toUpdateCount == 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var progressState: some View {
        VStack(spacing: 24) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text(String(format: LocalizedKey.supplementProgressFormat.rawValue.localized, currentIndex, totalCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var completedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(LocalizedKey.supplementCompleted.rawValue.localized)
                .font(.headline)
            Button(LocalizedKey.done.rawValue.localized) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(LocalizedKey.done.rawValue.localized) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func startSupplement() {
        let toUpdate = wordsNeedingSupplement
        let count = toUpdate.count
        guard count > 0 else { return }
        totalCount = count
        isRunning = true
        isCancelled = false
        errorMessage = nil
        currentIndex = 0
        
        Task {
            for index in 0..<count {
                if isCancelled { break }
                let word = toUpdate[index]
                do {
                    let details = try await DeepseekService.shared.generateWordDetails(for: word.term)
                    await MainActor.run {
                        word.example = details.example
                        word.exampleCn = details.exampleCn
                        word.root = details.root ?? ""
                        word.synonyms = details.synonyms ?? ""
                        word.antonyms = details.antonyms ?? ""
                        try? modelContext.save()
                        currentIndex = index + 1
                    }
                } catch {
                    await MainActor.run {
                        isRunning = false
                        if let serviceError = error as? DeepseekServiceError,
                           case .noRemainingCalls = serviceError {
                            showPaywall = true
                        } else {
                            errorMessage = error.localizedDescription
                        }
                    }
                    return
                }
            }
            await MainActor.run {
                isRunning = false
                isCompleted = true
            }
        }
    }
}

#Preview {
    WordSupplementView()
        .modelContainer(for: [Word.self, WordSheet.self], inMemory: true)
}
