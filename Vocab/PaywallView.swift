//
//  PaywallView.swift
//  Vocab
//
//  订阅付费墙：展示价值点、价格、购买与恢复入口。
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var brandColorManager: BrandColorManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var isRestoring: Bool = false
    @State private var isPurchasing: Set<String> = []
    
    // 引导流程相关
    var isOnboarding: Bool = false
    var onSkip: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    featureList
                    pricingSection
                    restoreSection
                    
                    // 引导流程中显示"开始使用"按钮
                    if isOnboarding, let onSkip = onSkip {
                        skipButton(onSkip: onSkip)
                    }
                    
                    termsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .padding(.top, 12)
            }
            .navigationTitle("paywall_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 仅在非引导流程中显示关闭按钮
                if !isOnboarding {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("close".localized) { dismiss() }
                    }
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.12),
                        Color.pink.opacity(0.08),
                        Color(.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .task {
                // 每次打开 PaywallView 时重新加载产品列表
                await purchaseManager.loadProducts()
            }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(brandColorManager.currentBrandColor)

            Text("paywall_title".localized)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("paywall_subtitle".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("paywall_feature_title".localized)
                .font(.headline)

            featureRow(icon: "sparkles", title: "paywall_feature_ai".localized)
            featureRow(icon: "tray.and.arrow.down.fill", title: "paywall_feature_import_export".localized)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var pricingSection: some View {
        VStack(spacing: 12) {
            if hasLifetime {
                lifetimeUnlockedCard
            } else {
                if purchaseManager.isLoading {
                    ProgressView("loading".localized)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if purchaseManager.products.isEmpty {
                    if let message = purchaseManager.errorMessage {
                        VStack(spacing: 12) {
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button {
                                Task {
                                    await purchaseManager.loadProducts()
                                }
                            } label: {
                                Text("retry".localized)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    } else {
                        ProgressView("loading".localized)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                } else {
                    // 显示错误信息（如果有）
                    if let errorMessage = purchaseManager.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                    
                    ForEach(sortedProducts(), id: \.id) { product in
                        purchaseButton(for: product)
                    }
                }
            }
        }
    }

    private var restoreSection: some View {
        Button {
            Task {
                isRestoring = true
                await purchaseManager.restorePurchases()
                isRestoring = false
                entitlementManager.updateEntitlement()
            }
        } label: {
            HStack {
                if isRestoring { ProgressView().scaleEffect(0.8) }
                Text("paywall_button_restore".localized)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
    
    private func skipButton(onSkip: @escaping () -> Void) -> some View {
        Button {
            onSkip()
        } label: {
            Text("onboarding_complete".localized)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(brandColorManager.currentBrandColor)
                )
        }
    }

    private var termsSection: some View {
        VStack(spacing: 6) {
            Text("subscription_auto_renew_note".localized)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                Link("terms_of_use".localized, destination: URL(string: "terms_url".localized)!)
                Text("|")
                    .foregroundColor(.secondary)
                Link("privacy_policy".localized, destination: URL(string: "privacy_url".localized)!)
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func featureRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(brandColorManager.currentBrandColor)
                .frame(width: 26)
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private func purchaseButton(for product: Product) -> some View {
        let isPurchasingThis = isPurchasing.contains(product.id)
        let isCurrentSubscription = entitlementManager.currentSubscriptionProductID == product.id && entitlementManager.isSubscriptionActive
        
        return Button {
            guard !isPurchasingThis else { 
                print("⚠️ 购买进行中，忽略重复点击")
                return 
            }
            
            // 如果已经是当前订阅，不允许再次购买
            guard !isCurrentSubscription else {
                print("ℹ️ 用户已拥有该订阅: \(product.id)，不允许重复购买")
                return
            }
            
            print("🔄 用户点击购买: \(product.id)")
            print("🔄 当前订阅状态: isActive=\(entitlementManager.isSubscriptionActive), productID=\(entitlementManager.currentSubscriptionProductID ?? "nil")")
            
            // 立即设置购买状态，提供即时反馈
            isPurchasing.insert(product.id)
            
            Task { @MainActor in
                // 清除之前的错误信息
                purchaseManager.errorMessage = nil
                
                print("🔄 准备调用 purchase()，等待系统弹窗...")
                // 执行购买
                let transaction = await purchaseManager.purchase(product)
                
                print("🔄 purchase() 返回: transaction=\(transaction != nil ? "有" : "无")")
                
                // 如果购买成功，更新权益
                if let transaction = transaction {
                    print("🔄 购买成功，基于交易直接更新权益状态...")
                    
                    // 使用刚完成的交易直接更新权益
                    entitlementManager.updateEntitlement(from: transaction)
                    
                    // 等待权益更新完成
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3秒
                    
                    print("🔄 权益更新完成，当前状态: entitlement=\(entitlementManager.currentEntitlement), isActive=\(entitlementManager.isSubscriptionActive), productID=\(entitlementManager.currentSubscriptionProductID ?? "nil")")
                    
                    // 如果权益更新成功，关闭 PaywallView
                    if entitlementManager.isSubscriptionActive {
                        print("✅ 订阅已激活，关闭 PaywallView")
                        dismiss()
                    } else {
                        print("⚠️ 订阅状态未更新，尝试使用标准方法更新...")
                        // 如果直接更新失败，尝试使用标准方法
                        entitlementManager.updateEntitlement()
                    }
                }
                
                // 延迟移除购买状态，确保用户看到反馈
                if transaction == nil && purchaseManager.errorMessage == nil {
                    // 用户取消，立即移除状态
                    print("🔄 用户取消或购买失败，移除购买状态")
                    isPurchasing.remove(product.id)
                } else {
                    // 购买成功或失败，延迟移除状态
                    print("🔄 延迟移除购买状态...")
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1秒延迟
                    isPurchasing.remove(product.id)
                }
            }
        } label: {
            HStack {
                VStack(spacing: 6) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)
                        Spacer()
                        if isCurrentSubscription {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.subheadline)
                                Text("paywall_current_subscription".localized)
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text(product.displayPrice)
                                .font(.headline)
                        }
                    }
                    HStack {
                        Text(subtitle(for: product))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if isCurrentSubscription {
                            if let expiryDate = entitlementManager.subscriptionExpiryDate {
                                Text("paywall_expires_on".localized + formatDate(expiryDate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("membership_status_lifetime_active".localized)
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
                
                if isPurchasingThis {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isCurrentSubscription ? 
                          Color.green.opacity(colorScheme == .dark ? 0.2 : 0.1) :
                          brandColorManager.currentBrandColor.opacity(colorScheme == .dark ? 0.25 : 0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isCurrentSubscription ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isPurchasingThis || isCurrentSubscription)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }

    private func sortedProducts() -> [Product] {
        purchaseManager.products.sorted { lhs, rhs in
            lhs.price < rhs.price
        }
    }

    private func subtitle(for product: Product) -> String {
        if product.id == SubscriptionProductID.proLifetime {
            return "one_time_purchase".localized
        }
        if let unit = product.subscription?.subscriptionPeriod.unit {
            return unit.title
        }
        return ""
    }
    
    private var hasLifetime: Bool {
        entitlementManager.currentEntitlement == .pro && entitlementManager.subscriptionExpiryDate == nil
    }
    
    private var lifetimeUnlockedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("paywall_lifetime_unlocked".localized)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            Text("paywall_lifetime_sync_hint".localized)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private extension Product.SubscriptionPeriod.Unit {
    var title: String {
        switch self {
        case .month: return "subscription_monthly".localized
        case .year: return "subscription_yearly".localized
        case .week: return "subscription_weekly".localized
        case .day: return "subscription_daily".localized
        @unknown default: return "subscription_default".localized
        }
    }
}
