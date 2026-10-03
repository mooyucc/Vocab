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

    /// AVSpeechSynthesizer 使用的 BCP 47 语言码
    var speechLanguageCode: String {
        switch self {
        case .chinese:
            return "zh-CN"
        case .chineseTraditional:
            return "zh-TW"
        case .english:
            return "en-US"
        case .japanese:
            return "ja-JP"
        case .french:
            return "fr-FR"
        case .spanish:
            return "es-ES"
        case .korean:
            return "ko-KR"
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
    
    private let userDefaults = UserDefaults.standard
    private let languageKey = "appLanguage"
    private let targetLanguageKey = "targetLanguage"
    
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
    }
}
