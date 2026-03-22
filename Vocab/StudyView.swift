//
//  StudyView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

enum ReviewMode {
    case reviewAll      // 复习全部
    case continueLast   // 接着上次复习
    case recommendedReview  // 推荐复习（基于艾宾浩斯遗忘曲线）
}

struct StudyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var words: [Word]
    @Query(sort: \WordSheet.createdAt, order: .reverse) private var allSheets: [WordSheet]
    
    @State private var forgottenWordIds: Set<UUID> = []
    @State private var showReviewAlert = false
    @State private var selectedSheetIds: Set<UUID> = []
    @State private var showSheetPicker = false
    @State private var reviewModeSelected: Bool = false
    @State private var reviewMode: ReviewMode?
    @State private var sessionQueue: [Word] = [] // 当前会话的复习队列
    @State private var isStartingReview: Bool = false // 防止重复点击
    
    // 根据选中的 sheet 过滤单词
    private var filteredWords: [Word] {
        if selectedSheetIds.isEmpty {
            return words
        } else {
            return words.filter { word in
                if let sheetId = word.sheet?.id {
                    return selectedSheetIds.contains(sheetId)
                }
                return false
            }
        }
    }
    
    // 只包含有单词的 sheet（与 WordListView 保持一致）
    private var sheetsWithWords: [WordSheet] {
        allSheets.filter { sheet in
            words.contains { $0.sheet?.id == sheet.id }
        }
    }
    
    // 当前学习队列：直接使用会话队列
    private var studyQueue: [Word] { sessionQueue }
    
    // 所有未学习的单词（包括"忘记了"的）
    private var allUnlearnedWords: [Word] {
        filteredWords.filter { !$0.learned }
    }
    
    /// 「接着上次复习」与 `startReview(mode: .continueLast)` 使用同一队列逻辑
    private var continueLastQueueWords: [Word] {
        filteredWords.filter { !$0.learned || forgottenWordIds.contains($0.id) }
    }
    
    // 根据艾宾浩斯遗忘曲线筛选需要复习的单词（不区分sheet，从全部词库筛选）
    /// 仅对已「记住了」的词；间隔只看「推荐复习」内累计（spacedLastReviewed / spacedReviewCount），与复习全部无关。
    private var recommendedReviewWords: [Word] {
        let now = Date()
        let calendar = Calendar.current
        
        return words.filter { word in
            guard word.learned else { return false }
            
            // 尚未在推荐复习中完成过「记住了」：可进入推荐复习首轮，不参与间隔筛选
            guard let spacedLast = word.spacedLastReviewed else {
                return true
            }
            
            let daysSinceSpaced = calendar.dateComponents([.day], from: spacedLast, to: now).day ?? 0
            let interval = Self.ebbinghausIntervalDays(forSpacedCount: word.spacedReviewCount)
            return daysSinceSpaced >= interval
        }
    }
    
    /// 艾宾浩斯间隔（天）：`count` 为在推荐复习中累计「记住了」的次数（更新后的当前值）
    private static func ebbinghausIntervalDays(forSpacedCount count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1: return 1
        case 2: return 3
        case 3: return 7
        case 4: return 15
        case 5: return 30
        default: return 30
        }
    }
    
    private var selectedSheetName: String {
        if selectedSheetIds.isEmpty {
            return LocalizedKey.allSheets.rawValue.localized
        }
        if selectedSheetIds.count == 1,
           let sheetId = selectedSheetIds.first,
           let sheet = sheetsWithWords.first(where: { $0.id == sheetId }) {
            return sheet.localizedDisplayName
        }
        return LocalizedKey.wordSheet.rawValue.localized
    }
    
    /// 推荐复习不可用时展示的说明（与 `recommendedReviewAccessibilityLabel` 一致）
    private var recommendedReviewEmptyHintKey: LocalizedKey {
        if words.isEmpty { return .recommendedReviewEmptyNoWords }
        if !words.contains(where: \.learned) { return .recommendedReviewEmptyAllUnlearned }
        return .recommendedReviewEmptyNoDue
    }
    
    /// 推荐复习按钮的无障碍标签（禁用时附带原因说明）
    private var recommendedReviewAccessibilityLabel: String {
        let title = LocalizedKey.recommendedReview.rawValue.localized
        let countPart = "\(recommendedReviewWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)"
        if recommendedReviewWords.isEmpty {
            let reason = recommendedReviewEmptyHintKey.rawValue.localized
            return "\(title)，\(countPart)。\(reason)"
        }
        return "\(title)，\(countPart)"
    }
    
    /// 专注模式「选择复习方式」：三张卡片均分可用高度
    private enum ReviewModeCardLayout {
        static let iconSize: CGFloat = 40
        static let contentSpacing: CGFloat = 8
        static let innerVerticalPadding: CGFloat = 12
        static let horizontalPadding: CGFloat = 20
        static let betweenCards: CGFloat = 10
        static let screenHorizontalInset: CGFloat = 24
        static let screenVerticalMargin: CGFloat = 8
        static let cornerRadius: CGFloat = 18
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if !reviewModeSelected {
                    // 初始选择页面：显示两个按钮
                    reviewModeSelectionView
                } else if studyQueue.isEmpty {
                    // 复习完成
                    reviewCompletedView
                } else {
                    // 显示闪卡
                    if let firstWord = studyQueue.first {
                        FlashCardView(
                            word: firstWord,
                            onResult: { remembered in
                                handleReviewResult(wordId: firstWord.id, remembered: remembered)
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
            .navigationTitle(LocalizedKey.focusMode.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showSheetPicker = true
                    }) {
                        HStack(spacing: 4) {
                            Text(selectedSheetName)
                                .font(.subheadline)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .accessibilityLabel(LocalizedKey.selectWordSheet.rawValue.localized)
                }
            }
        }
        .sheet(isPresented: $showSheetPicker) {
            SheetPickerView(
                sheets: sheetsWithWords,
                selectedSheetIds: $selectedSheetIds
            )
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: studyQueue.isEmpty) { oldValue, newValue in
            // 当学习队列为空时，检查是否有"忘记了"的单词
            if newValue && !forgottenWordIds.isEmpty && reviewMode == .continueLast {
                showReviewAlert = true
            }
        }
        .alert(LocalizedKey.reviewPrompt.rawValue.localized, isPresented: $showReviewAlert) {
            Button(LocalizedKey.reviewAgain.rawValue.localized) {
                reviewForgottenWords()
            }
            Button(LocalizedKey.later.rawValue.localized, role: .cancel) {
                // 用户选择稍后再说，不做任何操作
            }
        } message: {
            Text(String(format: "您有 %d 个单词标记为\"%@\"，是否再复习一遍？", forgottenWordIds.count, LocalizedKey.forgot.rawValue.localized))
        }
        .onAppear {
            // 每次切换到背单词tab时，重置状态
            resetReviewState()
        }
    }
    
    // MARK: - Review Mode Selection View
    private var reviewModeSelectionView: some View {
        GeometryReader { proxy in
            let gap = ReviewModeCardLayout.betweenCards
            let vm = ReviewModeCardLayout.screenVerticalMargin
            let usableHeight = max(0, proxy.size.height - vm * 2)
            let cardHeight = (usableHeight - gap * 2) / 3
            
            VStack(spacing: gap) {
                Button(action: {
                    guard !isStartingReview else { return }
                    startReview(mode: .recommendedReview)
                }) {
                    VStack(spacing: ReviewModeCardLayout.contentSpacing) {
                        Spacer(minLength: 0)
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: ReviewModeCardLayout.iconSize))
                            .foregroundStyle(.purple)
                        Text(LocalizedKey.recommendedReview)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(LocalizedKey.recommendedReviewDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if !recommendedReviewWords.isEmpty {
                            Text("\(recommendedReviewWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if recommendedReviewWords.isEmpty && !isStartingReview {
                            Text(recommendedReviewEmptyHintKey)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, ReviewModeCardLayout.innerVerticalPadding)
                    .padding(.horizontal, ReviewModeCardLayout.horizontalPadding)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: ReviewModeCardLayout.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ReviewModeCardLayout.cornerRadius, style: .continuous)
                            .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
                .accessibilityLabel(recommendedReviewAccessibilityLabel)
                .disabled(recommendedReviewWords.isEmpty || isStartingReview)
                .opacity(recommendedReviewWords.isEmpty || isStartingReview ? 0.5 : 1.0)
                
                Button(action: {
                    guard !isStartingReview else { return }
                    startReview(mode: .reviewAll)
                }) {
                    VStack(spacing: ReviewModeCardLayout.contentSpacing) {
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: ReviewModeCardLayout.iconSize))
                            .foregroundStyle(.blue)
                        Text(LocalizedKey.reviewAll)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(LocalizedKey.reviewAllDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if !filteredWords.isEmpty {
                            Text("\(filteredWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, ReviewModeCardLayout.innerVerticalPadding)
                    .padding(.horizontal, ReviewModeCardLayout.horizontalPadding)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: ReviewModeCardLayout.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ReviewModeCardLayout.cornerRadius, style: .continuous)
                            .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
                .accessibilityLabel({
                    let title = LocalizedKey.reviewAll.rawValue.localized
                    let desc = LocalizedKey.reviewAllDescription.rawValue.localized
                    guard !filteredWords.isEmpty else { return "\(title)，\(desc)" }
                    let countPart = "\(filteredWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)"
                    return "\(title)，\(countPart)。\(desc)"
                }())
                .disabled(isStartingReview)
                .opacity(isStartingReview ? 0.5 : 1.0)
                
                Button(action: {
                    guard !isStartingReview else { return }
                    startReview(mode: .continueLast)
                }) {
                    VStack(spacing: ReviewModeCardLayout.contentSpacing) {
                        Spacer(minLength: 0)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: ReviewModeCardLayout.iconSize))
                            .foregroundStyle(.green)
                        Text(LocalizedKey.continueLast)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(LocalizedKey.continueLastDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if !continueLastQueueWords.isEmpty {
                            Text("\(continueLastQueueWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, ReviewModeCardLayout.innerVerticalPadding)
                    .padding(.horizontal, ReviewModeCardLayout.horizontalPadding)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: ReviewModeCardLayout.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ReviewModeCardLayout.cornerRadius, style: .continuous)
                            .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
                .accessibilityLabel({
                    let title = LocalizedKey.continueLast.rawValue.localized
                    let desc = LocalizedKey.continueLastDescription.rawValue.localized
                    guard !continueLastQueueWords.isEmpty else { return "\(title)，\(desc)" }
                    let countPart = "\(continueLastQueueWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)"
                    return "\(title)，\(countPart)。\(desc)"
                }())
                .disabled(isStartingReview)
                .opacity(isStartingReview ? 0.5 : 1.0)
            }
            .padding(.horizontal, ReviewModeCardLayout.screenHorizontalInset)
            .padding(.vertical, vm)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Review Completed View
    private var reviewCompletedView: some View {
        Group {
            if reviewMode == .reviewAll {
                // 复习全部模式完成
                if #available(iOS 17.0, *) {
                    ContentUnavailableView {
                        Label("太棒了！", systemImage: "face.smiling")
                    } description: {
                        Text(LocalizedKey.allWordsReviewed)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint.opacity(0.3))
                        Text("太棒了！所有单词都复习完了")
                            .font(.headline)
                        Text(LocalizedKey.goAddNewWords)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if reviewMode == .recommendedReview {
                // 推荐复习模式完成
                if #available(iOS 17.0, *) {
                    ContentUnavailableView {
                        Label("太棒了！", systemImage: "face.smiling")
                    } description: {
                        Text(LocalizedKey.recommendedReviewCompleted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint.opacity(0.3))
                        Text("太棒了！推荐复习完成")
                            .font(.headline)
                        Text(LocalizedKey.goAddNewWords)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // 接着上次复习模式完成
                if forgottenWordIds.isEmpty {
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView {
                            Label("太棒了！", systemImage: "face.smiling")
                        } description: {
                            Text(LocalizedKey.todayWordsReviewed)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 64))
                                .foregroundStyle(.tint.opacity(0.3))
                            Text("太棒了！今天的单词都背完了")
                                .font(.headline)
                            Text(LocalizedKey.goAddNewWords)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // 有"忘记了"的单词，显示提示
                    if #available(iOS 17.0, *) {
                        VStack(spacing: 24) {
                            ContentUnavailableView {
                                Label(LocalizedKey.roundComplete.rawValue.localized, systemImage: "checkmark.circle")
                            } description: {
                                Text(String(format: "还有 %d %@", forgottenWordIds.count, LocalizedKey.wordsNeedReview.rawValue.localized))
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                reviewForgottenWords()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text(LocalizedKey.reviewAgain)
                                }
                                .frame(maxWidth: 200)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.bottom, 100) // 为底部导航栏留出空间
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 24) {
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.tint.opacity(0.3))
                                Text(LocalizedKey.roundComplete)
                                    .font(.headline)
                                Text(String(format: "还有 %d %@", forgottenWordIds.count, LocalizedKey.wordsNeedReview.rawValue.localized))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                reviewForgottenWords()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text(LocalizedKey.reviewAgain)
                                }
                                .frame(maxWidth: 200)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.bottom, 100) // 为底部导航栏留出空间
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
    
    @MainActor
    private func handleReviewResult(wordId: UUID, remembered: Bool) {
        // 防止并发调用导致的状态冲突
        guard !sessionQueue.isEmpty else { return }
        
        if let word = words.first(where: { $0.id == wordId }) {
            withAnimation {
                // 确保队列不为空再移除
                if !sessionQueue.isEmpty {
                    sessionQueue.removeFirst()
                }
                
                if remembered {
                    // 记住了：标记为已学
                    word.learned = true
                    // 如果之前在"忘记了"列表中，移除它
                    forgottenWordIds.remove(wordId)
                } else {
                    // 忘记了：加入"忘记了"列表，但不重新加入队列
                    // 每个单词在这一轮中只出现一次，不要循环
                    forgottenWordIds.insert(wordId)
                    // 未记住：一律标记为未学，使其不再进入「推荐复习」，可通过「复习全部」「接着上次」巩固
                    word.learned = false
                }
                word.reviewCount += 1
                word.lastReviewed = Date()
                
                // 遗忘曲线仅跟踪「推荐复习」内的「记住了」；复习全部/接着上次不改变 spaced 字段
                if reviewMode == .recommendedReview {
                    if remembered {
                        word.spacedReviewCount += 1
                        word.spacedLastReviewed = Date()
                    } else {
                        word.spacedReviewCount = 0
                        word.spacedLastReviewed = nil
                    }
                }
                
                // 当所有单词都过完一遍后（队列为空），直接返回到选择界面
                if sessionQueue.isEmpty {
                    // 立即重置状态，返回到选择界面
                    reviewModeSelected = false
                    reviewMode = nil
                }
            }
            try? modelContext.save()
        }
    }
    
    @MainActor
    private func reviewForgottenWords() {
        // 将"忘记了"的单词重新加入学习队列
        guard let mode = reviewMode else { return }
        
        withAnimation {
            // 根据当前模式重建队列
            let forgottenWords = filteredWords.filter { forgottenWordIds.contains($0.id) }
            sessionQueue = forgottenWords
            forgottenWordIds.removeAll()
            
            // 如果队列为空，重置状态
            if sessionQueue.isEmpty {
                reviewModeSelected = false
                reviewMode = nil
            }
        }
    }
    
    @MainActor
    private func startReview(mode: ReviewMode) {
        // 防止重复点击
        guard !isStartingReview else { return }
        isStartingReview = true
        
        withAnimation {
            reviewMode = mode
            reviewModeSelected = true
            
            // 初始化会话队列
            switch mode {
            case .reviewAll:
                sessionQueue = filteredWords
                // 复习全部：清空忘记列表，重新开始
                forgottenWordIds.removeAll()
            case .continueLast:
                sessionQueue = continueLastQueueWords
            case .recommendedReview:
                // 推荐复习：使用全部词库中根据记忆曲线筛选的单词（不区分sheet）
                sessionQueue = recommendedReviewWords
                forgottenWordIds.removeAll()
            }
        }
        
        // 延迟重置标志，防止快速连续点击
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            isStartingReview = false
        }
    }
    
    @MainActor
    private func resetReviewState() {
        // 重置复习状态，回到初始选择页面
        reviewModeSelected = false
        reviewMode = nil
        sessionQueue.removeAll()
        isStartingReview = false
    }
}
