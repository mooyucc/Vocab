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

/// 背单词 hub 横向手风琴入口
private enum StudyHubAction: Int, CaseIterable, Identifiable {
    case recommended
    case reviewAll
    case continueLast
    case exercise
    case guess
    
    var id: Int { rawValue }
    
    var titleKey: LocalizedKey {
        switch self {
        case .recommended: return .recommendedReview
        case .reviewAll: return .reviewAll
        case .continueLast: return .continueLast
        case .exercise: return .tabExercise
        case .guess: return .tabGuess
        }
    }
    
    var descriptionKey: LocalizedKey {
        switch self {
        case .recommended: return .recommendedReviewDescription
        case .reviewAll: return .reviewAllDescription
        case .continueLast: return .continueLastDescription
        case .exercise: return .exerciseStartDescription
        case .guess: return .hubGuessDescription
        }
    }
    
    var symbol: String {
        switch self {
        case .recommended: return "brain.head.profile"
        case .reviewAll: return "arrow.clockwise"
        case .continueLast: return "play.fill"
        case .exercise: return "text.badge.checkmark"
        case .guess: return "puzzlepiece.extension"
        }
    }
    
    /// 收起窄条底色（与词库手风琴色板共用）
    var stripColorName: String {
        switch self {
        case .recommended: return "hubGold"
        case .reviewAll: return "hubBrand"
        case .continueLast: return "hubSky"
        case .exercise: return "hubIndigo"
        case .guess: return "hubTeal"
        }
    }
    
    var stripColor: Color {
        WordSheetAppearance.color(named: stripColorName)
    }
    
    var inkOnStrip: Color {
        switch self {
        case .continueLast, .exercise: return Color(hex: "1A1A1A")
        default: return Color(hex: "1A1A1A")
        }
    }
}

