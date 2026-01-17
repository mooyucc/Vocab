//
//  LocalizedString.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import Foundation
import SwiftUI
import Combine

/// 本地化字符串辅助类
/// 根据 AppSettingsManager 的语言设置返回对应的本地化字符串
class LocalizedString: ObservableObject {
    static let shared = LocalizedString()
    
    @Published private var currentLanguage: AppLanguage
    
    private init() {
        self.currentLanguage = AppSettingsManager.shared.language
        // 监听语言变化
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppLanguageChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.currentLanguage = AppSettingsManager.shared.language
        }
    }
    
    /// 获取本地化字符串
    /// - Parameter key: 本地化键
    /// - Returns: 本地化后的字符串
    func localized(_ key: String) -> String {
        let languageCode = currentLanguage.rawValue
        let bundle = Bundle.main
        
        // 尝试从指定语言的 bundle 中获取
        if let path = bundle.path(forResource: languageCode, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            let localized = languageBundle.localizedString(forKey: key, value: nil, table: nil)
            // 如果返回的字符串和 key 相同，说明没有找到本地化，尝试从主 bundle 获取
            if localized != key {
                return localized
            }
        }
        
        // 如果找不到，尝试从主 bundle 获取
        let mainLocalized = bundle.localizedString(forKey: key, value: nil, table: nil)
        return mainLocalized != key ? mainLocalized : key
    }
}

/// SwiftUI 扩展，方便在视图中使用
extension String {
    /// 本地化字符串
    var localized: String {
        LocalizedString.shared.localized(self)
    }
}

/// 日期格式化辅助函数
extension DateFormatter {
    /// 根据当前语言设置获取日期格式
    static func localizedDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        let language = AppSettingsManager.shared.language
        if language == .chinese {
            formatter.locale = Locale(identifier: "zh_Hans")
            formatter.dateFormat = "yyyy年M月d日"
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMMM d, yyyy"
        }
        return formatter
    }
    
    /// 格式化日期为本地化字符串
    static func localizedDateString(from date: Date) -> String {
        let formatter = localizedDateFormatter()
        return formatter.string(from: date)
    }
}

/// WordSheet 扩展，用于格式化显示名称
extension WordSheet {
    /// 获取本地化格式的显示名称
    /// 如果名称是日期格式，则根据当前语言重新格式化
    var localizedDisplayName: String {
        // 尝试解析名称是否为日期格式
        let chineseFormatter = DateFormatter()
        chineseFormatter.locale = Locale(identifier: "zh_Hans")
        chineseFormatter.dateFormat = "yyyy年M月d日"
        
        let englishFormatter = DateFormatter()
        englishFormatter.locale = Locale(identifier: "en_US")
        englishFormatter.dateFormat = "MMMM d, yyyy"
        
        // 先尝试用中文格式解析
        if let date = chineseFormatter.date(from: name) {
            return DateFormatter.localizedDateString(from: date)
        }
        
        // 再尝试用英文格式解析
        if let date = englishFormatter.date(from: name) {
            return DateFormatter.localizedDateString(from: date)
        }
        
        // 如果名称看起来像日期格式但解析失败，尝试使用 createdAt 日期
        // 检查名称是否包含日期相关的字符
        if name.contains("年") || name.contains("月") || name.contains("日") || 
           name.contains("January") || name.contains("February") || name.contains("March") ||
           name.contains("April") || name.contains("May") || name.contains("June") ||
           name.contains("July") || name.contains("August") || name.contains("September") ||
           name.contains("October") || name.contains("November") || name.contains("December") ||
           name.contains("一月") || name.contains("二月") || name.contains("三月") ||
           name.contains("四月") || name.contains("五月") || name.contains("六月") ||
           name.contains("七月") || name.contains("八月") || name.contains("九月") ||
           name.contains("十月") || name.contains("十一月") || name.contains("十二月") {
            // 如果名称看起来像日期但无法解析，使用 createdAt
            return DateFormatter.localizedDateString(from: createdAt)
        }
        
        // 如果无法解析为日期，直接返回名称
        return name
    }
}

/// Text 视图扩展，直接使用本地化字符串
extension Text {
    init(_ key: LocalizedKey) {
        self.init(key.rawValue.localized)
    }
}

/// 本地化键枚举，确保类型安全
enum LocalizedKey: String {
    // MARK: - Common
    case settings = "settings"
    case done = "done"
    case cancel = "cancel"
    case confirm = "confirm"
    case save = "save"
    case delete = "delete"
    case ok = "ok"
    case yes = "yes"
    case no = "no"
    
