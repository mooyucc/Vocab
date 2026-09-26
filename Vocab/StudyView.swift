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

/// 背单词 hub 第三段圆环上的五个入口
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
}

struct StudyView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var authManager: AuthenticationManager
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
    @State private var rememberedCombo: Int = 0
    @State private var comboScale: CGFloat = 1
    @State private var showExercise = false
    @State private var showGuess = false
    @State private var isExerciseInProgress = false
    @State private var isGuessSessionActive = false
    @State private var endGuessSessionRequested = false
    /// 第三段圆环当前选中项（正中 / 正上）
    @State private var hubActionIndex: Int = 0
    /// Click Wheel：相对吸附位的实时转角（度，顺时针为正）
    @State private var ringDragDegrees: Double = 0
    @State private var ringLastFingerAngle: Double? = nil
    @State private var ringDidScrub: Bool = false
    /// Click Wheel：上次已反馈的小刻度索引（与视觉 minorStep 对齐）
    @State private var ringLastTickIndex: Int? = nil
    
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
        static let centerDiameter: CGFloat = 84
        static let sideDiameter: CGFloat = 58
        static let farDiameter: CGFloat = 44
        /// 相邻按钮夹角（度）；半径放大后收紧，保证屏上可见左中右三个
        static let buttonAngleStep: Double = 15
        /// Click Wheel 小刻度步长（度），与 HubClickWheelTicks.minorStep 一致
        static let clickTickStep: Double = 3
        /// 小于此转角视为点击而非刮环
        static let tapMaxDegrees: Double = 10
        /// 奶油卡相对顶部的预留（问候区下方；含左侧大头像）
        static let headerBlockHeight: CGFloat = 152
        static let avatarSize: CGFloat = 60
    }
    
    private var hubActions: [StudyHubAction] { StudyHubAction.allCases }
    
    private var selectedHubAction: StudyHubAction {
        let count = hubActions.count
        let idx = ((hubActionIndex % count) + count) % count
        return hubActions[idx]
    }
    
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
                    StudyHubAtmosphereBackground(includeBottomTeal: false)
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
                ZStack {
                    StudyHubAtmosphereBackground(includeBottomTeal: true)
                    
                    GeometryReader { geo in
                        let metrics = StudyHubStackMetrics(
                            size: geo.size,
                            stackOffsetY: HubLayout.headerBlockHeight - 88
                        )
                        let action = selectedHubAction
                        let available = isHubActionAvailable(action)
                        
                        ZStack(alignment: .top) {
                            hubHeaderOnBrand
                                .padding(.horizontal, HubLayout.horizontalInset)
                                .padding(.top, 8)
                                .zIndex(8)
                            
                            hubCreamCard(
                                bottomClear: StudyHubStackMetrics.isPadLandscapeLarge(geo.size)
                                    ? max(300, geo.size.height * 0.34)
                                    : 200
                            )
                                .padding(.top, HubLayout.headerBlockHeight + 28)
                                .frame(maxWidth: .infinity, alignment: .top)
                                .zIndex(1)
                            
                            // 第三部分：橙色大圆（微渐变 + 描边 + 投影，增加层次）
                            ZStack {
                                Circle()
                                    .fill(LinearGradient.vocabGoldProgress)
                                DiagonalStripePattern(lineColor: Color.vocabInk.opacity(0.55))
                                    .opacity(0.22)
                                    .clipShape(Circle())
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.40),
                                                Color.clear,
                                                Color.black.opacity(0.14)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                            .frame(width: metrics.orangeRadius * 2, height: metrics.orangeRadius * 2)
                            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 6)
                            .position(metrics.center)
                            .zIndex(2)
                            .allowsHitTesting(false)
                            
                            // Click Wheel 刻度：钟表式，圆心与半径同第五部分
                            HubClickWheelTicks(
                                center: metrics.center,
                                radius: metrics.buttonRadius
                            )
                            .stroke(
                                Color.white.opacity(0.32),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                            .zIndex(2)
                            .allowsHitTesting(false)
                            
                            // 五钮视觉：圆心与第三、四部分一致，半径在二者之间
                            ForEach(hubActions) { hubAction in
                                let delta = hubAction.rawValue - hubActionIndex
                                let angleDeg = Double(delta) * HubLayout.buttonAngleStep + ringDragDegrees
                                let absDelta = abs(Double(delta) - ringDragDegrees / HubLayout.buttonAngleStep)
                                let scale = ringDiameter(for: visualStep(absDelta)) / HubLayout.sideDiameter
                                let emphasized = abs(angleDeg) < HubLayout.buttonAngleStep * 0.45
                                
                                ringActionKnob(
                                    action: hubAction,
                                    scale: scale,
                                    emphasized: emphasized
                                )
                                .position(
                                    metrics.point(
                                        on: metrics.buttonRadius,
                                        angleFromVerticalDegrees: angleDeg
                                    )
                                )
                                .opacity(opacityForRing(absDelta: absDelta))
                                .zIndex(emphasized ? 6 : 4)
                                .allowsHitTesting(false)
                            }
                            
                            // 第四部分：青绿圆 + 上缘尖角（同一 Path，避免透出橙环斜纹）
                            HubTealDiskWithNotch(
                                center: metrics.center,
                                radius: metrics.tealRadius
                            )
                            .fill(
                                RadialGradient(
                                    colors: [Color.vocabTeal, Color.vocabTeal.opacity(0.85)],
                                    center: UnitPoint(
                                        x: metrics.center.x / max(geo.size.width, 1),
                                        y: metrics.center.y / max(geo.size.height, 1)
                                    ),
                                    startRadius: 0,
                                    endRadius: metrics.tealRadius
                                )
                            )
                            .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: -2)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .zIndex(3)
                            .allowsHitTesting(false)
                            
                            // Click Wheel 热区：橙环 − 青圆（切向刮动）
                            StudyHubAnnulus(
                                center: metrics.center,
                                outerRadius: metrics.orangeRadius,
                                innerRadius: metrics.tealRadius
                            )
                            .fill(Color.white.opacity(0.001), style: FillStyle(eoFill: true, antialiased: true))
                            .contentShape(
                                StudyHubAnnulus(
                                    center: metrics.center,
                                    outerRadius: metrics.orangeRadius,
                                    innerRadius: metrics.tealRadius
                                ),
                                eoFill: true
                            )
                            .gesture(clickWheelGesture(center: metrics.center, metrics: metrics))
                            .zIndex(4)
                            
                            // 青绿圆内：标题 / 说明（点击开始）
                            Button {
                                activateSelectedHubAction()
                            } label: {
                                VStack(spacing: 8) {
                                    Text(action.titleKey.rawValue.localized)
                                        .font(.title3.weight(.bold))
                                        .fontDesign(.rounded)
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)
                                    
                                    Text(hubDetailSubtitle(for: action))
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.9))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(3)
                                        .minimumScaleFactor(0.85)
                                        .frame(maxWidth: min(220, geo.size.width * 0.55))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(VocabPressButtonStyle())
                            .disabled(!available || isStartingReview)
                            .opacity(available ? 1 : 0.45)
                            .accessibilityLabel(LocalizedKey.hubStart.rawValue.localized)
                            .position(x: metrics.center.x, y: metrics.contentY)
                            .zIndex(7)
                            .animation(.easeInOut(duration: 0.22), value: hubActionIndex)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .coordinateSpace(name: "hubClickWheel")
                        .clipped()
                    }
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
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(LocalizedKey.checkIn.rawValue.localized) \(checkInStreak)\(LocalizedKey.consecutiveDays.rawValue.localized)")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color(hex: "1A1A1A")))
            .padding(3)
            .background(Capsule().fill(Color.black.opacity(0.18)))
            .opacity(checkInStreak > 0 ? 1 : 0)
            .accessibilityHidden(checkInStreak <= 0)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - 2. Cream Card
    
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
    
    private func hubCreamCard(bottomClear: CGFloat = 200) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            hubSheetPickerHeader
            hubProgressMetrics
            // 底部留白，让橙圆叠上来时不挡住进度区；大屏横屏加高以盖住侧边粉底
            Color.clear.frame(height: bottomClear)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: HubLayout.cardCorner,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: HubLayout.cardCorner,
                style: .continuous
            )
            .fill(Color.vocabSurface)
            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: HubLayout.cardCorner,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: HubLayout.cardCorner,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
            )
        )
    }
    
    private var hubSheetPickerHeader: some View {
        Button {
            showSheetPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedKey.currentWordSheet)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(selectedSheetName)
                        .font(.title2.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.vocabInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizedKey.selectWordSheet.rawValue.localized)
        .accessibilityValue(selectedSheetName)
    }
    
    private var hubProgressMetrics: some View {
        Button {
            selectedTab = .progress
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    hubMetricColumn(
                        systemImage: "checkmark.seal.fill",
                        label: LocalizedKey.mastered.rawValue.localized,
                        value: "\(hubSheetMasteredCount) / \(hubSheetWordCount)",
                        valueColor: Color.vocabTeal
                    )
                    hubMetricColumn(
                        systemImage: "chart.bar.fill",
                        label: LocalizedKey.totalProgress.rawValue.localized,
                        value: "\(hubSheetMasteryPercent)%",
                        valueColor: Color.vocabBrand
                    )
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.vocabBrand.opacity(0.12))
                        Capsule()
                            .fill(LinearGradient.vocabBrandProgress)
                            .frame(width: geo.size.width * hubSheetMasteryProgress)
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(VocabPressButtonStyle())
        .accessibilityLabel(LocalizedKey.learningProgress.rawValue.localized)
        .accessibilityValue(
            "\(LocalizedKey.mastered.rawValue.localized) \(hubSheetMasteredCount) / \(hubSheetWordCount)，\(LocalizedKey.totalProgress.rawValue.localized) \(hubSheetMasteryPercent)%"
        )
        .accessibilityHint(LocalizedKey.tabProgress.rawValue.localized)
    }
    
    private func hubMetricColumn(
        systemImage: String,
        label: String,
        value: String,
        valueColor: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Click Wheel
    
    private func clickWheelGesture(center: CGPoint, metrics: StudyHubStackMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("hubClickWheel"))
            .onChanged { value in
                let finger = angleFromVertical(center: center, point: value.location)
                let distance = hypot(value.location.x - center.x, value.location.y - center.y)
                // 仅在环带内跟手
                guard distance >= metrics.tealRadius * 0.92,
                      distance <= metrics.orangeRadius * 1.05 else { return }
                
                if let last = ringLastFingerAngle {
                    var delta = finger - last
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }
                    ringDragDegrees += delta
                    if abs(ringDragDegrees) > HubLayout.tapMaxDegrees {
                        ringDidScrub = true
                    }
                    // 越过半格则切换 index（不循环，到头停止）
                    let steps = Int((ringDragDegrees / HubLayout.buttonAngleStep).rounded(.towardZero))
                    if steps != 0, abs(ringDragDegrees) >= HubLayout.buttonAngleStep * 0.55 {
                        let applied = rotateHubRing(by: -steps)
                        if applied != 0 {
                            ringDragDegrees -= Double(-applied) * HubLayout.buttonAngleStep
                        } else {
                            ringDragDegrees = clampRingOverscroll(ringDragDegrees)
                        }
                    } else {
                        ringDragDegrees = clampRingOverscroll(ringDragDegrees)
                    }
                    fireClickWheelTickIfNeeded()
                } else {
                    prepareClickWheelTickBaseline()
                }
                ringLastFingerAngle = finger
            }
            .onEnded { value in
                defer {
                    ringLastFingerAngle = nil
                    ringDidScrub = false
                    ringLastTickIndex = nil
                }
                
                if !ringDidScrub {
                    // 轻点环：选中最靠近触点的项；已选中则启动
                    let finger = angleFromVertical(center: center, point: value.location)
                    if let tapped = nearestAction(toFingerAngle: finger) {
                        if tapped.rawValue == hubActionIndex {
                            activateSelectedHubAction()
                        } else {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                _ = rotateHubRing(by: tapped.rawValue - hubActionIndex)
                                ringDragDegrees = 0
                            }
                        }
                    }
                    return
                }
                
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    let steps = Int((ringDragDegrees / HubLayout.buttonAngleStep).rounded())
                    if steps != 0 {
                        _ = rotateHubRing(by: -steps)
                    }
                    ringDragDegrees = 0
                }
            }
    }
    
    /// 触点相对圆心的方位角：0° 为正上，顺时针为正
    private func angleFromVertical(center: CGPoint, point: CGPoint) -> Double {
        let dx = point.x - center.x
        let dy = center.y - point.y
        return atan2(dx, dy) * 180 / .pi
    }
    
    /// Click Wheel 绝对转角（度）：index 格 + 当前拖拽残差
    private var clickWheelAbsoluteDegrees: Double {
        Double(hubActionIndex) * HubLayout.buttonAngleStep + ringDragDegrees
    }
    
    private func prepareClickWheelTickBaseline() {
        VocabHaptics.prepareSelection()
        ringLastTickIndex = Int(floor(clickWheelAbsoluteDegrees / HubLayout.clickTickStep))
    }
    
    /// 每跨过一小刻度触发一次 selection，模拟 iPod Click Wheel「哒哒」
    private func fireClickWheelTickIfNeeded() {
        let tick = Int(floor(clickWheelAbsoluteDegrees / HubLayout.clickTickStep))
        if let last = ringLastTickIndex, tick != last {
            VocabHaptics.selection()
            VocabHaptics.prepareSelection()
        }
        ringLastTickIndex = tick
    }
    
    /// 到头后限制继续外拨的角度（轻微阻尼，不循环）
    private func clampRingOverscroll(_ degrees: Double) -> Double {
        let limit = HubLayout.buttonAngleStep * 0.32
        let last = hubActions.count - 1
        if hubActionIndex <= 0, degrees > 0 {
            return min(degrees, limit)
        }
        if hubActionIndex >= last, degrees < 0 {
            return max(degrees, -limit)
        }
        return degrees
    }
    
    private func nearestAction(toFingerAngle finger: Double) -> StudyHubAction? {
        var best: StudyHubAction?
        var bestDiff = 180.0
        for action in hubActions {
            let delta = action.rawValue - hubActionIndex
            let itemAngle = Double(delta) * HubLayout.buttonAngleStep + ringDragDegrees
            var diff = abs(finger - itemAngle)
            if diff > 180 { diff = 360 - diff }
            if diff < bestDiff {
                bestDiff = diff
                best = action
            }
        }
        guard let best else { return selectedHubAction }
        return bestDiff <= HubLayout.buttonAngleStep * 1.1 ? best : selectedHubAction
    }
    
    private func visualStep(_ absDelta: Double) -> Int {
        if absDelta < 0.55 { return 0 }
        if absDelta < 1.55 { return 1 }
        return 2
    }
    
    private func opacityForRing(absDelta: Double) -> Double {
        if absDelta < 0.55 { return 1 }
        if absDelta < 1.55 { return 0.85 }
        if absDelta < 2.4 { return 0.55 }
        return 0.28
    }
    
    private func ringDiameter(for absDelta: Int) -> CGFloat {
        switch absDelta {
        case 0: return HubLayout.centerDiameter
        case 1: return HubLayout.sideDiameter
        default: return HubLayout.farDiameter
        }
    }
    
    /// 线性切换，夹在首尾之间；返回实际移动步数
    @discardableResult
    private func rotateHubRing(by step: Int) -> Int {
        let last = hubActions.count - 1
        let newIndex = min(max(hubActionIndex + step, 0), last)
        let applied = newIndex - hubActionIndex
        if applied != 0 {
            // 大刻度吸附：比小刻度 selection 稍重，形成「密哒 + 吸附咔」
            VocabHaptics.impact(.light)
            hubActionIndex = newIndex
        }
        return applied
    }
    
    private func ringActionKnob(action: StudyHubAction, scale: CGFloat, emphasized: Bool) -> some View {
        let disabled = !isHubActionAvailable(action)
        let base = HubLayout.sideDiameter
        return ZStack {
            Circle()
                .fill(Color.vocabSurface)
                .overlay {
                    DiagonalStripePattern(lineColor: Color.vocabInk.opacity(0.45))
                        .opacity(0.18)
                        .clipShape(Circle())
                }
                .opacity(emphasized ? 0 : 1)
            
            Circle()
                .fill(LinearGradient.vocabBrandProgress)
                .opacity(emphasized ? 1 : 0)
            
            Circle()
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
            
            Image(systemName: action.symbol)
                .font(.system(size: base * 0.34, weight: .semibold))
                .foregroundStyle(emphasized ? Color.white : Color.vocabInk.opacity(0.85))
        }
        .frame(width: base, height: base)
        .compositingGroup()
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 4)
        .shadow(color: Color.vocabBrand.opacity(emphasized ? 0.32 : 0), radius: 10, x: 0, y: 4)
        .scaleEffect(scale)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityLabel(action.titleKey.rawValue.localized)
        .accessibilityAddTraits(action.rawValue == hubActionIndex ? .isSelected : [])
        .accessibilityHint(LocalizedKey.hubStart.rawValue.localized)
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
    private func activateSelectedHubAction() {
        let action = selectedHubAction
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
                        .background(Color.vocabCanvas)
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
        .background(reviewModeSelected ? Color.vocabCanvas : Color.clear)
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(Color.vocabInk)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            VStack(spacing: 8) {
                Text(hasForgotten ? LocalizedKey.roundComplete : LocalizedKey.greatJob)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.vocabInk)
                Text(completionMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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

/// 背单词 Hub 全屏氛围底（对齐词库 `LibraryAtmosphereBackground`：外层 ignoresSafeArea）
private struct StudyHubAtmosphereBackground: View {
    var includeBottomTeal: Bool
    
    var body: some View {
        GeometryReader { geo in
            let largeLandscape = StudyHubStackMetrics.isPadLandscapeLarge(geo.size)
            let padLandscape = StudyHubStackMetrics.isPadLandscape(geo.size)
            ZStack(alignment: .top) {
                if includeBottomTeal, largeLandscape {
                    // 13" 横屏：粉（含侧边楔形）/ 青绿；中段不用 Surface，避免奶油卡底色被同化
                    VStack(spacing: 0) {
                        Color.vocabBrand
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Color.vocabTeal
                            .frame(height: geo.size.height * 0.28)
                    }
                } else {
                    Color.vocabBrand
                    
                    if includeBottomTeal {
                        Color.vocabTeal
                            .frame(height: geo.size.height * (padLandscape ? 0.55 : 0.52))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 圆叠圆布局：橙圆 / 青圆同圆心
private struct StudyHubStackMetrics {
    let size: CGSize
    let center: CGPoint
    let orangeRadius: CGFloat
    let tealRadius: CGFloat
    let buttonRadius: CGFloat
    let contentY: CGFloat
    
    /// iPad 类横屏（短边仍够高）：竖屏手机公式会把青圆顶出可视区
    static func isPadLandscape(_ size: CGSize) -> Bool {
        size.width > size.height && size.height >= 560
    }
    
    /// 13" 类横屏（宽 ≥ 1300）：需更平弧 + 三色氛围底
    static func isPadLandscapeLarge(_ size: CGSize) -> Bool {
        isPadLandscape(size) && size.width >= 1300
    }
    
    /// iPad 类竖屏：手机公式橙半径随宽度放大，黄/绿占比过高
    static func isPadPortrait(_ size: CGSize) -> Bool {
        size.height > size.width && size.width >= 600
    }
    
    /// - Parameter stackOffsetY: 随问候区增高同步下移（相对原 headerBlockHeight 88）
    init(size: CGSize, stackOffsetY: CGFloat = 0) {
        self.size = size
        
        let orange: CGFloat
        let centerY: CGFloat
        let teal: CGFloat
        
        if Self.isPadLandscapeLarge(size) {
            // 13" 横屏：上移压奶油、加厚橙环、加大半径压平侧边
            let halfW = size.width * 0.5
            orange = max(size.width * 0.95, size.height * 1.20, halfW * 1.40)
            let minRing: CGFloat = 110
            teal = min(orange * 0.79, orange - minRing)
            let orangeTop = min(max(size.height * 0.42, 320), size.height * 0.46)
            centerY = orangeTop + orange
        } else if Self.isPadLandscape(size) {
            // 宽度主导半径 → 弧更平，左右盖住奶油卡底角（消除白三角）
            let halfW = size.width * 0.5
            orange = max(size.width * 0.90, size.height * 1.15, halfW * 1.35)
            // 环带略宽于上一版，青绿上缘再下移一点
            let minRing: CGFloat = 90
            teal = min(orange * 0.84, orange - minRing)
            // 整圈略下移，减少屏内青绿占比（勿超 ~0.55，以免侧边露白）
            let orangeTop = min(max(size.height * 0.52, 300), size.height * 0.55)
            centerY = orangeTop + orange
        } else if Self.isPadPortrait(size) {
            // 上移压住奶油卡底；加大半径压平左右弧，避免侧边露青绿
            let halfW = size.width * 0.5
            orange = max(
                size.width * 1.10 * 1.40,
                size.height * 0.55 * 1.35,
                halfW * 1.45
            )
            let minRing: CGFloat = 100
            teal = min(orange * 0.78, orange - minRing)
            // 约对齐奶油进度区下缘，叠进卡底透明区
            let orangeTop = min(max(size.height * 0.36, 340), size.height * 0.40)
            centerY = orangeTop + orange
        } else {
            // 第三部分：橙圆放大，但避免过大顶穿奶油卡
            orange = min(size.width * 0.92, size.height * 0.74) * 1.65
            // 圆心尽量下移：橙圆上缘落在奶油卡进度区下方，露出奶油卡
            let creamSafeBottom: CGFloat = 360
            centerY = max(size.height * 1.18 + stackOffsetY, creamSafeBottom + orange)
            let minRing: CGFloat = 150
            teal = min(orange * 0.70, orange - minRing)
        }
        
        self.orangeRadius = orange
        let center = CGPoint(x: size.width * 0.5, y: centerY)
        self.center = center
        self.tealRadius = teal
        // 第五部分：与橙/青同圆心，半径取二者中间
        self.buttonRadius = (orange + teal) * 0.5
        // 标题/说明锚在青绿圆内
        let tealTop = center.y - teal
        if Self.isPadLandscape(size) || Self.isPadPortrait(size) {
            // 按「屏内可见青绿」锚点，避免被 height*0.86 夹到橙环上
            let visible = max(size.height - tealTop, 0)
            let factor: CGFloat = Self.isPadPortrait(size) ? 0.38 : 0.42
            self.contentY = tealTop + visible * factor
        } else {
            self.contentY = min(tealTop + teal * 0.58, size.height * 0.86)
        }
    }
    
    func point(on radius: CGFloat, angleFromVerticalDegrees: Double) -> CGPoint {
        let rad = angleFromVerticalDegrees * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(sin(rad)) * radius,
            y: center.y - CGFloat(cos(rad)) * radius
        )
    }
}


/// Click Wheel 热区：外圆减内圆
private struct StudyHubAnnulus: Shape {
    var center: CGPoint
    var outerRadius: CGFloat
    var innerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(
            x: center.x - outerRadius,
            y: center.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))
        path.addEllipse(in: CGRect(
            x: center.x - innerRadius,
            y: center.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        ))
        return path
    }
}

/// 青绿圆 + 上缘尖角（同一填充，避免尖角透出橙环）
private struct HubTealDiskWithNotch: Shape {
    var center: CGPoint
    var radius: CGFloat
    var notchWidth: CGFloat = 36
    var notchHeight: CGFloat = 22
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        let tipY = center.y - radius - notchHeight
        let baseY = center.y - radius + 2
        path.move(to: CGPoint(x: center.x, y: tipY))
        path.addLine(to: CGPoint(x: center.x + notchWidth / 2, y: baseY))
        path.addLine(to: CGPoint(x: center.x - notchWidth / 2, y: baseY))
        path.closeSubpath()
        return path
    }
}

/// Click Wheel 钟表刻度（沿橙/青中间半径）
private struct HubClickWheelTicks: Shape {
    var center: CGPoint
    var radius: CGFloat
    var minorStep: Double = 3
    var majorStep: Double = 15
    var minorLength: CGFloat = 11
    var majorLength: CGFloat = 20
    /// 从正上方起算的可见弧范围（度）
    var startAngle: Double = -110
    var endAngle: Double = 110
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var angle = startAngle
        while angle <= endAngle + 0.001 {
            let mod = angle.truncatingRemainder(dividingBy: majorStep)
            let isMajor = abs(mod) < 0.01 || abs(abs(mod) - majorStep) < 0.01
            let len = isMajor ? majorLength : minorLength
            let rad = angle * .pi / 180
            let s = CGFloat(sin(rad))
            let c = CGFloat(cos(rad))
            let inner = radius - len * 0.5
            let outer = radius + len * 0.5
            path.move(to: CGPoint(x: center.x + s * inner, y: center.y - c * inner))
            path.addLine(to: CGPoint(x: center.x + s * outer, y: center.y - c * outer))
            angle += minorStep
        }
        return path
    }
}
