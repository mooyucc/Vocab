//
//  AppDelegate.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import UIKit
import UserNotifications
import CloudKit
import SwiftData

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // 设置通知中心代理
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    // 处理远程通知注册成功
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("✅ 远程通知注册成功，设备 Token 已获取")
    }
    
    // 处理远程通知注册失败
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ 远程通知注册失败: \(error.localizedDescription)")
    }
    
    // 处理接收到的远程通知（应用在前台时）
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        
        // 检查是否是 CloudKit 通知
        if CKNotification(fromRemoteNotificationDictionary: userInfo) != nil {
            print("📥 收到 CloudKit 远程通知（应用在前台）")
            // 应用在前台时，可以选择显示通知或静默处理
            // SwiftData 会自动处理数据同步，所以这里可以选择不显示通知
            completionHandler([]) // 不显示通知横幅
        } else {
            // 其他类型的通知，按默认方式处理
            completionHandler([.banner, .sound, .badge])
        }
    }
    
    // 处理用户点击通知（应用在后台或未启动时）
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // 检查是否是 CloudKit 通知
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            print("📥 用户点击了 CloudKit 通知")
            handleCloudKitNotification(ckNotification)
        }
        
        completionHandler()
    }
    
    // 处理后台远程通知（静默推送）
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // 检查是否是 CloudKit 通知
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            print("📥 收到 CloudKit 后台通知")
            handleCloudKitNotification(ckNotification)
            // SwiftData 会自动处理数据同步，所以返回 .newData
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    // 处理 CloudKit 通知
    private func handleCloudKitNotification(_ notification: CKNotification) {
        switch notification.notificationType {
        case .database:
            if let dbNotification = notification as? CKDatabaseNotification {
                print("📊 CloudKit 数据库变更通知")
                print("   - 订阅 ID: \(dbNotification.subscriptionID ?? "未知")")
                // SwiftData 会自动处理数据库变更，这里只需要记录日志
            }
        case .query:
            if let queryNotification = notification as? CKQueryNotification {
                print("🔍 CloudKit 查询通知")
                print("   - 记录 ID: \(queryNotification.recordID?.recordName ?? "未知")")
                print("   - 变更类型: \(queryNotification.queryNotificationReason)")
                // SwiftData 会自动处理查询结果变更
            }
        case .recordZone:
            if let zoneNotification = notification as? CKRecordZoneNotification {
                print("🗂️ CloudKit 记录区域通知")
                print("   - 区域 ID: \(zoneNotification.recordZoneID?.zoneName ?? "未知")")
                // SwiftData 会自动处理区域变更
            }
        @unknown default:
            print("❓ 未知类型的 CloudKit 通知")
        }
    }
}
