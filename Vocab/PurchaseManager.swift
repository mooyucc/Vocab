//
//  PurchaseManager.swift
//  Vocab
//
//  使用 StoreKit 2 管理订阅产品的加载、购买与恢复。
//

import Foundation
import StoreKit
import Combine

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private var updateListenerTask: Task<Void, Never>?

    private init() {
        // 启动交易监听
        updateListenerTask = listenForTransactions()

        // 预加载产品与权益
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - 产品加载

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: SubscriptionProductID.all)
                .sorted { $0.price < $1.price }
        } catch {
            errorMessage = "加载产品失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 购买与恢复

    func purchase(_ product: Product) async -> Transaction? {
        await MainActor.run {
            errorMessage = nil // 清除之前的错误信息
        }
        
        do {
            print("🛒 开始购买产品: \(product.id)")
            print("🛒 调用 product.purchase()，等待系统弹窗...")
            
            let result = try await product.purchase()
            
            print("🛒 product.purchase() 返回结果: \(result)")
            
            switch result {
            case .success(let verification):
                print("✅ 购买成功，验证交易...")
                let transaction = try checkVerified(verification)
                print("✅ 交易验证成功，产品ID: \(transaction.productID), 交易ID: \(transaction.id)")
                print("✅ 交易类型: \(transaction.productType), 购买日期: \(transaction.purchaseDate)")
                
                // 检查订阅信息
                if let expirationDate = transaction.expirationDate {
                    print("ℹ️ 订阅到期时间: \(expirationDate)")
                    if expirationDate > Date() {
                        print("ℹ️ 订阅当前有效")
                    } else {
                        print("ℹ️ 订阅已过期")
                    }
                }
                
                await transaction.finish()
                await updatePurchasedProducts()
                print("✅ 交易完成并已标记为完成")
                return transaction
            case .userCancelled:
                print("⚠️ 用户取消购买")
                await MainActor.run {
                    errorMessage = nil // 用户取消不需要显示错误
                }
                return nil
            case .pending:
                print("⏳ 购买待处理")
                await MainActor.run {
                    errorMessage = "购买正在处理中，请稍候..."
                }
                return nil
            @unknown default:
                print("❓ 未知购买结果: \(result)")
                return nil
            }
        } catch {
            print("❌ 购买失败: \(error)")
            print("❌ 错误详情: \(error.localizedDescription)")
            if let storeKitError = error as? StoreKitError {
                print("❌ StoreKit错误: \(storeKitError)")
            }
            await MainActor.run {
                errorMessage = "购买失败：\(error.localizedDescription)"
            }
            return nil
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = "恢复购买失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 交易监听

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        do {
            let transaction = try checkVerified(transactionResult)
            await transaction.finish()
            await updatePurchasedProducts()
        } catch {
            await MainActor.run {
                self.errorMessage = "交易验证失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 权益更新

    private func updatePurchasedProducts() async {
        var purchasedIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                switch transaction.productType {
                case .autoRenewable, .nonConsumable:
                    purchasedIDs.insert(transaction.productID)
                default:
                    break
                }
            } catch {
                continue
            }
        }

        await MainActor.run {
            self.purchasedProductIDs = purchasedIDs
        }
    }

    // MARK: - 验证封装

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw NSError(domain: "PurchaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "交易未验证"])
        case .verified(let safe):
            return safe
        }
    }
}
