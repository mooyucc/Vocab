//
//  FreeTrialWelcomeView.swift
//  Vocab
//
//  新装/升级用户获得免费 AI 调用额度时的提示页（一次性）
//

import SwiftUI

private let welcomeGradient = LinearGradient(
    colors: [Color(hex: "FE6A57"), Color(hex: "FE2E69")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

struct FreeTrialWelcomeView: View {
    var onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            Image(systemName: "gift.fill")
                .font(.system(size: 56))
                .foregroundStyle(welcomeGradient)
            
            VStack(spacing: 12) {
                Text("free_trial_welcome_title".localized)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                
                Text(String(format: "free_trial_welcome_message".localized, UsageTracker.freeTrialCalls))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            
            Spacer()
            
            Button(action: {
                UsageTracker.markFreeTrialWelcomeShown()
                onDismiss()
            }) {
                Text("free_trial_welcome_button".localized)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(welcomeGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .padding(.top, 40)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    FreeTrialWelcomeView(onDismiss: {})
}