struct StudyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var localizedString = LocalizedString.shared
    @Binding var selectedTab: AppView
    @Query private var words: [Word]
    @Query(sort: \WordSheet.createdAt, order: .reverse) private var allSheets: [WordSheet]
    
    @State private var forgottenWordIds: Set<UUID> = []
    @State private var showReviewAlert = false
    @State private var selectedSheetIds: Set<UUID> = []
    @State private var reviewModeSelected: Bool = false
    @State private var reviewMode: ReviewMode?
    @State private var sessionQueue: [Word] = [] // 当前会话的复习队列
    @State private var sessionInitialCount: Int = 0 // 本轮开始时的队列长度（用于进度）
    @State private var isStartingReview: Bool = false // 防止重复点击
    @State private var showSettings = false
    @State private var showEndReviewConfirm = false
    @State private var rememberedCombo: Int = 0
    @State private var comboScale: CGFloat = 1
    @State private var showExercise = false
    @State private var showGuess = false
    @State private var isExerciseInProgress = false
    @State private var isGuessSessionActive = false
    @State private var endGuessSessionRequested = false
    /// 手风琴选中项；nil = 全等宽（首次点击前）
    @State private var accordionSelection: StudyHubAction? = nil
    @State private var accordionDetailVisible = false
    /// 氛围光斑上一入口色，用于双色过渡
    @State private var atmospherePreviousAccent: Color = .vocabBrandDeep
    
    private var atmosphereAccent: Color {
        accordionSelection?.stripColor ?? .vocabBrand
    }
    
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
    
    private var todayDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppSettingsManager.shared.language.rawValue)
        formatter.setLocalizedDateFormatFromTemplate("EEE, d MMM")
        return formatter.string(from: Date())
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
        static let horizontalInset: CGFloat = 16
        static let cardCorner: CGFloat = 44
        static let avatarSize: CGFloat = 60
        static let accordionSpacing: CGFloat = 8
        static let accordionPadding: CGFloat = 10
        static let stripCorner: CGFloat = 22
        static let containerCorner: CGFloat = 28
        /// 竖向：收起条高度
        static let collapsedStripHeight: CGFloat = 56
        /// 竖向：展开条高度
        static let expandedStripHeight: CGFloat = 240
        static let progressRingSize: CGFloat = 56
        /// 顶栏打卡 / 词库选择胶囊统一高度，避免长文案把右侧撑高
        static let capsuleHeight: CGFloat = 40
    }
    
    private var hubActions: [StudyHubAction] { StudyHubAction.allCases }
    
    private var reviewedDayStarts: Set<Date> {
        let calendar = Calendar.current
        return Set(words.compactMap { word in
            guard let last = word.lastReviewed else { return nil }
            return calendar.startOfDay(for: last)
        })
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
                ZStack(alignment: .top) {
                    VocabAtmosphereBackground(
                        accent: atmosphereAccent,
                        secondaryAccent: atmospherePreviousAccent
                    )
                    VStack(alignment: .leading, spacing: 16) {
                        hubHeaderOnBrand
                        EmptyLibraryPrompt(
                            title: LocalizedKey.noWordsYet.rawValue.localized,
                            systemImage: "book.closed"
                        ) {
                            selectedTab = .list
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: HubLayout.cardCorner, style: .continuous)
                                .fill(Color.vocabSurface)
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, HubLayout.horizontalInset)
                    .padding(.top, 8)
                }
            } else {
                ZStack(alignment: .top) {
                    VocabAtmosphereBackground(
                        accent: atmosphereAccent,
                        secondaryAccent: atmospherePreviousAccent
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            collapseAccordion()
                        }
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            hubHeaderOnBrand
                            hubAccordion
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 120)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    collapseAccordion()
                                }
                        }
                        .padding(.horizontal, HubLayout.horizontalInset)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }
    
    // MARK: - 1. Header on brand (no card)
    
    private var hubHeaderOnBrand: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                UserAvatarView(
                    image: authManager.avatarImage,
                    userName: authManager.userName ?? displayName,
                    size: HubLayout.avatarSize,
                    style: .onBrand
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(greeting)\(displayName)")
                        .font(.title.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(todayDateText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 8)
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedKey.settings.rawValue.localized)
            }
            
            HStack(spacing: 8) {
                if checkInStreak > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("\(LocalizedKey.checkIn.rawValue.localized) \(checkInStreak)\(LocalizedKey.consecutiveDays.rawValue.localized)")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: HubLayout.capsuleHeight)
                    .vocabCapsuleChrome()
                    .contentShape(Capsule())
                    .accessibilityElement(children: .combine)
                }
                
                Spacer(minLength: 8)
                
                hubSheetCapsule
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Capsule sheet picker + Accordion
    
    private var hubSheetWordCount: Int { filteredWords.count }
    
    private var hubSheetMasteredCount: Int {
        filteredWords.filter(\.learned).count
    }
    
    private var hubSheetMasteryPercent: Int {
        guard hubSheetWordCount > 0 else { return 0 }
        return Int((Double(hubSheetMasteredCount) / Double(hubSheetWordCount) * 100).rounded())
    }
    
    private var hubSheetMasteryProgress: CGFloat {
        guard hubSheetWordCount > 0 else { return 0 }
        return CGFloat(hubSheetMasteredCount) / CGFloat(hubSheetWordCount)
    }
    
    private var hubSheetMenuSelection: Binding<UUID?> {
        Binding(
            get: {
                selectedSheetIds.count == 1 ? selectedSheetIds.first : nil
            },
            set: { newValue in
                if let id = newValue {
                    selectedSheetIds = [id]
                } else {
                    selectedSheetIds = []
                }
            }
        )
    }
    
    private var hubSheetCapsule: some View {
        Menu {
            Picker(selection: hubSheetMenuSelection) {
                Text(LocalizedKey.allSheets)
                    .tag(Optional<UUID>.none)
                ForEach(sheetsWithWords) { sheet in
                    Label(sheet.localizedDisplayName, systemImage: sheet.displaySymbolName)
                        .tag(Optional(sheet.id))
                }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: 8) {
                Text(LocalizedKey.currentWordSheet)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(-1)
                Text(selectedSheetName)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 16)
            .frame(height: HubLayout.capsuleHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .vocabCapsuleChrome()
        .contentShape(Capsule())
        .accessibilityLabel(LocalizedKey.selectWordSheet.rawValue.localized)
        .accessibilityValue(selectedSheetName)
    }
    
    private var hubAccordion: some View {
        let heights = accordionStripHeights()
        return VStack(spacing: HubLayout.accordionSpacing) {
            ForEach(Array(hubActions.enumerated()), id: \.element.id) { index, action in
                let isExpanded = accordionSelection == action
                hubAccordionStrip(
                    action: action,
                    isExpanded: isExpanded,
                    height: heights[index]
                )
            }
        }
        .padding(HubLayout.accordionPadding)
        .background(
            VocabChromeContainerBackground(cornerRadius: HubLayout.containerCorner)
        )
        .accessibilityElement(children: .contain)
    }
    
    private func accordionStripHeights() -> [CGFloat] {
        let count = hubActions.count
        guard count > 0 else { return [] }
        if let selected = accordionSelection,
           let selectedIndex = hubActions.firstIndex(of: selected) {
            return (0..<count).map {
                $0 == selectedIndex ? HubLayout.expandedStripHeight : HubLayout.collapsedStripHeight
            }
        }
        return Array(repeating: HubLayout.collapsedStripHeight, count: count)
    }
    
    private func hubAccordionStrip(
        action: StudyHubAction,
        isExpanded: Bool,
        height: CGFloat
    ) -> some View {
        let available = isHubActionAvailable(action)
        let strip = ZStack(alignment: .topLeading) {
            if isExpanded {
                VocabGlassBackground(cornerRadius: HubLayout.stripCorner)
            } else if let progress = accordionProgress(for: action) {
                // 收起态：自左向右水位；未完成区右侧淡遮罩
                GeometryReader { geo in
                    ZStack(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: HubLayout.stripCorner, style: .continuous)
                            .fill(action.stripColor)
                        Rectangle()
                            .fill(Color.black.opacity(0.18))
                            .frame(width: geo.size.width * (1 - progress))
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: progress)
            } else {
                // 习题 / 猜词：无水位，整条实色
                RoundedRectangle(cornerRadius: HubLayout.stripCorner, style: .continuous)
                    .fill(action.stripColor)
            }
            
            hubAccordionCollapsed(action: action)
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(false)
            
            if isExpanded {
                hubAccordionExpanded(action: action, available: available)
                    .opacity(accordionDetailVisible ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: HubLayout.stripCorner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: HubLayout.stripCorner, style: .continuous))
        .opacity(available || isExpanded ? 1 : 0.72)
        .background(alignment: .bottom) {
            if isExpanded {
                Ellipse()
                    .fill(action.stripColor.opacity(0.55))
                    .frame(height: 36)
                    .blur(radius: 22)
                    .padding(.horizontal, 28)
                    .offset(y: 10)
                    .allowsHitTesting(false)
            }
        }
        
        return Group {
            if isExpanded {
                strip
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isSelected)
            } else {
                strip
                    .onTapGesture {
                        selectAccordion(action)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accordionAccessibilityLabel(for: action))
                    .accessibilityValue(accordionAccessibilityValue(for: action, isExpanded: false))
                    .accessibilityHint(LocalizedKey.hubStart.rawValue.localized)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        selectAccordion(action)
                    }
            }
        }
    }
    
    private func hubAccordionCollapsed(action: StudyHubAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(action.inkOnStrip)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.14))
                )
            
            Text(action.titleKey.rawValue.localized)
                .font(.subheadline.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(action.inkOnStrip)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Spacer(minLength: 0)
            
            Text(accordionMetric(for: action))
                .font(.subheadline.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(action.inkOnStrip.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func hubAccordionExpanded(action: StudyHubAction, available: Bool) -> some View {
        let stats = accordionExpandedStats(for: action)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    collapseAccordion()
                } label: {
                    Image(systemName: action.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(action.stripColor)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedKey.cancel.rawValue.localized)
                
                Text(action.titleKey.rawValue.localized)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Spacer(minLength: 0)
                
                if let badge = accordionBadgeTitle(for: action) {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
            
            VocabCardHairline()
            
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(accordionMetric(for: action))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        
                        Text(accordionHeroUnit(for: action))
                            .font(.caption.weight(.medium))
                            .fontDesign(.rounded)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    
                    Text(hubDetailSubtitle(for: action))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                
                Spacer(minLength: 8)
                
                if let progress = stats.barProgress, let percent = stats.percent {
                    accordionProgressRing(
                        progress: progress,
                        percent: percent,
                        tint: action.stripColor
                    )
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture().onEnded {
                            selectedTab = .progress
                        }
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(LocalizedKey.learningProgress.rawValue.localized)
                    .accessibilityValue(stats.accessibilityValue)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        selectedTab = .progress
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            VocabCardHairline()
            
            Button {
                activateHubAction(action)
            } label: {
                Text(LocalizedKey.hubStart.rawValue.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(available ? Color(hex: "1A1A1A") : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(available ? action.stripColor : Color.white.opacity(0.12))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!available || isStartingReview)
            .opacity(available ? 1 : 0.7)
            .accessibilityLabel(LocalizedKey.hubStart.rawValue.localized)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func accordionProgressRing(progress: CGFloat, percent: Int, tint: Color) -> some View {
        let clamped = min(max(progress, 0), 1)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)%")
                .font(.caption.weight(.semibold))
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(width: HubLayout.progressRingSize, height: HubLayout.progressRingSize)
        .accessibilityHidden(true)
    }
    
    private func selectAccordion(_ action: StudyHubAction) {
        guard accordionSelection != action else { return }
        accordionDetailVisible = false
        let previous = accordionSelection?.stripColor ?? atmosphereAccent
        let widthAnim: Animation = reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.42, dampingFraction: 0.86)
        withAnimation(widthAnim) {
            atmospherePreviousAccent = previous
            accordionSelection = action
        }
        VocabHaptics.impact(.light)
        let delay = reduceMotion ? 0.0 : 0.16
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22)) {
                accordionDetailVisible = true
            }
        }
    }
    
    private func collapseAccordion() {
        guard accordionSelection != nil else { return }
        accordionDetailVisible = false
        let previous = accordionSelection?.stripColor ?? atmosphereAccent
        let widthAnim: Animation = reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.42, dampingFraction: 0.86)
        withAnimation(widthAnim) {
            atmospherePreviousAccent = previous
            accordionSelection = nil
        }
    }
    
    /// 各入口水位比例；习题 / 猜词返回 nil（无水位）
    private func accordionProgress(for action: StudyHubAction) -> CGFloat? {
        switch action {
        case .recommended:
            let pool = words.filter(\.learned).count
            guard pool > 0 else { return 0 }
            return max(0, min(1, 1 - CGFloat(recommendedReviewWords.count) / CGFloat(pool)))
        case .reviewAll:
            guard hubSheetWordCount > 0 else { return 0 }
            return CGFloat(todayReviewedMasteredCount) / CGFloat(hubSheetWordCount)
        case .continueLast:
            let total = max(hubSheetWordCount, 1)
            return max(0, min(1, 1 - CGFloat(continueLastQueueWords.count) / CGFloat(total)))
        case .exercise, .guess:
            return nil
        }
    }
    
    private func accordionBadgeTitle(for action: StudyHubAction) -> String? {
        switch action {
        case .recommended, .exercise, .guess:
            return LocalizedKey.allSheets.rawValue.localized
        case .reviewAll, .continueLast:
            return selectedSheetName
        }
    }
    
    private struct AccordionExpandedStats {
        var primaryLabel: String
        var primaryValue: String
        var percentLabel: String?
        var percent: Int?
        var barProgress: CGFloat?
        
        var accessibilityValue: String {
            var parts = ["\(primaryLabel) \(primaryValue)"]
            if let percentLabel, let percent {
                parts.append("\(percentLabel) \(percent)%")
            }
            return parts.joined(separator: "，")
        }
    }
    
    /// 展开态进度文案 / 比例，与各入口水位语义一致
    private func accordionExpandedStats(for action: StudyHubAction) -> AccordionExpandedStats {
        let progressKey = LocalizedKey.totalProgress.rawValue.localized
        switch action {
        case .recommended:
            let due = recommendedReviewWords.count
            let pool = words.filter(\.learned).count
            let bar = accordionProgress(for: .recommended) ?? 0
            return AccordionExpandedStats(
                primaryLabel: LocalizedKey.recommendedReview.rawValue.localized,
                primaryValue: "\(due) / \(pool)",
                percentLabel: progressKey,
                percent: Int((bar * 100).rounded()),
                barProgress: bar
            )
        case .reviewAll:
            let bar = accordionProgress(for: .reviewAll) ?? 0
            return AccordionExpandedStats(
                primaryLabel: LocalizedKey.mastered.rawValue.localized,
                primaryValue: "\(todayReviewedMasteredCount) / \(hubSheetWordCount)",
                percentLabel: progressKey,
                percent: Int((bar * 100).rounded()),
                barProgress: bar
            )
        case .continueLast:
            let remaining = continueLastQueueWords.count
            let bar = accordionProgress(for: .continueLast) ?? 0
            return AccordionExpandedStats(
                primaryLabel: LocalizedKey.continueLast.rawValue.localized,
                primaryValue: "\(remaining) / \(hubSheetWordCount)",
                percentLabel: progressKey,
                percent: Int((bar * 100).rounded()),
                barProgress: bar
            )
        case .exercise:
            return AccordionExpandedStats(
                primaryLabel: LocalizedKey.tabExercise.rawValue.localized,
                primaryValue: "\(words.count)",
                percentLabel: nil,
                percent: nil,
                barProgress: nil
            )
        case .guess:
            return AccordionExpandedStats(
                primaryLabel: LocalizedKey.tabGuess.rawValue.localized,
                primaryValue: "\(words.count)",
                percentLabel: nil,
                percent: nil,
                barProgress: nil
            )
        }
    }
    
    /// 今日已复习且仍掌握（当前词库），用于「复习全部」日进度水位
    private var todayReviewedMasteredCount: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return filteredWords.filter { word in
            guard word.learned, let last = word.lastReviewed else { return false }
            return calendar.startOfDay(for: last) == today
        }.count
    }
    
    private func accordionAccessibilityValue(for action: StudyHubAction, isExpanded: Bool) -> String {
        guard !isExpanded, let progress = accordionProgress(for: action) else { return "" }
        return "\(LocalizedKey.totalProgress.rawValue.localized) \(Int((progress * 100).rounded()))%"
    }
    
    private func accordionMetric(for action: StudyHubAction) -> String {
        switch action {
        case .recommended: return "\(recommendedReviewWords.count)"
        case .reviewAll: return "\(filteredWords.count)"
        case .continueLast: return "\(continueLastQueueWords.count)"
        case .exercise, .guess: return "\(words.count)"
        }
    }
    
    private func accordionHeroUnit(for action: StudyHubAction) -> String {
        switch action {
        case .recommended, .continueLast:
            return LocalizedKey.libraryFilterDue.rawValue.localized
        case .reviewAll, .exercise, .guess:
            return LocalizedKey.statTotal.rawValue.localized
        }
    }
    
    private func accordionAccessibilityLabel(for action: StudyHubAction) -> String {
        switch action {
        case .recommended:
            return recommendedReviewAccessibilityLabel
        default:
            return "\(action.titleKey.rawValue.localized)，\(accordionMetric(for: action))"
        }
    }
    
    private func hubDetailSubtitle(for action: StudyHubAction) -> String {
        switch action {
        case .recommended:
            if recommendedReviewWords.isEmpty {
                return recommendedReviewEmptyHintKey.rawValue.localized
            }
            return action.descriptionKey.rawValue.localized
        case .reviewAll:
            if filteredWords.isEmpty {
                return LocalizedKey.noWordsYet.rawValue.localized
            }
            return action.descriptionKey.rawValue.localized
        case .continueLast:
            if continueLastQueueWords.isEmpty {
                return LocalizedKey.noWordsYet.rawValue.localized
            }
            return action.descriptionKey.rawValue.localized
        case .exercise, .guess:
            return action.descriptionKey.rawValue.localized
        }
    }
    
    private func isHubActionAvailable(_ action: StudyHubAction) -> Bool {
        switch action {
        case .recommended:
            return !recommendedReviewWords.isEmpty && !isStartingReview && !words.isEmpty
        case .reviewAll:
            return !isStartingReview && !filteredWords.isEmpty
        case .continueLast:
            return !isStartingReview && !continueLastQueueWords.isEmpty
        case .exercise, .guess:
            return !words.isEmpty
        }
    }
    
    @MainActor
    private func activateHubAction(_ action: StudyHubAction) {
        guard isHubActionAvailable(action) else { return }
        switch action {
        case .recommended:
            startReview(mode: .recommendedReview)
        case .reviewAll:
            startReview(mode: .reviewAll)
        case .continueLast:
            startReview(mode: .continueLast)
        case .exercise:
            showExercise = true
        case .guess:
            showGuess = true
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if !reviewModeSelected {
                    studyHubView
                } else if studyQueue.isEmpty {
                    // 复习完成
                    ZStack {
                        VocabAtmosphereBackground(
                            accent: .vocabBrand,
                            secondaryAccent: .vocabGold
                        )
                        reviewCompletedView
                    }
                } else {
                    // 显示闪卡
                    if let firstWord = studyQueue.first {
                        ZStack {
                            VocabAtmosphereBackground(
                                accent: .vocabBrand,
                                secondaryAccent: .vocabTeal
                            )
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
                        }
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
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showExercise) {
            ExerciseView(
                isExerciseInProgress: $isExerciseInProgress,
                selectedTab: $selectedTab
            )
        }
        .fullScreenCover(isPresented: $showGuess) {
            GuessWordGameView(
                isSessionActive: $isGuessSessionActive,
                endSessionRequested: $endGuessSessionRequested,
                selectedTab: $selectedTab
            )
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .list {
                showExercise = false
                showGuess = false
            }
        }
        .background(reviewModeSelected ? Color.black : Color.clear)
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
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                
                Spacer(minLength: 0)
                
                if rememberedCombo > 1 {
                    Text(String(format: LocalizedKey.comboMultiplier.rawValue.localized, rememberedCombo))
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.vocabGold)
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
        let hasForgotten = reviewMode == .continueLast && !forgottenWordIds.isEmpty
        return VStack(spacing: 20) {
            Spacer(minLength: 8)
            
            Text("\(max(sessionInitialCount, 0))")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            VStack(spacing: 8) {
                Text(hasForgotten ? LocalizedKey.roundComplete : LocalizedKey.greatJob)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                Text(completionMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            
            VStack(spacing: 12) {
                if hasForgotten {
                    Button {
                        reviewForgottenWords()
                    } label: {
                        Label(LocalizedKey.reviewAgain.rawValue.localized, systemImage: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.vocabBrandDeep)
                    .controlSize(.large)
                }
                
                Button {
                    openPractice(.exercise)
                } label: {
                    Label(LocalizedKey.goToExercise.rawValue.localized, systemImage: "text.badge.checkmark")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.vocabTeal)
                .controlSize(.large)
                
                Button {
                    openPractice(.guess)
                } label: {
                    Label(LocalizedKey.goToGuess.rawValue.localized, systemImage: "puzzlepiece.extension")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Color.vocabGold)
                .controlSize(.large)
                
                Button {
                    endReviewSession()
                } label: {
                    Text(LocalizedKey.done)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 28)
            
            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
        .accessibilityElement(children: .contain)
    }
    
    private var completionMessage: String {
        if reviewMode == .continueLast && !forgottenWordIds.isEmpty {
            return "\(forgottenWordIds.count)\(LocalizedKey.wordsNeedReview.rawValue.localized)"
        }
        switch reviewMode {
        case .reviewAll:
            return LocalizedKey.allWordsReviewed.rawValue.localized
        case .recommendedReview:
            return LocalizedKey.recommendedReviewCompleted.rawValue.localized
        case .continueLast, .none:
            return LocalizedKey.todayWordsReviewed.rawValue.localized
        }
    }
    
    private enum PracticeDestination {
        case exercise
        case guess
    }
    
    private func openPractice(_ destination: PracticeDestination) {
        endReviewSession()
        switch destination {
        case .exercise:
            showExercise = true
        case .guess:
            showGuess = true
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
                WordSheetService.setLearned(word, true)
                forgottenWordIds.remove(wordId)
                rememberedCombo += 1
                pulseComboIfNeeded()
            } else {
                forgottenWordIds.insert(wordId)
                WordSheetService.setLearned(word, false)
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
                resetSessionCombo()
            }
            try? modelContext.save()
        }
    }
    
    @MainActor
    private func reviewForgottenWords() {
        // 将"忘记了"的单词重新加入学习队列
        guard reviewMode != nil else { return }
        
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
