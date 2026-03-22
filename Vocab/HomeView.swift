//
//  HomeView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query private var words: [Word]
    @Binding var selectedTab: AppView
    @State private var showSettings = false
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var dailyMotivation: String = LocalizedKey.dailyMotivation.rawValue.localized
    @State private var isLoadingMotivation = false
    @State private var showPaywall = false
    @ObservedObject private var settingsManager = AppSettingsManager.shared
    
    private let userDefaults = UserDefaults.standard
    private let motivationDateKey = "dailyMotivationDate"
    private let motivationTextKey = "dailyMotivationText"
    private let motivationLanguageKey = "dailyMotivationLanguage"
    
    private var mastered: Int {
        words.filter { $0.learned }.count
    }
    
    private var total: Int {
        words.count
    }
    
    private var progress: Int {
        guard total > 0 else { return 0 }
        return Int((Double(mastered) / Double(total)) * 100)
    }
    
    private var vocabularyEnergyPoints: Int {
        VocabularyEnergy.totalPoints(for: words)
    }
    
    private var formattedVocabularyEnergyPoints: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: vocabularyEnergyPoints)) ?? "\(vocabularyEnergyPoints)"
    }
    
    private var vocabularyEnergyLevel: Int {
        let p = vocabularyEnergyPoints
        switch p {
        case ..<80: return 1
        case 80..<200: return 2
        case 200..<400: return 3
        case 400..<700: return 4
        default: return 5
        }
    }
    
    private var vocabularyEnergyTierBounds: (start: Int, next: Int) {
        switch vocabularyEnergyLevel {
        case 1: return (0, 80)
        case 2: return (80, 200)
        case 3: return (200, 400)
        case 4: return (400, 700)
        default: return (700, 700)
        }
    }
    
    private var vocabularyEnergyProgressToNext: Double {
        let (start, next) = vocabularyEnergyTierBounds
        guard vocabularyEnergyLevel < 5, next > start else { return 1 }
        let span = Double(next - start)
        return min(1, max(0, Double(vocabularyEnergyPoints - start) / span))
    }
    
    private var vocabularyEnergyTierTitle: String {
        switch vocabularyEnergyLevel {
        case 1: return LocalizedKey.vocabularyEnergyTier1Title.rawValue.localized
        case 2: return LocalizedKey.vocabularyEnergyTier2Title.rawValue.localized
        case 3: return LocalizedKey.vocabularyEnergyTier3Title.rawValue.localized
        case 4: return LocalizedKey.vocabularyEnergyTier4Title.rawValue.localized
        default: return LocalizedKey.vocabularyEnergyTier5Title.rawValue.localized
        }
    }
    
    private var vocabularyEnergyTierSubtitle: String {
        switch vocabularyEnergyLevel {
        case 1: return LocalizedKey.vocabularyEnergyTier1Subtitle.rawValue.localized
        case 2: return LocalizedKey.vocabularyEnergyTier2Subtitle.rawValue.localized
        case 3: return LocalizedKey.vocabularyEnergyTier3Subtitle.rawValue.localized
        case 4: return LocalizedKey.vocabularyEnergyTier4Subtitle.rawValue.localized
        default: return LocalizedKey.vocabularyEnergyTier5Subtitle.rawValue.localized
        }
    }
    
    /// 相对约 7 天前（有快照的最近一日）的能量变化；无足够历史时为 nil
    private var vocabularyEnergySevenDayDelta: Int? {
        guard let baseline = VocabularyEnergySnapshotStore.baselineEnergySevenDaysAgo() else { return nil }
        return vocabularyEnergyPoints - baseline
    }
    
    private func vocabularyEnergyDeltaDisplayText(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        return "\(delta)"
    }
    
    private var vocabularyEnergyAccessibilityLabel: String {
        var parts: [String] = [
            LocalizedKey.vocabularyEnergy.rawValue.localized,
            "\(LocalizedKey.vocabularyEnergyScoreLabel.rawValue.localized) \(formattedVocabularyEnergyPoints)"
        ]
        if let d = vocabularyEnergySevenDayDelta {
            parts.append("\(LocalizedKey.vocabularyEnergyLast7Days.rawValue.localized) \(vocabularyEnergyDeltaDisplayText(d))")
        } else {
            parts.append(LocalizedKey.vocabularyEnergyLast7DaysPending.rawValue.localized)
        }
        parts.append("\(vocabularyEnergyTierTitle)。\(vocabularyEnergyTierSubtitle)")
        return parts.joined(separator: "，")
    }
    
    // 根据当前时间返回问候语
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
    
    // 获取用户名，如果没有则显示默认值
    private var displayName: String {
        if let userName = authManager.userName, !userName.isEmpty {
            return userName
        }
        return "Learner"
    }
    
    // 检查并获取每日激励语
    private func checkAndUpdateDailyMotivation() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        let currentLanguage = settingsManager.language.rawValue
        
        // 检查是否已经有今天的激励语，并且语言匹配
        if let savedDate = userDefaults.string(forKey: motivationDateKey),
           savedDate == todayString,
           let savedLanguage = userDefaults.string(forKey: motivationLanguageKey),
           savedLanguage == currentLanguage,
           let savedMotivation = userDefaults.string(forKey: motivationTextKey),
           !savedMotivation.isEmpty {
            // 如果已经有今天的激励语，直接使用
            dailyMotivation = savedMotivation
            return
        }
        
        // 如果没有今天的激励语，或者日期不匹配，或者语言不匹配，则获取新的
        // 先显示默认值，然后异步获取新的
        dailyMotivation = LocalizedKey.dailyMotivation.rawValue.localized
        Task {
            await fetchDailyMotivation()
        }
    }
    
    // 从 API 获取每日激励语
    @MainActor
    private func fetchDailyMotivation() async {
        isLoadingMotivation = true
        defer { isLoadingMotivation = false }
        
        do {
            let motivation = try await DeepseekService.shared.generateDailyMotivation()
            dailyMotivation = motivation
            
            // 保存到 UserDefaults
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let todayString = dateFormatter.string(from: today)
            
            userDefaults.set(todayString, forKey: motivationDateKey)
            userDefaults.set(motivation, forKey: motivationTextKey)
            userDefaults.set(settingsManager.language.rawValue, forKey: motivationLanguageKey)
        } catch {
            // 检查是否是次数不足的错误
            if let serviceError = error as? DeepseekServiceError,
               case .noRemainingCalls = serviceError {
                showPaywall = true
            } else {
                // 如果获取失败，保持默认值
                print("获取每日激励语失败: \(error.localizedDescription)")
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 头部
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.title)
                            .fontWeight(.black)
                        Text("\(displayName)!")
                            .font(.title)
                            .fontWeight(.black)
                        Text(dailyMotivation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("设置")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
                
                // 进度卡片
                VStack(alignment: .leading, spacing: 16) {
                    Text(LocalizedKey.totalProgress)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.9))
                        .textCase(.uppercase)
                        .tracking(1)
                    
                    HStack(alignment: .bottom, spacing: 8) {
                        Text("\(progress)")
                            .font(.system(size: 48, weight: .black))
                            .foregroundStyle(.white)
                        Text("%")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.bottom, 8)
                        Text(LocalizedKey.mastered)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.bottom, 4)
                    }
                    
                    // 进度条
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(.white.opacity(0.25))
                                .frame(height: 8)
                                .clipShape(Capsule())
                            
                            Rectangle()
                                .fill(.white)
                                .frame(width: geometry.size.width * CGFloat(progress) / 100, height: 8)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("\(LocalizedKey.mastered.rawValue.localized): \(mastered)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.9))
                        
                        Spacer()
                        
                        Text("\(LocalizedKey.toLearn.rawValue.localized): \(total - mastered)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .background(LinearGradient.vocabBrandProgress)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(LocalizedKey.totalProgress.rawValue.localized) \(progress)%，\(LocalizedKey.mastered.rawValue.localized) \(mastered) 个，\(LocalizedKey.toLearn.rawValue.localized) \(total - mastered) 个")
                
                // 词汇能量
                VStack(alignment: .leading, spacing: 16) {
                    Text(LocalizedKey.vocabularyEnergy)
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.horizontal, 20)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "bolt.fill")
                                .font(.title)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "FFB020"), Color(hex: "FE6A57")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 48, height: 48)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            // 数字独占一行宽度，避免与「近 7 天」同一行抢空间导致大数换行
                            VStack(alignment: .leading, spacing: 10) {
                                Text(LocalizedKey.vocabularyEnergyScoreLabel.rawValue.localized)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .tracking(0.6)
                                
                                Text(formattedVocabularyEnergyPoints)
                                    .font(.system(size: 36, weight: .black, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.55)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Spacer(minLength: 0)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(LocalizedKey.vocabularyEnergyLast7Days.rawValue.localized)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                        if let delta = vocabularyEnergySevenDayDelta {
                                            Text(vocabularyEnergyDeltaDisplayText(delta))
                                                .font(.title3)
                                                .fontWeight(.bold)
                                                .foregroundStyle(delta >= 0 ? Color.green : Color.red)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                        } else {
                                            Text(LocalizedKey.vocabularyEnergyLast7DaysPending.rawValue.localized)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                                .multilineTextAlignment(.trailing)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(vocabularyEnergyTierTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(vocabularyEnergyTierSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        if vocabularyEnergyLevel < 5 {
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: vocabularyEnergyProgressToNext)
                                    .tint(Color(hex: "FE6A57"))
                                Text(
                                    String(
                                        format: LocalizedKey.vocabularyEnergyNextHint.rawValue.localized,
                                        max(0, vocabularyEnergyTierBounds.next - vocabularyEnergyPoints)
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }
                        
                        Button(action: {
                            selectedTab = .study
                        }) {
                            Label(LocalizedKey.startReview.rawValue.localized, systemImage: "brain.head.profile")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(LinearGradient.vocabBrandProgress)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 20)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(vocabularyEnergyAccessibilityLabel)
                }
                .padding(.bottom, 100)
            }
        }
        .background(Color(.systemGroupedBackground))
        .task {
            // 使用 task 确保每次视图出现时都会检查并更新
            checkAndUpdateDailyMotivation()
            VocabularyEnergySnapshotStore.recordSnapshot(currentEnergy: vocabularyEnergyPoints)
        }
        .onChange(of: vocabularyEnergyPoints) { _, newValue in
            VocabularyEnergySnapshotStore.recordSnapshot(currentEnergy: newValue)
        }
        .onChange(of: settingsManager.language) { oldValue, newValue in
            // 语言切换时，重新获取激励语
            checkAndUpdateDailyMotivation()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}

enum AppView {
    case home
    case study
    case list
}

// MARK: - 词汇能量每日快照（用于近 7 天变化）
private enum VocabularyEnergySnapshotStore {
    private static let defaults = UserDefaults.standard
    private static let storageKey = "vocabularyEnergySnapshotsByDay"
    private static let retentionDays = 34
    
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: Calendar.current.startOfDay(for: date))
    }
    
    private static func load() -> [String: Int] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return decoded
    }
    
    private static func save(_ map: [String: Int]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: storageKey)
    }
    
    static func recordSnapshot(currentEnergy: Int) {
        var map = load()
        map[dayKey(for: Date())] = currentEnergy
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -retentionDays, to: cal.startOfDay(for: Date())) else {
            save(map)
            return
        }
        let cutoffKey = dayKey(for: cutoff)
        map = map.filter { $0.key >= cutoffKey }
        save(map)
    }
    
    /// 取「今天往前第 7 个自然日」当日或之前最近一条快照的能量值
    static func baselineEnergySevenDaysAgo() -> Int? {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let targetDate = cal.date(byAdding: .day, value: -7, to: todayStart) else { return nil }
        let targetKey = dayKey(for: targetDate)
        let map = load()
        guard let bestKey = map.keys.filter({ $0 <= targetKey }).max() else { return nil }
        return map[bestKey]
    }
}