    // MARK: - Tab Bar
    case tabProgress = "tab_progress"
    case tabStudy = "tab_study"
    case tabWordList = "tab_word_list"
    
    // MARK: - Home
    case goodMorning = "good_morning"
    case goodAfternoon = "good_afternoon"
    case goodEvening = "good_evening"
    case totalProgress = "total_progress"
    case mastered = "mastered"
    case toLearn = "to_learn"
    case startReview = "start_review"
    case addNewWord = "add_new_word"
    case recentlyAdded = "recently_added"
    case viewAll = "view_all"
    case noWordsYet = "no_words_yet"
    case goAddWords = "go_add_words"
    case dailyMotivation = "daily_motivation"
    case wordsToReview = "words_to_review"
    case aiSmartFill = "ai_smart_fill"
    
    // MARK: - Settings
    case account = "account"
    case general = "general"
    case data = "data"
    case app = "app"
    case about = "about"
    case help = "help"
    case signOut = "sign_out"
    case signOutConfirm = "sign_out_confirm"
    case language = "language"
    case appearance = "appearance"
    case appearanceDescription = "appearance_description"
    case languageDescription = "language_description"
    
    // MARK: - Add Word
    case word = "word"
    case definition = "definition"
    case partOfSpeech = "part_of_speech"
    case pronunciation = "pronunciation"
    case example = "example"
    case translation = "translation"
    case wordSheet = "word_sheet"
    case wordSheetDescription = "word_sheet_description"
    case saveWord = "save_word"
    case addNewWordTitle = "add_new_word_title"
    case aiFill = "ai_fill"
    case cameraRecognize = "camera_recognize"
    case aiGenerateFailed = "ai_generate_failed"
    case selectRecognitionRegion = "select_recognition_region"
    case recognizeFullImage = "recognize_full_image"
    case recognizeSelectedRegion = "recognize_selected_region"
    
    // MARK: - Study
    case focusMode = "focus_mode"
    case recommendedReview = "recommended_review"
    case recommendedReviewDescription = "recommended_review_description"
    case recommendedReviewCompleted = "recommended_review_completed"
    case reviewAll = "review_all"
    case reviewAllDescription = "review_all_description"
    case continueLast = "continue_last"
    case continueLastDescription = "continue_last_description"
    case forgot = "forgot"
    case remembered = "remembered"
    case dailyGoal = "daily_goal"
    case clickToFlip = "click_to_flip"
    case question = "question"
    case answer = "answer"
    case aiUpdateExample = "ai_update_example"
    case reviewPrompt = "review_prompt"
    case reviewAgain = "review_again"
    case later = "later"
    case allWordsReviewed = "all_words_reviewed"
    case todayWordsReviewed = "today_words_reviewed"
    case goAddNewWords = "go_add_new_words"
    case roundComplete = "round_complete"
    case wordsNeedReview = "words_need_review"
    case selectWordSheet = "select_word_sheet"
    case allSheets = "all_sheets"
    case playPronunciation = "play_pronunciation"
    
    // MARK: - Batch Add
    case batchAddWords = "batch_add_words"
    case noWordsRecognized = "no_words_recognized"
    case recognizedWords = "recognized_words"
    case selectAll = "select_all"
    case deselectAll = "deselect_all"
    case selectedCount = "selected_count"
    case adding = "adding"
    case batchAdd = "batch_add"
    case addFailed = "add_failed"
    case noWordsRecognizedError = "no_words_recognized_error"
    case recognizeFailed = "recognize_failed"
    
    // MARK: - Data Settings
    case localData = "local_data"
    case importData = "import_data"
    case exportData = "export_data"
    case dataBackup = "data_backup"
    case deleteAccount = "delete_account"
    case deleteAccountDescription = "delete_account_description"
    case deleteAccountWarning = "delete_account_warning"
    case deleteAccountConfirm = "delete_account_confirm"
    case confirmDelete = "confirm_delete"
    case dataExported = "data_exported"
    case dataImported = "data_imported"
    case exportSuccess = "export_success"
    case importSuccess = "import_success"
    case importFailed = "import_failed"
    
    // MARK: - Word List
    case myWordList = "my_word_list"
    case searchWords = "search_words"
    case noResults = "no_results"
    case tryOtherKeywords = "try_other_keywords"
    
    // MARK: - About
    case version = "version"
    case features = "features"
    case updates = "updates"
    case coreFeatures = "core_features"
    case versionHistory = "version_history"
    
    // MARK: - Errors
    case unknownError = "unknown_error"
    case invalidImage = "invalid_image"
    case recognitionFailed = "recognition_failed"
    case processingFailed = "processing_failed"
}
