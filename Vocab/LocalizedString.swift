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
private enum LocalizedDateFormatCache {
    static var language: AppLanguage?
    static var dateFormatter: DateFormatter?
    static var monthFormatter: DateFormatter?
}

extension DateFormatter {
    /// 根据当前语言设置获取日期格式
    static func localizedDateFormatter() -> DateFormatter {
        let language = AppSettingsManager.shared.language
        if LocalizedDateFormatCache.language == language,
           let cached = LocalizedDateFormatCache.dateFormatter {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        LocalizedDateFormatCache.language = language
        LocalizedDateFormatCache.dateFormatter = formatter
        LocalizedDateFormatCache.monthFormatter = nil
        return formatter
    }
    
    /// 格式化日期为本地化字符串
    static func localizedDateString(from date: Date) -> String {
        localizedDateFormatter().string(from: date)
    }
    
    /// 格式化月份（词库「按月」分组）
    static func localizedMonthString(from date: Date) -> String {
        _ = localizedDateFormatter()
        if let cached = LocalizedDateFormatCache.monthFormatter {
            return cached.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppSettingsManager.shared.language.rawValue)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        LocalizedDateFormatCache.monthFormatter = formatter
        return formatter.string(from: date)
    }
}

enum LocalizedFormat {
    /// 词库列表中的单词数量（按界面语言处理单复数）
    static func wordCount(_ count: Int) -> String {
        switch AppSettingsManager.shared.language {
        case .english, .french, .spanish:
            if count == 1 {
                return LocalizedKey.wordCountOne.rawValue.localized
            }
        default:
            break
        }
        return String(format: LocalizedKey.wordCountFormat.rawValue.localized, count)
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
    case edit = "edit"
    case more = "more"
    
    // MARK: - Tab Bar
    case tabProgress = "tab_progress"
    case tabStudy = "tab_study"
    case tabExercise = "tab_exercise"
    case tabGuess = "tab_guess"
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
    case viewAll = "view_all"
    case noWordsYet = "no_words_yet"
    case goAddWords = "go_add_words"
    case goToLibraryAdd = "go_to_library_add"
    case wordsToReview = "words_to_review"
    case dueTodayMasteredFormat = "due_today_mastered_format"
    case aiSmartFill = "ai_smart_fill"
    case checkIn = "check_in"
    case consecutiveDays = "consecutive_days"
    case thisWeek = "this_week"
    case masteredCountFormat = "mastered_count_format"
    case studyFromSheetFormat = "study_from_sheet_format"
    case currentWordSheet = "current_word_sheet"
    case statTotal = "stat_total"
    case reviewActivity = "review_activity"
    case reviewActivityMonthsFormat = "review_activity_months_format"
    
    // MARK: - Settings
    case account = "account"
    case accountSignInDescription = "account_sign_in_description"
    case general = "general"
    case data = "data"
    case vocabularyData = "vocabulary_data"
    case app = "app"
    case about = "about"
    case help = "help"
    case signOut = "sign_out"
    case signOutConfirm = "sign_out_confirm"
    case language = "language"
    case targetLanguage = "target_language"
    case appearance = "appearance"
    case appearanceDescription = "appearance_description"
    case languageDescription = "language_description"
    case targetLanguageDescription = "target_language_description"
    
    case supplementRootSynonyms = "supplement_root_synonyms"
    case supplementRootSynonymsDescription = "supplement_root_synonyms_description"
    case supplementStart = "supplement_start"
    case supplementProgressFormat = "supplement_progress_format"
    case supplementCompleted = "supplement_completed"
    case supplementNoWords = "supplement_no_words"
    case supplementNoUpdateNeeded = "supplement_no_update_needed"
    case supplementApiCallsHint = "supplement_api_calls_hint"
    case supplementCountHint = "supplement_count_hint"
    case supplementSectionHeader = "supplement_section_header"
    
    // MARK: - Add Word
    case word = "word"
    case definition = "definition"
    case partOfSpeech = "part_of_speech"
    case pronunciation = "pronunciation"
    case example = "example"
    case translation = "translation"
    case root = "root"
    case rootPlaceholder = "root_placeholder"
    case synonymsAntonyms = "synonyms_antonyms"
    case synonymsPlaceholder = "synonyms_placeholder"
    case antonymsPlaceholder = "antonyms_placeholder"
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
    case duplicateWordTitle = "duplicate_word_title"
    case duplicateWordMessage = "duplicate_word_message"
    case skip = "skip"
    case addAnyway = "add_anyway"
    
    // MARK: - Onboarding
    case onboardingValueProposition = "onboarding_value_proposition"
    case onboardingContinue = "onboarding_continue"
    case onboardingBack = "onboarding_back"
    case onboardingLearnTitle = "onboarding_learn_title"
    case onboardingLearnSubtitle = "onboarding_learn_subtitle"
    case onboardingNativeTitle = "onboarding_native_title"
    case onboardingNativeSubtitle = "onboarding_native_subtitle"
    case onboardingComplete = "onboarding_complete"
    case onboardingStepFormat = "onboarding_step_format"
    case freeTrialWelcomeTitle = "free_trial_welcome_title"
    case freeTrialWelcomeMessage = "free_trial_welcome_message"
    
    // MARK: - Study
    case focusMode = "focus_mode"
    case recommendedReview = "recommended_review"
    case recommendedReviewDescription = "recommended_review_description"
    case recommendedReviewCompleted = "recommended_review_completed"
    case recommendedReviewEmptyNoWords = "recommended_review_empty_no_words"
    case recommendedReviewEmptyAllUnlearned = "recommended_review_empty_all_unlearned"
    case recommendedReviewEmptyNoDue = "recommended_review_empty_no_due"
    case reviewAll = "review_all"
    case reviewAllDescription = "review_all_description"
    case continueLast = "continue_last"
    case continueLastDescription = "continue_last_description"
    case hubGuessDescription = "hub_guess_description"
    case hubStart = "hub_start"
    case forgot = "forgot"
    case remembered = "remembered"
    case dailyGoal = "daily_goal"
    case clickToFlip = "click_to_flip"
    case swipeReviewHint = "swipe_review_hint"
    case question = "question"
    case answer = "answer"
    case aiUpdateExample = "ai_update_example"
    case readExampleSentence = "read_example_sentence"
    case reviewPrompt = "review_prompt"
    case reviewAgain = "review_again"
    case later = "later"
    case endReview = "end_review"
    case endReviewConfirmTitle = "end_review_confirm_title"
    case endReviewConfirmMessage = "end_review_confirm_message"
    case allWordsReviewed = "all_words_reviewed"
    case todayWordsReviewed = "today_words_reviewed"
    case goAddNewWords = "go_add_new_words"
    case roundComplete = "round_complete"
    case wordsNeedReview = "words_need_review"
    case selectWordSheet = "select_word_sheet"
    case allSheets = "all_sheets"
    case playPronunciation = "play_pronunciation"
    case comboStreak = "combo_streak"
    case comboMultiplier = "combo_multiplier"
    case sessionProgress = "session_progress"
    case greatJob = "great_job"
    case synonyms = "synonyms"
    case antonyms = "antonyms"
    case goToExercise = "go_to_exercise"
    case goToGuess = "go_to_guess"
    
    // MARK: - Exercise
    case exerciseWordBank = "exercise_word_bank"
    case exerciseFillHint = "exercise_fill_hint"
    case exerciseCheck = "exercise_check"
    case exerciseReshuffle = "exercise_reshuffle"
    case exerciseScore = "exercise_score"
    case exerciseAllCorrect = "exercise_all_correct"
    case exerciseAINewSet = "exercise_ai_new_set"
    case exerciseAINewSetHint = "exercise_ai_new_set_hint"
    case exerciseAIReplaceTitle = "exercise_ai_replace_title"
    case exerciseAIReplaceMessage = "exercise_ai_replace_message"
    case exercisePickForm = "exercise_pick_form"
    case exerciseEmptyNoWords = "exercise_empty_no_words"
    case exerciseEmptyAllUnlearned = "exercise_empty_all_unlearned"
    case exerciseEmptyNoDue = "exercise_empty_no_due"
    case exerciseEmptyNoExamples = "exercise_empty_no_examples"
    case exerciseCorrectAnswer = "exercise_correct_answer"
    case exerciseGenerating = "exercise_generating"
    case exerciseAIParseFailed = "exercise_ai_parse_failed"
    case exerciseStart = "exercise_start"
    case exerciseStartDescription = "exercise_start_description"
    case exerciseEnd = "exercise_end"
    case exerciseModeCloze = "exercise_mode_cloze"
    case exerciseModeGuess = "exercise_mode_guess"
    case guessBuzz = "guess_buzz"
    case guessSkip = "guess_skip"
    case guessSubmit = "guess_submit"
    case guessAnswerPlaceholder = "guess_answer_placeholder"
    case guessTryAgain = "guess_try_again"
    case guessPotentialScoreA11y = "guess_potential_score_a11y"
    case guessCompletedTitle = "guess_completed_title"
    case guessCompletedScore = "guess_completed_score"
    case guessPlayAgain = "guess_play_again"
    case guessEmptyNoEligible = "guess_empty_no_eligible"
    case guessRevealedA11y = "guess_revealed_a11y"
    case guessBuzzHint = "guess_buzz_hint"
    case guessNext = "guess_next"
    case guessCorrect = "guess_correct"
    case guessWrong = "guess_wrong"
    case guessStart = "guess_start"
    case guessReadyRules = "guess_ready_rules"
    case guessLeaveTitle = "guess_leave_title"
    case guessLeaveMessage = "guess_leave_message"
    case guessLeaveConfirm = "guess_leave_confirm"
    case guessLastScore = "guess_last_score"
    case guessBestScore = "guess_best_score"
    case guessRecentScores = "guess_recent_scores"
    
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
    case batchAddCompleted = "batch_add_completed"
    case batchAddCompletedMessage = "batch_add_completed_message"
    
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
    case exportCSV = "export_csv"
    case exportCSVDescription = "export_csv_description"
    case selectSheetsToExport = "select_sheets_to_export"
    case noSheetsSelected = "no_sheets_selected"
    case noWordsInSelectedSheets = "no_words_in_selected_sheets"
    case importCSVFile = "import_csv_file"
    case exportCSVFile = "export_csv_file"
    
    // MARK: - Word List
    case myWordList = "my_word_list"
    case searchWords = "search_words"
    case noResults = "no_results"
    case tryOtherKeywords = "try_other_keywords"
    case newSheet = "new_sheet"
    case newSheetPlaceholder = "new_sheet_placeholder"
    case editSheet = "edit_sheet"
    case sheetName = "sheet_name"
    case sheetAppearance = "sheet_appearance"
    case sheetIcon = "sheet_icon"
    case sheetColor = "sheet_color"
    case resetSheetColor = "reset_sheet_color"
    case resetSheetColorHint = "reset_sheet_color_hint"
    case pinSheet = "pin_sheet"
    case unpinSheet = "unpin_sheet"
    case pinnedSheets = "pinned_sheets"
    case otherSheets = "other_sheets"
    case reorderSheets = "reorder_sheets"
    case mergeSheets = "merge_sheets"
    case mergeInto = "merge_into"
    case mergeSelectSources = "merge_select_sources"
    case mergeSelectTarget = "merge_select_target"
    case mergeConfirm = "merge_confirm"
    case mergeDuplicatesTitle = "merge_duplicates_title"
    case mergeDuplicatesMessage = "merge_duplicates_message"
    case keepBetterProgress = "keep_better_progress"
    case keepBoth = "keep_both"
    case deleteSheet = "delete_sheet"
    case deleteSheetMessage = "delete_sheet_message"
    case moveToSheet = "move_to_sheet"
    case moveWords = "move_words"
    case selectWords = "select_words"
    case selectedWordsCount = "selected_words_count"
    case libraryFilterGrouped = "library_filter_grouped"
    case libraryFilterUnlearned = "library_filter_unlearned"
    case libraryFilterDue = "library_filter_due"
    case libraryFilterByMonth = "library_filter_by_month"
    case noUnlearnedWords = "no_unlearned_words"
    case noDueReviewWords = "no_due_review_words"
    case emptySheet = "empty_sheet"
    case wordCountFormat = "word_count_format"
    case wordCountOne = "word_count_one"
    case sheetNameEmpty = "sheet_name_empty"
    case sheetNameExists = "sheet_name_exists"
    case mergeNeedSourceTarget = "merge_need_source_target"
    case deleteWordsConfirmTitle = "delete_words_confirm_title"
    case deleteWordsConfirmMessage = "delete_words_confirm_message"
    case deleteWordConfirmTitle = "delete_word_confirm_title"
    case deleteWordConfirmMessage = "delete_word_confirm_message"
    case noTargetSheet = "no_target_sheet"
    
    // MARK: - About
    case version = "version"
    case features = "features"
    case updates = "updates"
    case coreFeatures = "core_features"
    case versionHistory = "version_history"
    case softwareLicense = "software_license"
    case privacyPolicy = "privacy_policy"
    case copyright = "copyright"
    case developerWebsite = "developer_website"
    case appleUser = "apple_user"
    case userName = "user_name"
    case userNameDescription = "user_name_description"
    case editUserName = "edit_user_name"
    case changeAvatar = "change_avatar"
    case chooseFromPhotos = "choose_from_photos"
    case removeAvatar = "remove_avatar"
    
    // MARK: - Features
    case wordManagement = "word_management"
    case wordManagementDescription = "word_management_description"
    case intelligentLearning = "intelligent_learning"
    case intelligentLearningDescription = "intelligent_learning_description"
    case cameraRecognition = "camera_recognition_feature"
    case cameraRecognitionDescription = "camera_recognition_description"
    case learningProgress = "learning_progress"
    case learningProgressDescription = "learning_progress_description"
    case reviewSystem = "review_system"
    case reviewSystemDescription = "review_system_description"
    case firstRelease = "first_release"
    case supportWordAdd = "support_word_add"
    case aiSmartFillFeature = "ai_smart_fill_feature"
    case cameraRecognizeFeature = "camera_recognize_feature"
    case progressTracking = "progress_tracking"
    case reviewSystemFeature = "review_system_feature"
    case versionDateFormat = "version_date_format"
    case versionUpdate24Date = "version_update_2_4_date"
    case versionUpdate24RecommendedReview = "version_update_2_4_recommended_review"
    case versionUpdate24ProgressTab = "version_update_2_4_progress_tab"
    case versionUpdate24StudyUI = "version_update_2_4_study_ui"
    case versionUpdate24SettingsData = "version_update_2_4_settings_data"
    case versionUpdate24AIPaywall = "version_update_2_4_ai_paywall"
    case versionUpdate24Stability = "version_update_2_4_stability"
    
    // MARK: - Errors
    case unknownError = "unknown_error"
    case invalidImage = "invalid_image"
    case recognitionFailed = "recognition_failed"
    case processingFailed = "processing_failed"
}

/// Text 视图扩展，直接使用本地化字符串
extension Text {
    init(_ key: LocalizedKey) {
        self.init(key.rawValue.localized)
    }
}
