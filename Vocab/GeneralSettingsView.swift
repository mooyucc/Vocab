//
//  GeneralSettingsView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import UIKit

struct GeneralSettingsView: View {
    @StateObject private var settingsManager = AppSettingsManager.shared
    @ObservedObject private var localizedString = LocalizedString.shared
    @State private var showSupplementSheet = false
    
    /// 获取系统级别的颜色方案（不受应用设置影响）
    private var systemColorScheme: ColorScheme? {
        settingsManager.getSystemColorScheme()
    }
    
    /// 计算应该使用的颜色方案
    /// 当模式为"系统"时，使用系统颜色方案以确保弹窗能立即更新
    private var effectiveColorScheme: ColorScheme? {
        switch settingsManager.appearanceMode {
        case .system:
            // 使用系统颜色方案，而不是 nil，以确保弹窗能立即更新
            return systemColorScheme
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
    
    var body: some View {
        Form {
            // 语言设置
            Section {
                Picker(LocalizedKey.language.rawValue.localized, selection: $settingsManager.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
            } header: {
                Text(LocalizedKey.language)
            } footer: {
                Text(LocalizedKey.languageDescription)
            }
            
            // 学习目标语言设置
            Section {
                Picker(LocalizedKey.targetLanguage.rawValue.localized, selection: $settingsManager.targetLanguage) {
                    // 目前学习目标语言不区分简体/繁体，隐藏繁体选项，避免混淆
                    ForEach(AppLanguage.allCases.filter { $0 != .chineseTraditional }, id: \.self) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
            } header: {
                Text(LocalizedKey.targetLanguage)
            } footer: {
                Text(LocalizedKey.targetLanguageDescription)
            }
            
            // 外观模式设置
            Section {
                Picker(LocalizedKey.appearance.rawValue.localized, selection: $settingsManager.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text(LocalizedKey.appearance)
            } footer: {
                Text(LocalizedKey.appearanceDescription)
            }
            
            // 一键更新词根与近反义词
            Section {
                Button {
                    showSupplementSheet = true
                } label: {
                    Label(LocalizedKey.supplementRootSynonyms.rawValue.localized, systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text(LocalizedKey.supplementSectionHeader.rawValue.localized)
            } footer: {
                Text(LocalizedKey.supplementRootSynonymsDescription)
            }
        }
        .navigationTitle(LocalizedKey.general.rawValue.localized)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(effectiveColorScheme)
        .sheet(isPresented: $showSupplementSheet) {
            WordSupplementView()
        }
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
