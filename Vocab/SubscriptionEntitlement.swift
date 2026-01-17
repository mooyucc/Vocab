//
//  SubscriptionEntitlement.swift
//  Vocab
//
//  定义订阅权益与产品标识，供全局权限判断使用。
//

import Foundation

/// 订阅产品 ID 集合
enum SubscriptionProductID {
    // 月度订阅
    static let proMonthly = "com.mooyu.vocab.pro.monthly"
    // 年度订阅
    static let proYearly = "com.mooyu.vocab.pro.yearly"
    // 终身买断（非消耗型）
    static let proLifetime = "com.mooyu.vocab.pro.lifetime"
    // 批量加载列表
    static let all: [String] = [proMonthly, proYearly, proLifetime]
}

/// 应用内权益等级
enum SubscriptionEntitlement: String, Codable {
    case free
    case pro

    var displayName: String {
        switch self {
        case .free: return "免费版"
        case .pro: return "Pro"
        }
    }

    // MARK: - 权限判断

    /// 是否可以使用 AI 功能
    var canUseAIFeatures: Bool {
        // 仅 Pro 可以使用AI功能
        self == .pro
    }
    
    /// 是否可以使用高级导入导出功能
    var canUseAdvancedDataIO: Bool {
        // 仅 Pro 可以使用高级数据导入导出
        self == .pro
    }
    
    /// 是否可以使用无限单词数量
    var canAddUnlimitedWords: Bool {
        // 免费版和 Pro 都可以无限添加
        true
    }
}
