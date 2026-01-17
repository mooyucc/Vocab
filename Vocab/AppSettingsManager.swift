//
//  AppSettingsManager.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"
    
    var displayName: String {
        switch self {
        case .chinese:
            return "中文"
        case .english:
            return "English"
        }
    }
}

enum AppearanceMode: String, CaseIterable {
    case system = "system"
    case dark = "dark"
    case light = "light"
    
    var displayName: String {
        switch self {
        case .system:
            return "系统"
        case .dark:
            return "深色"
        case .light:
            return "浅色"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

class AppSettingsManager: ObservableObject {
    static let shared = AppSettingsManager()
    
    @Published var language: AppLanguage {
        didSet {
            userDefaults.set(language.rawValue, forKey: languageKey)
            // 通知语言变化
            NotificationCenter.default.post(name: NSNotification.Name("AppLanguageChanged"), object: nil)
        }
    }
    
    @Published var appearanceMode: AppearanceMode {
        didSet {
            userDefaults.set(appearanceMode.rawValue, forKey: appearanceModeKey)
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let languageKey = "appLanguage"
    private let appearanceModeKey = "appearanceMode"
    
    private init() {
        // 加载语言设置
        if let savedLanguage = userDefaults.string(forKey: languageKey),
           let language = AppLanguage(rawValue: savedLanguage) {
            self.language = language
        } else {
            // 默认使用系统语言
            let systemLanguage = Locale.preferredLanguages.first ?? "en"
            if systemLanguage.hasPrefix("zh") {
                self.language = .chinese
            } else {
                self.language = .english
            }
        }
        
        // 加载外观模式设置
        if let savedMode = userDefaults.string(forKey: appearanceModeKey),
           let mode = AppearanceMode(rawValue: savedMode) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }
    }
}
