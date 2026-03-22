//
//  AppSettingsManager.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import Foundation
import SwiftUI
import Combine
import UIKit

enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case french = "fr"
    case spanish = "es"
    case korean = "ko"
    
    var displayName: String {
        switch self {
        case .chinese:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        case .french:
            return "Français"
        case .spanish:
            return "Español"
        case .korean:
            return "한국어"
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
            return "appearance_mode_system".localized
        case .dark:
            return "appearance_mode_dark".localized
        case .light:
            return "appearance_mode_light".localized
        }
    }
    
    /// 获取当前应该使用的颜色方案
    /// 当模式为"系统"时，返回系统级别的颜色方案以确保弹窗能立即更新
    func colorScheme(using systemColorScheme: ColorScheme?) -> ColorScheme? {
        switch self {
        case .system:
            // 如果提供了系统颜色方案，使用它；否则返回 nil 让 SwiftUI 自动处理
            return systemColorScheme
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
    
    /// 兼容旧代码的计算属性
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            // 返回 nil 让 SwiftUI 自动跟随系统
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
    
    /// 应用界面语言
    @Published var language: AppLanguage {
        didSet {
            userDefaults.set(language.rawValue, forKey: languageKey)
            // 通知语言变化
            NotificationCenter.default.post(name: NSNotification.Name("AppLanguageChanged"), object: nil)
        }
    }
    
    /// 学习目标语言（用于 AI 补全等学习相关内容）
    @Published var targetLanguage: AppLanguage {
        didSet {
            userDefaults.set(targetLanguage.rawValue, forKey: targetLanguageKey)
        }
    }
    
    /// 外观模式
    @Published var appearanceMode: AppearanceMode {
        didSet {
            userDefaults.set(appearanceMode.rawValue, forKey: appearanceModeKey)
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let languageKey = "appLanguage"
    private let targetLanguageKey = "targetLanguage"
    private let appearanceModeKey = "appearanceMode"
    
    /// 获取系统级别的颜色方案（不受应用设置影响）
    /// 使用 UIScreen.main.traitCollection 获取系统设置
    /// 注意：在某些情况下，这个方法可能也会受到应用设置的影响
    /// 如果遇到问题，可以考虑监听系统颜色方案变化通知
    func getSystemColorScheme() -> ColorScheme? {
        // 使用 UIScreen.main.traitCollection 获取系统设置
        // 这个方法获取的是屏幕级别的设置，理论上应该不受单个窗口设置的影响
        let screenTraitCollection = UIScreen.main.traitCollection
        let systemStyle = screenTraitCollection.userInterfaceStyle
        
        // 如果无法确定，返回 nil 让 SwiftUI 自动处理
        if systemStyle == .unspecified {
            return nil
        }
        
        return systemStyle == .dark ? .dark : .light
    }
    
    private init() {
        // 先解析系统语言，供界面语言和目标语言共同使用
        let resolvedAppLanguage: AppLanguage
        if let savedLanguage = userDefaults.string(forKey: languageKey),
           let language = AppLanguage(rawValue: savedLanguage) {
            resolvedAppLanguage = language
        } else {
            // 默认使用系统语言
            let systemLanguage = Locale.preferredLanguages.first ?? "en"
            
            if systemLanguage.hasPrefix("zh-Hant") ||
               systemLanguage.hasPrefix("zh_TW") ||
               systemLanguage.hasPrefix("zh_HK") {
                resolvedAppLanguage = .chineseTraditional
            } else if systemLanguage.hasPrefix("zh") {
                resolvedAppLanguage = .chinese
            } else if systemLanguage.hasPrefix("ja") {
                resolvedAppLanguage = .japanese
            } else if systemLanguage.hasPrefix("fr") {
                resolvedAppLanguage = .french
            } else if systemLanguage.hasPrefix("es") {
                resolvedAppLanguage = .spanish
            } else if systemLanguage.hasPrefix("ko") {
                resolvedAppLanguage = .korean
            } else {
                resolvedAppLanguage = .english
            }
        }
        
        // 设置界面语言
        self.language = resolvedAppLanguage
        
        // 加载学习目标语言，默认与界面语言保持一致
        if let savedTargetLanguage = userDefaults.string(forKey: targetLanguageKey),
           let target = AppLanguage(rawValue: savedTargetLanguage) {
            self.targetLanguage = target
        } else {
            self.targetLanguage = resolvedAppLanguage
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
