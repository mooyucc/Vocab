//
//  PaywallView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/29.
//

import SwiftUI
import StoreKit

private let paywallGradient = LinearGradient(
    colors: [Color(hex: "FE6A57"), Color(hex: "FE2E69")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct PaywallView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var purchaseManager = PurchaseManager.shared
    @StateObject private var usageTracker = UsageTracker.shared
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    // 标题区域（带图标）
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(paywallGradient)
                        
                        Text("paywall_usage_title".localized)
                            .font(.title.weight(.bold))
                        
                        Text("paywall_usage_subtitle".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .padding(.top, 16)
                    
                    // 使用情况卡片（渐变背景）
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("usage_remaining".localized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.9))
                            Text("\(usageTracker.remainingCalls)")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        Spacer()
                        
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(width: 1, height: 40)
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("usage_total_used".localized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.9))
                            Text("\(usageTracker.totalCallsUsed)")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(paywallGradient)
                            .shadow(color: Color(hex: "FE2E69").opacity(0.35), radius: 12, x: 0, y: 6)
                    )
                    .padding(.horizontal, 20)
                    
                    // 购买选项
                    if let product = purchaseManager.products.first {
                        VStack(spacing: 12) {
                            Text("usage_purchase_title".localized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                            
                            PurchaseCard(
                                product: product,
                                calls: UsageTracker.callsPerPurchase,
                                price: UsageTracker.pricePerPurchase
                            ) {
                                await purchaseProduct(product)
                            }
                            .disabled(isPurchasing)
                        }
                    } else if purchaseManager.isLoading {
                        ProgressView()
                            .scaleEffect(1.1)
                            .padding(.vertical, 24)
                    }
                    
                    // 说明与消耗说明（卡片式）
                    VStack(spacing: 14) {
                        Text(String(format: "usage_purchase_description".localized, UsageTracker.callsPerPurchase))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text("usage_purchase_note".localized)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("usage_consumption_info".localized, systemImage: "info.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "text.badge.plus")
                                    .font(.caption)
                                    .foregroundStyle(paywallGradient)
                                Text("usage_consumption_ai_fill".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(paywallGradient)
                                Text("usage_consumption_ai_example".localized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    
                    // 恢复购买
                    Button {
                        Task { await purchaseManager.restorePurchases() }
                    } label: {
                        Text("paywall_button_restore".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 28)
                    
                    Spacer(minLength: 24)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("error".localized, isPresented: $showError) {
                Button("ok".localized, role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func purchaseProduct(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        
        do {
            let success = try await purchaseManager.purchase(product)
            if success {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

struct PurchaseCard: View {
    let product: Product
    let calls: Int
    let price: Double
    let onPurchase: () async -> Void
    
    @State private var isPurchasing = false
    
    var body: some View {
        Button {
            Task {
                isPurchasing = true
                await onPurchase()
                isPurchasing = false
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "bolt.circle.fill")
                    .font(.title2)
                    .foregroundStyle(paywallGradient)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "usage_purchase_calls".localized, calls))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Text(product.displayPrice.isEmpty ? String(format: "usage_price_format".localized, price) : product.displayPrice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isPurchasing {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(paywallGradient.opacity(0.5), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

#Preview {
    PaywallView()
}
