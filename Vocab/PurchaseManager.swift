//
//  PurchaseManager.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/29.
//

import Foundation
import StoreKit
import Combine

/// 内购产品ID
enum PurchaseProductID {
    /// 100次AI调用（2元）
    static let aiCalls100 = "com.mooyunet.vocab.ai_calls_100"
}

/// 内购管理器
@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var updateListenerTask: Task<Void, Error>?
    
    private init() {
        // 启动监听器，监听交易更新
        updateListenerTask = listenForTransactions()
        
        // 加载产品
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    /// 加载可购买的产品
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let productIDs = [PurchaseProductID.aiCalls100]
            products = try await Product.products(for: productIDs)
        } catch {
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("❌ 加载产品失败: \(error)")
        }
    }
    
    /// 购买产品
    /// - Parameter product: 要购买的产品
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            // 购买成功，添加调用次数
            if transaction.productID == PurchaseProductID.aiCalls100 {
                await MainActor.run {
                    UsageTracker.shared.addCalls(UsageTracker.callsPerPurchase)
                }
            }
            await transaction.finish()
            await updatePurchasedProducts()
            return true
            
        case .userCancelled:
            return false
            
        case .pending:
            return false
            
        @unknown default:
            return false
        }
    }
    
    /// 恢复购买
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            print("❌ 恢复购买失败: \(error)")
        }
    }
    
    /// 更新已购买的产品列表
    func updatePurchasedProducts() async {
        var purchasedIDs: Set<String> = []
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try Self.checkVerified(result)
                purchasedIDs.insert(transaction.productID)
            } catch {
                print("❌ 验证交易失败: \(error)")
            }
        }
        
        purchasedProductIDs = purchasedIDs
    }
    
    /// 监听交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try Self.checkVerified(result)
                    // 处理交易
                    if transaction.productID == PurchaseProductID.aiCalls100 {
                        await MainActor.run {
                            UsageTracker.shared.addCalls(UsageTracker.callsPerPurchase)
                        }
                    }
                    await transaction.finish()
                    await PurchaseManager.shared.updatePurchasedProducts()
                } catch {
                    print("❌ 处理交易更新失败: \(error)")
                }
            }
        }
    }
    
    /// 验证交易（静态方法，可从非 MainActor 上下文调用）
    private nonisolated static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.unverifiedTransaction
        case .verified(let safe):
            return safe
        }
    }
}

/// 购买错误
enum PurchaseError: Error {
    case unverifiedTransaction
    case productNotFound
    case purchaseFailed
}
