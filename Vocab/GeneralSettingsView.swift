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
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
            } header: {
                Text(LocalizedKey.targetLanguage)
            } footer: {
                Text(LocalizedKey.targetLanguageDescription)
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
        .vocabFormCanvas()
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
