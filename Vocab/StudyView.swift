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
    @State private var selectedSheetId: UUID?
    @State private var showSheetPicker = false
    @State private var reviewModeSelected: Bool = false
    @State private var reviewMode: ReviewMode?
    @State private var sessionQueue: [Word] = [] // 当前会话的复习队列
    @State private var isStartingReview: Bool = false // 防止重复点击
    
    // 根据选中的 sheet 过滤单词
    private var filteredWords: [Word] {
        if let sheetId = selectedSheetId {
            return words.filter { $0.sheet?.id == sheetId }
        } else {
            return words
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
    
    // 根据艾宾浩斯遗忘曲线筛选需要复习的单词（不区分sheet，从全部词库筛选）
    private var recommendedReviewWords: [Word] {
        let now = Date()
        let calendar = Calendar.current
        
        return words.filter { word in
            // 如果从未复习过，需要复习
            guard let lastReviewed = word.lastReviewed else {
                return true
            }
            
            // 计算距离上次复习的天数
            let daysSinceReview = calendar.dateComponents([.day], from: lastReviewed, to: now).day ?? 0
            
            // 根据复习次数确定复习间隔（艾宾浩斯遗忘曲线）
            // 第1次复习：1天后
            // 第2次复习：3天后
            // 第3次复习：7天后
            // 第4次复习：15天后
            // 第5次复习：30天后
            // 之后：每30天复习一次
            let reviewCount = word.reviewCount
            let interval: Int
            
            switch reviewCount {
            case 0:
                interval = 0  // 从未复习过，立即需要复习
            case 1:
                interval = 1
            case 2:
                interval = 3
            case 3:
                interval = 7
            case 4:
                interval = 15
            case 5:
                interval = 30
            default:
                interval = 30  // 5次以上，每30天复习一次
            }
            
            // 如果距离上次复习的天数 >= 间隔天数，则需要复习
            return daysSinceReview >= interval
        }
    }
    
    private var selectedSheetName: String {
        if let sheetId = selectedSheetId,
           let sheet = sheetsWithWords.first(where: { $0.id == sheetId }) {
            return sheet.localizedDisplayName
        }
        return LocalizedKey.allSheets.rawValue.localized
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
                selectedSheetId: $selectedSheetId
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
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 32) {
                Button(action: {
                    guard !isStartingReview else { return }
                    startReview(mode: .recommendedReview)
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 48))
                            .foregroundStyle(.purple)
                        Text(LocalizedKey.recommendedReview)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(LocalizedKey.recommendedReviewDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if !recommendedReviewWords.isEmpty {
                            Text("\(recommendedReviewWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .padding(.horizontal, 24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(LocalizedKey.recommendedReview.rawValue.localized)，\(recommendedReviewWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                .disabled(recommendedReviewWords.isEmpty || isStartingReview)
                .opacity(recommendedReviewWords.isEmpty || isStartingReview ? 0.5 : 1.0)
                
                Button(action: {
                    guard !isStartingReview else { return }
                    startReview(mode: .reviewAll)
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        Text(LocalizedKey.reviewAll)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(LocalizedKey.reviewAllDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .padding(.horizontal, 24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(LocalizedKey.reviewAll.rawValue.localized)，\(LocalizedKey.reviewAllDescription.rawValue.localized)")
                .disabled(isStartingReview)
                .opacity(isStartingReview ? 0.5 : 1.0)
                
                Button(action: {
                    guard !isStartingReview else { return }
                    startReview(mode: .continueLast)
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text(LocalizedKey.continueLast)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(LocalizedKey.continueLastDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .padding(.horizontal, 24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(LocalizedKey.continueLast.rawValue.localized)，\(LocalizedKey.continueLastDescription.rawValue.localized)")
                .disabled(isStartingReview)
                .opacity(isStartingReview ? 0.5 : 1.0)
            }
            .padding(.horizontal, 40)
            
            Spacer()
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
                        Text("太棒了！推荐复习已完成")
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
                    // 在"复习全部"模式下，即使忘记了也不标记为已学，以便后续可以再次复习
                    if reviewMode == .reviewAll {
                        word.learned = false
                    }
                }
                word.reviewCount += 1
                word.lastReviewed = Date()
                
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
                sessionQueue = filteredWords.filter { !$0.learned || forgottenWordIds.contains($0.id) }
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
