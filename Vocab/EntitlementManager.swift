//
//  EntitlementManager.swift
//  Vocab
//
//  负责将交易状态映射为应用内权益，供各功能点检查。
//

import Foundation
import StoreKit
import Combine

@MainActor
final class EntitlementManager: ObservableObject {
    static let shared = EntitlementManager()

    @Published private(set) var currentEntitlement: SubscriptionEntitlement = .free
    @Published private(set) var subscriptionExpiryDate: Date?
    @Published private(set) var isSubscriptionActive: Bool = false
    @Published private(set) var currentSubscriptionProductID: String?

    private let purchaseManager = PurchaseManager.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {
        purchaseManager.$purchasedProductIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateEntitlement()
            }
            .store(in: &cancellables)

        updateEntitlement()
    }

    // MARK: - 对外便捷方法

    func entitlement() -> SubscriptionEntitlement {
        currentEntitlement
    }

    var canUseAIFeatures: Bool {
        currentEntitlement.canUseAIFeatures
    }

    var canUseAdvancedDataIO: Bool {
        currentEntitlement.canUseAdvancedDataIO
    }

    // MARK: - 权益更新

    func updateEntitlement() {
        Task {
            let (hasPro, productID) = await hasActiveProSubscription()
            let expiry = await latestExpiryDate()

            await MainActor.run {
                currentEntitlement = hasPro ? .pro : .free
                isSubscriptionActive = hasPro
                subscriptionExpiryDate = expiry
                currentSubscriptionProductID = productID
            }
        }
    }
    
    /// 基于刚完成的交易直接更新权益（用于购买成功后立即更新）
    func updateEntitlement(from transaction: Transaction) {
        Task {
            print("🔄 基于交易直接更新权益: \(transaction.productID)")
            
            var hasPro = false
            var productID: String? = nil
            var expiry: Date? = nil
            
            // 检查交易类型和产品ID
            switch transaction.productType {
            case .autoRenewable:
                if transaction.productID == SubscriptionProductID.proMonthly ||
                    transaction.productID == SubscriptionProductID.proYearly {
                    // 检查订阅是否过期
                    if let expirationDate = transaction.expirationDate {
                        if expirationDate > Date() {
                            // 订阅未过期
                            hasPro = true
                            productID = transaction.productID
                            expiry = expirationDate
                            print("✅ 订阅有效: \(transaction.productID), 到期: \(expirationDate)")
                        } else {
                            // 订阅已过期，但可能是刚购买的交易
                            let purchaseTime = transaction.purchaseDate
                            let timeSincePurchase = Date().timeIntervalSince(purchaseTime)
                            let fiveMinutes: TimeInterval = 5 * 60
                            
                            if timeSincePurchase < fiveMinutes {
                                // 订阅刚购买但已过期（可能是沙箱环境），仍认为有效
                                hasPro = true
                                productID = transaction.productID
                                expiry = expirationDate
                                print("⚠️ 订阅刚购买但已过期（可能是沙箱环境），仍认为有效: \(transaction.productID), 到期: \(expirationDate), 购买后: \(Int(timeSincePurchase))秒")
                            } else {
                                print("⚠️ 订阅已过期且购买时间超过5分钟: \(transaction.productID)")
                            }
                        }
                    } else {
                        print("⚠️ 订阅没有过期时间: \(transaction.productID)")
                    }
                }
            case .nonConsumable:
                if transaction.productID == SubscriptionProductID.proLifetime {
                    hasPro = true
                    productID = transaction.productID
                    expiry = nil
                    print("✅ 终身订阅: \(transaction.productID)")
                }
            default:
                break
            }
            
            await MainActor.run {
                currentEntitlement = hasPro ? .pro : .free
                isSubscriptionActive = hasPro
                subscriptionExpiryDate = expiry
                currentSubscriptionProductID = productID
                
                print("🔄 权益更新完成: entitlement=\(currentEntitlement), isActive=\(isSubscriptionActive), productID=\(currentSubscriptionProductID ?? "nil")")
            }
        }
    }

    private func hasActiveProSubscription() async -> (Bool, String?) {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                switch transaction.productType {
                case .autoRenewable:
                    if transaction.productID == SubscriptionProductID.proMonthly ||
                        transaction.productID == SubscriptionProductID.proYearly {
                        // 检查订阅是否过期
                        if let expirationDate = transaction.expirationDate {
                            if expirationDate > Date() {
                                print("✅ 找到有效订阅: \(transaction.productID), 到期时间: \(expirationDate)")
                                return (true, transaction.productID)
                            } else {
                                print("⚠️ 订阅已过期: \(transaction.productID), 到期时间: \(expirationDate)")
                            }
                        } else {
                            // 如果没有过期时间，认为是有效的
                            print("⚠️ 订阅没有过期时间: \(transaction.productID)")
                            return (true, transaction.productID)
                        }
                    }
                case .nonConsumable:
                    if transaction.productID == SubscriptionProductID.proLifetime {
                        print("✅ 找到终身订阅: \(transaction.productID)")
                        return (true, transaction.productID)
                    }
                default:
                    break
                }
            } catch {
                print("❌ 交易验证失败: \(error)")
                continue
            }
        }
        print("ℹ️ 未找到有效的 Pro 订阅")
        return (false, nil)
    }

    private func latestExpiryDate() async -> Date? {
        var latest: Date?

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                // 终身买断无过期时间，直接返回 nil
                if transaction.productType == .nonConsumable &&
                    transaction.productID == SubscriptionProductID.proLifetime {
                    return nil
                }
                if transaction.productType == .autoRenewable &&
                    (transaction.productID == SubscriptionProductID.proMonthly ||
                     transaction.productID == SubscriptionProductID.proYearly) {
                    if let expiry = transaction.expirationDate {
                        if latest == nil || expiry > latest! {
                            latest = expiry
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return latest
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(domain: "EntitlementManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "交易未验证"])
        case .verified(let safe):
            return safe
        }
    }
}
