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
    @State private var showAddWord = false
    @State private var showSettings = false
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var dailyMotivation: String = {
        // 初始化时尝试加载缓存的激励语
        let userDefaults = UserDefaults.standard
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        
        // 检查是否已经有今天的激励语，并且语言匹配
        if let savedDate = userDefaults.string(forKey: "dailyMotivationDate"),
           savedDate == todayString,
           let savedLanguage = userDefaults.string(forKey: "dailyMotivationLanguage"),
           savedLanguage == AppSettingsManager.shared.language.rawValue,
           let savedMotivation = userDefaults.string(forKey: "dailyMotivationText"),
           !savedMotivation.isEmpty {
            return savedMotivation
        }
        return LocalizedKey.dailyMotivation.rawValue.localized
    }()
    @State private var isLoadingMotivation = false
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
    
    private var studyQueue: [Word] {
        words.filter { !$0.learned }
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
            dailyMotivation = savedMotivation
            return
        }
        
        // 如果没有今天的激励语，或者语言不匹配，则获取新的
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
            // 如果获取失败，保持默认值
            print("获取每日激励语失败: \(error.localizedDescription)")
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
                            .font(.system(size: 48, weight: .black, design: .rounded))
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
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.indigo, Color.purple]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(LocalizedKey.totalProgress.rawValue.localized) \(progress)%，\(LocalizedKey.mastered.rawValue.localized) \(mastered) 个，\(LocalizedKey.toLearn.rawValue.localized) \(total - mastered) 个")
                
                // 操作按钮
                HStack(spacing: 16) {
                    Button(action: {
                        selectedTab = .study
                    }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "book.fill")
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .frame(width: 48, height: 48)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedKey.startReview)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(studyQueue.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(LocalizedKey.startReview.rawValue.localized)，\(studyQueue.count)\(LocalizedKey.wordsToReview.rawValue.localized)")
                    
                    Button(action: {
                        showAddWord = true
                    }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.primary)
                                .frame(width: 48, height: 48)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedKey.addNewWord)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(LocalizedKey.aiSmartFill)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(LocalizedKey.addNewWord.rawValue.localized)，\(LocalizedKey.aiSmartFill.rawValue.localized)")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                
                // 最近添加
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(LocalizedKey.recentlyAdded)
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button(action: {
                            selectedTab = .list
                        }) {
                            Text(LocalizedKey.viewAll)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                        .accessibilityLabel("\(LocalizedKey.viewAll.rawValue.localized) \(LocalizedKey.word.rawValue.localized)")
                    }
                    .padding(.horizontal, 20)
                    
                    if words.isEmpty {
                        if #available(iOS 17.0, *) {
                            ContentUnavailableView {
                                Label(LocalizedKey.noWordsYet.rawValue.localized, systemImage: "book.closed")
                            } description: {
                                Text(LocalizedKey.goAddWords)
                            }
                            .padding(.vertical, 40)
                            .offset(y: -20)
                        } else {
                            VStack(spacing: 16) {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.tertiary)
                                Text(LocalizedKey.goAddWords)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .offset(y: -20)
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(words.prefix(3))) { word in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(word.term)
                                            .font(.headline)
                                        Text(word.definition)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if word.learned {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .font(.title3)
                                    } else {
                                        Image(systemName: "circle.fill")
                                            .foregroundStyle(.orange.opacity(0.4))
                                            .font(.title3)
                                    }
                                }
                                .padding(16)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(word.term)，\(word.definition)，\(word.learned ? LocalizedKey.mastered.rawValue.localized : LocalizedKey.toLearn.rawValue.localized)")
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            checkAndUpdateDailyMotivation()
        }
        .onChange(of: settingsManager.language) { oldValue, newValue in
            // 语言切换时，重新获取激励语
            checkAndUpdateDailyMotivation()
        }
        .sheet(isPresented: $showAddWord) {
            AddWordView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

enum AppView {
    case home
    case study
    case list
}
