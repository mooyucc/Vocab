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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var settingsManager = AppSettingsManager.shared
    @Binding var selectedTab: AppView
    @Query private var words: [Word]
    @Query(sort: \WordSheet.createdAt, order: .reverse) private var allSheets: [WordSheet]
    
    @State private var forgottenWordIds: Set<UUID> = []
    @State private var showReviewAlert = false
    @State private var selectedSheetIds: Set<UUID> = []
    @State private var showSheetPicker = false
    @State private var reviewModeSelected: Bool = false
    @State private var reviewMode: ReviewMode?
    @State private var sessionQueue: [Word] = [] // 当前会话的复习队列
    @State private var sessionInitialCount: Int = 0 // 本轮开始时的队列长度（用于进度）
    @State private var isStartingReview: Bool = false // 防止重复点击
    @State private var showSettings = false
    @State private var showEndReviewConfirm = false
    @State private var dailyMotivation: String = LocalizedKey.dailyMotivation.rawValue.localized
    @State private var isLoadingMotivation = false
    @State private var rememberedCombo: Int = 0
    @State private var comboScale: CGFloat = 1
    
    private let userDefaults = UserDefaults.standard
    private let motivationDateKey = "dailyMotivationDate"
    private let motivationTextKey = "dailyMotivationText"
    private let motivationLanguageKey = "dailyMotivationLanguage"
    
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
        WordSheetService.sortedSheets(
            allSheets.filter { sheet in
                words.contains { $0.sheet?.id == sheet.id }
            }
        )
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
        SpacedRepetition.dueWords(from: words)
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
    
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            return LocalizedKey.goodMorning.rawValue.localized
        case 12..<18:
            return LocalizedKey.goodAfternoon.rawValue.localized
        default:
            return LocalizedKey.goodEvening.rawValue.localized
        }
    }
    
    private var displayName: String {
        if let userName = authManager.userName, !userName.isEmpty {
            return userName
        }
        return "Learner"
    }
    
    /// 推荐复习不可用时展示的说明（与 `recommendedReviewAccessibilityLabel` 一致）
    private var recommendedReviewEmptyHintKey: LocalizedKey {
        SpacedRepetition.emptyHintKey(for: words)
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
    
    init(selectedTab: Binding<AppView> = .constant(.study)) {
        _selectedTab = selectedTab
    }
    
    // MARK: - Hub Layout
    private enum HubLayout {
        static let horizontalInset: CGFloat = 20
        static let cardSpacing: CGFloat = 12
        static let cardCorner: CGFloat = 20
        static let cardMinHeight: CGFloat = 148
        static let heroDiameter: CGFloat = 128
        static let secondaryDiameter: CGFloat = 72
    }
    
    private struct CheckInDay: Identifiable {
        let id: Date
        let label: String
        let checked: Bool
    }
    
    private var reviewedDayStarts: Set<Date> {
        let calendar = Calendar.current
        return Set(words.compactMap { word in
            guard let last = word.lastReviewed else { return nil }
            return calendar.startOfDay(for: last)
        })
    }
    
    private var checkInDays: [CheckInDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settingsManager.language.rawValue)
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        let reviewed = reviewedDayStarts
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 6, to: today) else { return nil }
            return CheckInDay(
                id: date,
                label: formatter.string(from: date),
                checked: reviewed.contains(date)
            )
        }
    }
    
    private var checkInStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let reviewed = reviewedDayStarts
        var cursor = today
        if !reviewed.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  reviewed.contains(yesterday) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while reviewed.contains(cursor), streak < 365 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
    
    private var studyHubView: some View {
        Group {
            if words.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    hubGreetingHeader
                    hubMotivation
                    EmptyLibraryPrompt(
                        title: LocalizedKey.noWordsYet.rawValue.localized,
                        systemImage: "book.closed"
                    ) {
                        selectedTab = .list
                    }
                }
                .padding(.horizontal, HubLayout.horizontalInset)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        hubGreetingHeader
                        hubMotivation
                        hubStatsCards
                        hubReviewCircles
                    }
                    .padding(.horizontal, HubLayout.horizontalInset)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color(.systemGroupedBackground))
        .task {
            checkAndUpdateDailyMotivation()
        }
        .onChange(of: settingsManager.language) { _, _ in
            checkAndUpdateDailyMotivation()
        }
    }
    
    private var hubGreetingHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                Text("\(displayName)!")
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                settingsButtonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LocalizedKey.settings.rawValue.localized)
        }
    }
    
    @ViewBuilder
    private var settingsButtonLabel: some View {
        let icon = Image(systemName: "gearshape")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
        if #available(iOS 26, *) {
            icon
                .glassEffect(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        } else {
            icon
                .background(Color(.secondarySystemBackground))
                .clipShape(Circle())
                .contentShape(Circle())
        }
    }
    
    private var hubMotivation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dailyMotivation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .redacted(reason: isLoadingMotivation ? .placeholder : [])
                .accessibilityLabel(dailyMotivation)
            
            if !words.isEmpty {
                Button {
                    showSheetPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(String(format: LocalizedKey.studyFromSheetFormat.rawValue.localized, selectedSheetName))
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedKey.selectWordSheet.rawValue.localized)
            }
        }
    }
    
    private var hubStatsCards: some View {
        HStack(spacing: HubLayout.cardSpacing) {
            hubProgressCard
            hubCheckInCard
        }
    }
    
    private var hubProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedKey.totalProgress)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack {
                Circle()
                    .stroke(Color.vocabBrand.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: masteryProgress)
                    .stroke(
                        Color.vocabBrand,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: masteryProgress)
                Text("\(masteryPercent)%")
                    .font(.headline.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
            }
            .frame(width: 64, height: 64)
            Text(String(format: LocalizedKey.masteredCountFormat.rawValue.localized, masteredCount, words.count))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: HubLayout.cardMinHeight, alignment: .topLeading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: HubLayout.cardCorner, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(LocalizedKey.totalProgress.rawValue.localized) \(masteryPercent)%，\(String(format: LocalizedKey.masteredCountFormat.rawValue.localized, masteredCount, words.count))")
    }
    
    private var hubCheckInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedKey.checkIn)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(checkInStreak)")
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Text(LocalizedKey.consecutiveDays)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                ForEach(checkInDays) { day in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(day.checked ? Color.vocabBrand : Color.vocabBrand.opacity(0.18))
                            .frame(width: 10, height: 10)
                        Text(day.label)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: HubLayout.cardMinHeight, alignment: .topLeading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: HubLayout.cardCorner, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(LocalizedKey.checkIn.rawValue.localized)，\(checkInStreak)\(LocalizedKey.consecutiveDays.rawValue.localized)")
    }
    
    private var hubReviewCircles: some View {
        let recommendedDisabled = recommendedReviewWords.isEmpty || isStartingReview || words.isEmpty
        let reviewAllDisabled = isStartingReview || filteredWords.isEmpty
        let continueDisabled = isStartingReview || continueLastQueueWords.isEmpty
        
        return VStack(spacing: 28) {
            Button {
                guard !recommendedDisabled else { return }
                startReview(mode: .recommendedReview)
            } label: {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: HubLayout.heroDiameter, height: HubLayout.heroDiameter)
                        .background(
                            Circle()
                                .fill(LinearGradient.vocabBrandProgress)
                        )
                        .contentShape(Circle())
                        .shadow(color: Color.vocabBrand.opacity(recommendedDisabled ? 0 : 0.35), radius: 16, x: 0, y: 8)
                    Text(LocalizedKey.recommendedReview)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 8)
                    Group {
                        if !recommendedReviewWords.isEmpty {
                            Text("\(recommendedReviewWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(recommendedReviewEmptyHintKey)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: 220)
                }
            }
            .buttonStyle(.plain)
            .disabled(recommendedDisabled)
            .opacity(recommendedDisabled ? 0.5 : 1)
            .accessibilityLabel(recommendedReviewAccessibilityLabel)
            
            HStack(spacing: 36) {
                secondaryReviewCircle(
                    symbol: "arrow.clockwise",
                    title: LocalizedKey.reviewAll.rawValue.localized,
                    count: filteredWords.count,
                    disabled: reviewAllDisabled
                ) {
                    startReview(mode: .reviewAll)
                }
                .accessibilityLabel({
                    let title = LocalizedKey.reviewAll.rawValue.localized
                    let desc = LocalizedKey.reviewAllDescription.rawValue.localized
                    guard !filteredWords.isEmpty else { return "\(title)，\(desc)" }
                    return "\(title)，\(filteredWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)。\(desc)"
                }())
                
                secondaryReviewCircle(
                    symbol: "play.fill",
                    title: LocalizedKey.continueLast.rawValue.localized,
                    count: continueLastQueueWords.count,
                    disabled: continueDisabled
                ) {
                    startReview(mode: .continueLast)
                }
                .accessibilityLabel({
                    let title = LocalizedKey.continueLast.rawValue.localized
                    let desc = LocalizedKey.continueLastDescription.rawValue.localized
                    guard !continueLastQueueWords.isEmpty else { return "\(title)，\(desc)" }
                    return "\(title)，\(continueLastQueueWords.count)\(LocalizedKey.wordsToReview.rawValue.localized)。\(desc)"
                }())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
    
    private func secondaryReviewCircle(
        symbol: String,
        title: String,
        count: Int,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.vocabBrand)
                    .frame(width: HubLayout.secondaryDiameter, height: HubLayout.secondaryDiameter)
                    .background(
                        Circle()
                            .fill(Color.vocabBrand.opacity(0.12))
                    )
                    .contentShape(Circle())
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if count > 0 {
                    Text("\(count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
    
    private func checkAndUpdateDailyMotivation() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        let currentLanguage = settingsManager.language.rawValue
        
        if let savedDate = userDefaults.string(forKey: motivationDateKey),
           savedDate == todayString,
           let savedLanguage = userDefaults.string(forKey: motivationLanguageKey),
           savedLanguage == currentLanguage,
           let savedMotivation = userDefaults.string(forKey: motivationTextKey),
           !savedMotivation.isEmpty {
            dailyMotivation = savedMotivation
            return
        }
        
        dailyMotivation = LocalizedKey.dailyMotivation.rawValue.localized
        Task {
            await fetchDailyMotivation()
        }
    }
    
    @MainActor
    private func fetchDailyMotivation() async {
        isLoadingMotivation = true
        defer { isLoadingMotivation = false }
        
        do {
            let motivation = try await DeepseekService.shared.generateDailyMotivation()
            dailyMotivation = motivation
            
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            userDefaults.set(dateFormatter.string(from: today), forKey: motivationDateKey)
            userDefaults.set(motivation, forKey: motivationTextKey)
            userDefaults.set(settingsManager.language.rawValue, forKey: motivationLanguageKey)
        } catch {
            print("获取每日激励语失败: \(error.localizedDescription)")
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if !reviewModeSelected {
                    studyHubView
                } else if studyQueue.isEmpty {
                    // 复习完成
                    reviewCompletedView
                } else {
                    // 显示闪卡
                    if let firstWord = studyQueue.first {
                        VStack(spacing: 0) {
                            sessionProgressBar
                            FlashCardView(
                                word: firstWord,
                                deckLayerCount: min(2, max(0, studyQueue.count - 1)),
                                onResult: { remembered in
                                    handleReviewResult(wordId: firstWord.id, remembered: remembered)
                                }
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                    }
                }
            }
            .navigationTitle(reviewModeSelected ? LocalizedKey.focusMode.rawValue.localized : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(reviewModeSelected ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if reviewModeSelected {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            requestEndReview()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(LocalizedKey.endReview.rawValue.localized)
                    }
                }
            }
        }
        .sheet(isPresented: $showSheetPicker) {
            SheetPickerView(
                sheets: sheetsWithWords,
                selectedSheetIds: $selectedSheetIds
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
        .alert(LocalizedKey.endReviewConfirmTitle.rawValue.localized, isPresented: $showEndReviewConfirm) {
            Button(LocalizedKey.endReview.rawValue.localized) {
                endReviewSession()
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {}
        } message: {
            Text(LocalizedKey.endReviewConfirmMessage)
        }
    }
    
    // MARK: - Learning Progress Header
    private var masteredCount: Int {
        words.filter(\.learned).count
    }
    
    private var masteryProgress: Double {
        guard !words.isEmpty else { return 0 }
        return Double(masteredCount) / Double(words.count)
    }
    
    private var masteryPercent: Int {
        Int((masteryProgress * 100).rounded())
    }
    
    // MARK: - Session Progress
    private var sessionProgressBar: some View {
        let total = max(sessionInitialCount, 1)
        let remaining = studyQueue.count
        let currentIndex = min(total, total - remaining + 1)
        let fill = Double(currentIndex) / Double(total)
        
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: LocalizedKey.sessionProgress.rawValue.localized, currentIndex, total))
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                
                Spacer(minLength: 0)
                
                if rememberedCombo > 1 {
                    Text(String(format: LocalizedKey.comboMultiplier.rawValue.localized, rememberedCombo))
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.vocabBrand)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .scaleEffect(comboScale)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .accessibilityLabel(String(format: LocalizedKey.comboStreak.rawValue.localized, rememberedCombo))
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: currentIndex)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: rememberedCombo)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.vocabBrand.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient.vocabBrandProgress)
                        .frame(width: max(6, geo.size.width * CGFloat(fill)))
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: fill)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sessionProgressAccessibilityLabel(currentIndex: currentIndex, total: total))
    }
    
    private func sessionProgressAccessibilityLabel(currentIndex: Int, total: Int) -> String {
        let progress = String(format: LocalizedKey.sessionProgress.rawValue.localized, currentIndex, total)
        guard rememberedCombo > 1 else { return progress }
        return "\(progress)，\(String(format: LocalizedKey.comboStreak.rawValue.localized, rememberedCombo))"
    }
    
    private func resetSessionCombo() {
        rememberedCombo = 0
        comboScale = 1
    }
    
    private func pulseComboIfNeeded() {
        guard rememberedCombo > 1, !reduceMotion else {
            comboScale = 1
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            comboScale = 1.06
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            comboScale = 1
        }
    }
    
    // MARK: - Review Completed View
    private var reviewCompletedView: some View {
        Group {
            if reviewMode == .reviewAll {
                // 复习全部模式完成
                if #available(iOS 17.0, *) {
                    ContentUnavailableView {
                        Label(LocalizedKey.greatJob.rawValue.localized, systemImage: "face.smiling")
                    } description: {
                        Text(LocalizedKey.allWordsReviewed)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint.opacity(0.3))
                        Text(LocalizedKey.greatJob)
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
                        Label(LocalizedKey.greatJob.rawValue.localized, systemImage: "face.smiling")
                    } description: {
                        Text(LocalizedKey.recommendedReviewCompleted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint.opacity(0.3))
                        Text(LocalizedKey.greatJob)
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
                            Label(LocalizedKey.greatJob.rawValue.localized, systemImage: "face.smiling")
                        } description: {
                            Text(LocalizedKey.todayWordsReviewed)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 64))
                                .foregroundStyle(.tint.opacity(0.3))
                            Text(LocalizedKey.greatJob)
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
                            .tint(Color.vocabBrand)
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
                            .tint(Color.vocabBrand)
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
            if !sessionQueue.isEmpty {
                sessionQueue.removeFirst()
            }
            
            if remembered {
                word.learned = true
                forgottenWordIds.remove(wordId)
                rememberedCombo += 1
                pulseComboIfNeeded()
            } else {
                forgottenWordIds.insert(wordId)
                word.learned = false
                resetSessionCombo()
            }
            word.reviewCount += 1
            word.lastReviewed = Date()
            
            if reviewMode == .recommendedReview {
                if remembered {
                    word.spacedReviewCount += 1
                    word.spacedLastReviewed = Date()
                } else {
                    word.spacedReviewCount = 0
                    word.spacedLastReviewed = nil
                }
            }
            
            if sessionQueue.isEmpty {
                withAnimation {
                    reviewModeSelected = false
                    reviewMode = nil
                    sessionInitialCount = 0
                    resetSessionCombo()
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
            sessionQueue = forgottenWords.shuffled()
            sessionInitialCount = sessionQueue.count
            forgottenWordIds.removeAll()
            resetSessionCombo()
            
            // 如果队列为空，重置状态
            if sessionQueue.isEmpty {
                reviewModeSelected = false
                reviewMode = nil
                sessionInitialCount = 0
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
                sessionQueue = filteredWords.shuffled()
                // 复习全部：清空忘记列表，重新开始
                forgottenWordIds.removeAll()
            case .continueLast:
                sessionQueue = continueLastQueueWords.shuffled()
            case .recommendedReview:
                // 推荐复习：使用全部词库中根据记忆曲线筛选的单词（不区分sheet）
                sessionQueue = recommendedReviewWords.shuffled()
                forgottenWordIds.removeAll()
            }
            sessionInitialCount = sessionQueue.count
            resetSessionCombo()
        }
        
        // 延迟重置标志，防止快速连续点击
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            isStartingReview = false
        }
    }
    
    private var hasReviewedAnyCard: Bool {
        sessionInitialCount > sessionQueue.count
    }
    
    @MainActor
    private func requestEndReview() {
        if sessionQueue.isEmpty || !hasReviewedAnyCard {
            endReviewSession()
        } else {
            showEndReviewConfirm = true
        }
    }
    
    @MainActor
    private func endReviewSession() {
        withAnimation {
            reviewModeSelected = false
            reviewMode = nil
            sessionQueue.removeAll()
            sessionInitialCount = 0
            isStartingReview = false
            resetSessionCombo()
        }
    }
}
