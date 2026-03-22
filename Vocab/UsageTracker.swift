//
//  UsageTracker.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/29.
//

import Foundation
import Combine

/// AI API使用次数追踪器
class UsageTracker: ObservableObject {
    static let shared = UsageTracker()
    
    /// 每次购买获得的次数
    static let callsPerPurchase = 100
    
    /// 每次购买的价格（元）
    static let pricePerPurchase = 3.0
    
    /// 新安装用户免费额度（次）
    static let freeTrialCalls = 20
    
    @Published var remainingCalls: Int {
        didSet {
            UserDefaults.standard.set(remainingCalls, forKey: "ai_api_remaining_calls")
        }
    }
    
    @Published var totalCallsUsed: Int {
        didSet {
            UserDefaults.standard.set(totalCallsUsed, forKey: "ai_api_total_calls_used")
        }
    }
    
    private let remainingCallsKey = "ai_api_remaining_calls"
    private let totalCallsUsedKey = "ai_api_total_calls_used"
    /// 是否已发放过「新安装/升级」的免费额度（一次性）
    private let freeTrialGrantedKey = "vocab_ai_free_trial_granted"
    /// 是否需要在本次启动时展示「获得免费额度」提示页
    static let freeTrialWelcomeKey = "vocab_show_free_trial_welcome"
    
    private init() {
        // 从UserDefaults加载数据
        self.remainingCalls = UserDefaults.standard.integer(forKey: remainingCallsKey)
        self.totalCallsUsed = UserDefaults.standard.integer(forKey: totalCallsUsedKey)
        
        // 新安装或从免费版升级：首次启动本版本时赠送一次免费额度
        let hasGranted = UserDefaults.standard.bool(forKey: freeTrialGrantedKey)
        if !hasGranted {
            self.remainingCalls = Self.freeTrialCalls
            UserDefaults.standard.set(true, forKey: freeTrialGrantedKey)
            UserDefaults.standard.set(true, forKey: Self.freeTrialWelcomeKey)
        }
    }
    
    /// 是否应展示免费额度欢迎页（新装/升级首次启动）
    static var shouldShowFreeTrialWelcome: Bool {
        UserDefaults.standard.bool(forKey: freeTrialWelcomeKey)
    }
    
    /// 标记免费额度欢迎页已展示，下次不再弹出
    static func markFreeTrialWelcomeShown() {
        UserDefaults.standard.set(false, forKey: freeTrialWelcomeKey)
    }
    
    /// 检查是否有足够的调用次数
    func hasRemainingCalls() -> Bool {
        return remainingCalls > 0
    }
    
    /// 使用一次API调用
    /// - Returns: 是否成功使用（有剩余次数）
    @discardableResult
    func useCall() -> Bool {
        guard hasRemainingCalls() else {
            return false
        }
        
        remainingCalls -= 1
        totalCallsUsed += 1
        
        return true
    }
    
    /// 添加调用次数（购买后调用）
    /// - Parameter calls: 要添加的次数
    func addCalls(_ calls: Int) {
        remainingCalls += calls
    }
    
    /// 获取剩余次数描述
    func getRemainingCallsDescription() -> String {
        if remainingCalls == 0 {
            return "usage_no_calls_remaining".localized
        } else if remainingCalls == 1 {
            return "usage_one_call_remaining".localized
        } else {
            return String(format: "usage_calls_remaining".localized, remainingCalls)
        }
    }
    
    /// 获取使用统计描述
    func getUsageStatsDescription() -> String {
        return String(format: "usage_stats".localized, totalCallsUsed, remainingCalls)
    }
}
