//
//  ContentView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab: AppView = .home
    @ObservedObject private var localizedString = LocalizedString.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Label(LocalizedKey.tabProgress.rawValue.localized, systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(AppView.home)
            
            StudyView()
                .tabItem {
                    Label(LocalizedKey.tabStudy.rawValue.localized, systemImage: "brain.head.profile")
                }
                .tag(AppView.study)
            
            WordListView(selectedTab: $selectedTab)
                .tabItem {
                    Label(LocalizedKey.tabWordList.rawValue.localized, systemImage: "list.bullet")
                }
                .tag(AppView.list)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .applyTabViewStyle()
    }
}

// iOS 26+ 样式扩展
extension View {
    @ViewBuilder
    func applyTabViewStyle() -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26+ 使用沉浸式浮动标签栏（SwiftUI 8）
            // 注意：这些 API 可能在 iOS 26 SDK 发布前不可用
            // 如果编译错误，请暂时注释掉以下两行，使用标准样式
            self.tabViewStyle(.automatic)
            // self.tabViewStyle(.expanded)
            // self.tabBarToolbar(.visible)
        } else {
            // iOS 18-25 使用标准样式
            self.tabViewStyle(.automatic)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Word.self, WordSheet.self], inMemory: true)
}
