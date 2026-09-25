//
//  VocabApp.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct VocabApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsManager = AppSettingsManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var brandColorManager = BrandColorManager.shared
    /// 延后创建，避免在 `App` 属性初始化阶段阻塞主线程，使首帧能先绘出加载界面。
    @State private var modelContainer: ModelContainer?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container = modelContainer {
                    ContentView()
                        .environmentObject(authManager)
                        .environmentObject(brandColorManager)
                        .preferredColorScheme(settingsManager.appearanceMode.colorScheme)
                        .modelContainer(container)
                } else {
                    ZStack {
                        Color(.systemGroupedBackground)
                            .ignoresSafeArea()
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task {
                guard modelContainer == nil else { return }
                // 让 SwiftUI 先提交首帧（加载态），再执行 CloudKit + SwiftData 的同步初始化。
                await Task.yield()
                await Task.yield()
                modelContainer = Self.makeModelContainer()
                registerForRemoteNotificationsAfterModelReady()
            }
        }
    }

    /// 与 CloudKit 推送配合：在首屏就绪后再请求权限，减少与冷启动竞争的系统对话框与主线程压力。
    private func registerForRemoteNotificationsAfterModelReady() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ 通知权限请求失败: \(error.localizedDescription)")
            } else if granted {
                print("✅ 通知权限已授予")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("⚠️ 用户拒绝了通知权限")
            }
        }
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            Word.self,
            WordSheet.self,
        ])

        let cloudKitConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [cloudKitConfiguration])
        } catch {
            print("❌ ModelContainer 创建失败（CloudKit）:")
            print("错误类型: \(type(of: error))")
            print("错误描述: \(error.localizedDescription)")
            print("完整错误: \(error)")

            print("⚠️ CloudKit 初始化失败，尝试使用本地存储...")
            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            do {
                let container = try ModelContainer(for: schema, configurations: [localConfiguration])
                print("✅ 已使用本地存储（CloudKit 未启用）")
                return container
            } catch {
                print("❌ 本地存储也失败: \(error)")
                fatalError("无法创建 ModelContainer: \(error)\n\n提示：如果这是首次启用 CloudKit，可能需要删除应用并重新安装，或清除应用数据。")
            }
        }
    }
}
