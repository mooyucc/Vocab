//
//  ProgressTabView.swift
//  Vocab
//
//  打卡、掌握度等学习统计（参考 Learning plan 布局）。
//

import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    @Binding var selectedTab: AppView
    @EnvironmentObject var authManager: AuthenticationManager
    @Query private var words: [Word]
    @ObservedObject private var settingsManager = AppSettingsManager.shared
    
    @State private var showSettings = false
    @State private var selectedMonthId: Date?
    
    private enum Layout {
        static let horizontalInset: CGFloat = 20
        static let cardCorner: CGFloat = VocabTheme.Radius.card
        static let masteryRingSize: CGFloat = 112
        static let masteryRingLine: CGFloat = 14
        static let monthCount = 6
    }
    
    private struct CheckInDay: Identifiable {
        let id: Date
        let label: String
        let checked: Bool
    }
    
    private struct MonthActivity: Identifiable {
        let id: Date
        let label: String
        let count: Int
    }
    
    private var locale: Locale {
        Locale(identifier: settingsManager.language.rawValue)
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
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE, d MMM")
        return formatter.string(from: Date())
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
        formatter.locale = locale
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
    
    private var weekCheckedCount: Int {
        checkInDays.filter(\.checked).count
    }
    
    private var weekProgress: Double {
        Double(weekCheckedCount) / 7.0
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
    
    private var masteredCount: Int {
        words.filter(\.learned).count
    }
    
    private var dueCount: Int {
        SpacedRepetition.dueWords(from: words).count
    }
    
    private var masteryProgress: Double {
        guard !words.isEmpty else { return 0 }
        return Double(masteredCount) / Double(words.count)
    }
    
    private var masteryPercent: Int {
        Int((masteryProgress * 100).rounded())
    }
    
    private var monthlyActivity: [MonthActivity] {
        let calendar = Calendar.current
        let now = Date()
        guard let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
            return []
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        
        var counts: [Date: Int] = [:]
        for word in words {
            guard let last = word.lastReviewed else { continue }
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: last)) else { continue }
            counts[monthStart, default: 0] += 1
        }
        
        return (0..<Layout.monthCount).compactMap { offset in
            let monthsBack = Layout.monthCount - 1 - offset
            guard let month = calendar.date(byAdding: .month, value: -monthsBack, to: currentMonth) else { return nil }
            return MonthActivity(
                id: month,
                label: formatter.string(from: month),
                count: counts[month, default: 0]
            )
        }
    }
    
    private var resolvedSelectedMonthId: Date {
        if let selectedMonthId,
           monthlyActivity.contains(where: { $0.id == selectedMonthId }) {
            return selectedMonthId
        }
        return monthlyActivity.last?.id ?? Date()
    }
    
    private var selectedMonthActivity: MonthActivity? {
        monthlyActivity.first(where: { $0.id == resolvedSelectedMonthId })
    }
    
    private var chartYearText: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("y")
        return formatter.string(from: resolvedSelectedMonthId)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        EmptyLibraryPrompt(
                            title: LocalizedKey.learningProgress.rawValue.localized,
                            systemImage: "chart.bar.fill"
                        ) {
                            selectedTab = .list
                        }
                    }
                    .padding(.horizontal, Layout.horizontalInset)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            header
                            Text(LocalizedKey.learningProgress)
                                .font(.title.weight(.bold))
                                .fontDesign(.rounded)
                                .foregroundStyle(Color.vocabInk)
                            masteryHero
                            checkInSummaryCard
                            activityChartSection
                        }
                        .padding(.horizontal, Layout.horizontalInset)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Color.vocabCanvas)
            .toolbar(.hidden, for: .navigationBar)
        }
        .background(Color.vocabCanvas)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            if selectedMonthId == nil {
                selectedMonthId = monthlyActivity.last?.id
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            UserAvatarView(
                image: authManager.avatarImage,
                userName: authManager.userName ?? displayName,
                size: 60,
                style: .onCanvas
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(greeting)\(displayName)")
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.vocabInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(todayDateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.vocabSurface)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LocalizedKey.settings.rawValue.localized)
        }
    }
    
    // MARK: - Check-in Card
    
    private var checkInSummaryCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.vocabInk.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: weekProgress)
                    .stroke(
                        Color.vocabGold,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(LocalizedKey.thisWeek)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.vocabInk.opacity(0.55))
                    Spacer(minLength: 0)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.vocabGold)
                    Text("\(checkInStreak)")
                        .font(.headline.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(Color.vocabInk)
                    Text(LocalizedKey.consecutiveDays)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.vocabInk.opacity(0.55))
                }
                
                HStack(spacing: 0) {
                    ForEach(checkInDays) { day in
                        VStack(spacing: 4) {
                            Circle()
                                .fill(day.checked ? Color.vocabGold : Color.clear)
                                .overlay(
                                    Circle().stroke(
                                        day.checked
                                            ? Color.vocabGold
                                            : Color.vocabInk.opacity(0.22),
                                        lineWidth: 1.5
                                    )
                                )
                                .frame(width: 9, height: 9)
                            Text(day.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.vocabInk.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                .fill(Color.vocabSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cardCorner, style: .continuous)
                        .strokeBorder(Color.vocabGold.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(LocalizedKey.checkIn.rawValue.localized)，\(checkInStreak)\(LocalizedKey.consecutiveDays.rawValue.localized)，\(LocalizedKey.thisWeek.rawValue.localized) \(weekCheckedCount)/7"
        )
    }
    
    // MARK: - Mastery Hero
    
    private var masteryHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(masteryPercent)%")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.vocabInk)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(LocalizedKey.totalProgress)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                masteryRing
            }
            
            HStack(spacing: 12) {
                Text(
                    String(
                        format: LocalizedKey.masteredCountFormat.rawValue.localized,
                        masteredCount,
                        words.count
                    )
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.vocabInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                
                Text("·")
                    .foregroundStyle(.tertiary)
                
                Text("\(LocalizedKey.libraryFilterDue.rawValue.localized) \(dueCount)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(LocalizedKey.totalProgress.rawValue.localized) \(masteryPercent)%，\(String(format: LocalizedKey.masteredCountFormat.rawValue.localized, masteredCount, words.count))，\(LocalizedKey.libraryFilterDue.rawValue.localized) \(dueCount)"
        )
        .animation(.easeOut(duration: 0.25), value: masteryPercent)
    }
    
    private var masteryRing: some View {
        ZStack {
            Circle()
                .stroke(Color.vocabBrand.opacity(0.14), lineWidth: Layout.masteryRingLine)
            Circle()
                .trim(from: 0, to: masteryProgress)
                .stroke(
                    AngularGradient(
                        colors: [Color.vocabBrand, Color.vocabBrandDeep, Color.vocabBrand],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: Layout.masteryRingLine, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Layout.masteryRingSize, height: Layout.masteryRingSize)
        .accessibilityHidden(true)
    }
    
    // MARK: - Activity Chart
    
    private var activityChartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(String(format: LocalizedKey.reviewActivityMonthsFormat.rawValue.localized, Layout.monthCount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.vocabInk)
                Spacer()
                Text(chartYearText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            chartBody
                .frame(height: 180)
            
            Text(LocalizedKey.reviewActivity)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
    
    private var chartBody: some View {
        let points = monthlyActivity
        let selectedId = resolvedSelectedMonthId
        let maxCount = max(points.map(\.count).max() ?? 0, 1)
        
        return Chart(points) { point in
            AreaMark(
                x: .value("Month", point.id, unit: .month),
                y: .value("Count", point.count)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.vocabBrand.opacity(0.35), Color.vocabBrand.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            LineMark(
                x: .value("Month", point.id, unit: .month),
                y: .value("Count", point.count)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            .foregroundStyle(Color.vocabBrand)
            
            if point.id == selectedId {
                PointMark(
                    x: .value("Month", point.id, unit: .month),
                    y: .value("Count", point.count)
                )
                .symbolSize(72)
                .foregroundStyle(Color.vocabInk)
                .annotation(position: .top, spacing: 8) {
                    Text("\(point.count)")
                        .font(.caption.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(Color.vocabCanvas)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.vocabInk))
                }
            }
        }
        .chartYScale(domain: 0...Double(maxCount) * 1.25)
        .chartXAxis {
            AxisMarks(values: points.map(\.id)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self),
                       let point = points.first(where: { $0.id == date }) {
                        Text(point.label)
                            .font(.caption2.weight(date == selectedId ? .semibold : .regular))
                            .foregroundStyle(date == selectedId ? Color.vocabInk : Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background {
                                if date == selectedId {
                                    Capsule()
                                        .strokeBorder(Color.vocabInk.opacity(0.35), lineWidth: 1)
                                }
                            }
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let x = value.location.x
                                guard let plotFrame = proxy.plotFrame else { return }
                                let plotX = x - geo[plotFrame].origin.x
                                guard let date: Date = proxy.value(atX: plotX) else { return }
                                if let nearest = nearestMonth(to: date, in: points) {
                                    selectedMonthId = nearest
                                }
                            }
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LocalizedKey.reviewActivity.rawValue.localized)
        .accessibilityValue(
            selectedMonthActivity.map { "\($0.label)，\($0.count)" } ?? ""
        )
    }
    
    private func nearestMonth(to date: Date, in points: [MonthActivity]) -> Date? {
        let calendar = Calendar.current
        guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return points.min(by: { abs($0.id.timeIntervalSince(date)) < abs($1.id.timeIntervalSince(date)) })?.id
        }
        if points.contains(where: { $0.id == month }) { return month }
        return points.min(by: { abs($0.id.timeIntervalSince(date)) < abs($1.id.timeIntervalSince(date)) })?.id
    }
}

#Preview {
    ProgressTabView(selectedTab: .constant(.progress))
        .environmentObject(AuthenticationManager.shared)
        .modelContainer(for: [Word.self, WordSheet.self], inMemory: true)
}
