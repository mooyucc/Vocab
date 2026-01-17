//
//  CloudKitStatusManager.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import Foundation
import CloudKit
import Combine
import SwiftUI

@MainActor
class CloudKitStatusManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var isSyncing: Bool = false
    
    private let container: CKContainer
    
    init() {
        // 使用默认容器（自动匹配 Bundle ID）
        container = CKContainer.default()
        checkAccountStatus()
    }
    
    func checkAccountStatus() {
        container.accountStatus { [weak self] status, error in
            Task { @MainActor in
                if let error = error {
                    print("CloudKit 账户状态检查失败: \(error.localizedDescription)")
                    return
                }
                
                self?.accountStatus = status
                self?.isSignedIn = (status == .available)
            }
        }
    }
    
    var statusDescription: String {
        switch accountStatus {
        case .available:
            return "已启用 iCloud 同步"
        case .noAccount:
            return "未登录 iCloud"
        case .restricted:
            return "iCloud 受限"
        case .couldNotDetermine:
            return "无法确定 iCloud 状态"
        case .temporarilyUnavailable:
            return "iCloud 暂时不可用"
        @unknown default:
            return "未知状态"
        }
    }
    
    var statusIcon: String {
        switch accountStatus {
        case .available:
            return "icloud.fill"
        case .noAccount:
            return "icloud.slash"
        case .restricted:
            return "exclamationmark.triangle"
        case .couldNotDetermine:
            return "questionmark.circle"
        case .temporarilyUnavailable:
            return "icloud.slash"
        @unknown default:
            return "questionmark.circle"
        }
    }
    
    var statusColor: Color {
        switch accountStatus {
        case .available:
            return .green
        case .noAccount:
            return .orange
        case .restricted, .temporarilyUnavailable:
            return .red
        case .couldNotDetermine:
            return .secondary
        @unknown default:
            return .secondary
        }
    }
}
