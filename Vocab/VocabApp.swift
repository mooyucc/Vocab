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
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var entitlementManager = EntitlementManager.shared
    @StateObject private var brandColorManager = BrandColorManager.shared
    
    init() {
        // 注册远程通知以支持 CloudKit 推送
        registerForRemoteNotifications()
    }
    
    private func registerForRemoteNotifications() {
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
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Word.self,
            WordSheet.self,
        ])
        
        // 首先尝试使用 CloudKit
        let cloudKitConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [cloudKitConfiguration])
        } catch {
            // 打印详细错误信息以便调试
            print("❌ ModelContainer 创建失败（CloudKit）:")
            print("错误类型: \(type(of: error))")
            print("错误描述: \(error.localizedDescription)")
            print("完整错误: \(error)")
            
            // 如果 CloudKit 失败，尝试不使用 CloudKit（降级方案）
            // 这通常发生在现有数据库与 CloudKit schema 不兼容时
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
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(purchaseManager)
                .environmentObject(entitlementManager)
                .environmentObject(brandColorManager)
                .preferredColorScheme(settingsManager.appearanceMode.colorScheme)
                .onAppear {
                    // 确保注册远程通知
                    UIApplication.shared.registerForRemoteNotifications()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
