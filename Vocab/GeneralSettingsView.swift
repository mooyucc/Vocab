//
//  GeneralSettingsView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI

struct GeneralSettingsView: View {
    @StateObject private var settingsManager = AppSettingsManager.shared
    @ObservedObject private var localizedString = LocalizedString.shared
    
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
        }
        .navigationTitle(LocalizedKey.general.rawValue.localized)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(settingsManager.appearanceMode.colorScheme)
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
