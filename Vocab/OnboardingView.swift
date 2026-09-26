//
//  OnboardingView.swift
//  Vocab
//
//  首次安装：选择学习语言与母语后进入应用
//

import SwiftUI
import UIKit

enum OnboardingStorage {
    static let completedKey = "vocab_onboarding_completed"
    
    /// 仅全新安装展示。已发放免费额度或已有调用次数记录的用户视为既有用户。
    static var shouldShow: Bool {
        if UserDefaults.standard.bool(forKey: completedKey) {
            return false
        }
        if UserDefaults.standard.bool(forKey: "vocab_ai_free_trial_granted") {
            return false
        }
        if UserDefaults.standard.object(forKey: "ai_api_remaining_calls") != nil {
            return false
        }
        return true
    }
    
    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case languages
    case freeTrial
}

struct OnboardingView: View {
    var onComplete: () -> Void
    
    @ObservedObject private var settingsManager = AppSettingsManager.shared
    @ObservedObject private var localizedString = LocalizedString.shared
    @State private var step: OnboardingStep = .welcome
    
    private var learningLanguages: [AppLanguage] {
        AppLanguage.allCases
    }
    
    private var nativeLanguages: [AppLanguage] {
        AppLanguage.allCases
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
            
            TabView(selection: $step) {
                welcomePage
                    .tag(OnboardingStep.welcome)
                languagesPage
                    .tag(OnboardingStep.languages)
                freeTrialPage
                    .tag(OnboardingStep.freeTrial)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: step)
            
            bottomButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .padding(.top, 12)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .tint(Color.vocabBrand)
        .onAppear {
            suggestLearningLanguageIfNeeded()
        }
        .modifier(OnboardingSelectionFeedback(trigger: settingsManager.targetLanguage))
        .modifier(OnboardingSelectionFeedback(trigger: settingsManager.language))
    }
    
    private var headerBar: some View {
        HStack {
            if step != .welcome {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedKey.onboardingBack.rawValue.localized)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            
            Spacer()
            
            stepIndicator
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    String(
                        format: LocalizedKey.onboardingStepFormat.rawValue.localized,
                        step.rawValue + 1,
                        OnboardingStep.allCases.count
                    )
                )
            
            Spacer()
            
            Color.clear.frame(width: 44, height: 44)
        }
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item == step ? Color.vocabBrand : Color.secondary.opacity(0.25))
                    .frame(width: item == step ? 20 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
        .accessibilityHidden(true)
    }
    
    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            
            VStack(spacing: 12) {
                Text("Vocab Ai")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                Text(LocalizedKey.onboardingValueProposition)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
    }
    
    private var languagesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                languageSection(
                    title: LocalizedKey.onboardingLearnTitle.rawValue.localized,
                    subtitle: LocalizedKey.onboardingLearnSubtitle.rawValue.localized,
                    languages: learningLanguages,
                    selection: $settingsManager.targetLanguage
                )
                languageSection(
                    title: LocalizedKey.onboardingNativeTitle.rawValue.localized,
                    subtitle: LocalizedKey.onboardingNativeSubtitle.rawValue.localized,
                    languages: nativeLanguages,
                    selection: $settingsManager.language
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
    }
    
    private var freeTrialPage: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "gift.fill")
                .font(.system(size: 56))
                .foregroundStyle(LinearGradient.vocabBrandProgress)
            
            VStack(spacing: 12) {
                Text(LocalizedKey.freeTrialWelcomeTitle)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                
                Text(String(format: LocalizedKey.freeTrialWelcomeMessage.rawValue.localized, UsageTracker.freeTrialCalls))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
    }
    
    private func languageSection(
        title: String,
        subtitle: String,
        languages: [AppLanguage],
        selection: Binding<AppLanguage>
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2.weight(.bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(languages, id: \.self) { language in
                    OnboardingLanguageCard(
                        language: language,
                        isSelected: selection.wrappedValue == language
                    ) {
                        if #unavailable(iOS 26) {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        selection.wrappedValue = language
                    }
                }
            }
        }
    }
    
    private var bottomButton: some View {
        Button {
            if step == .freeTrial {
                finish()
            } else {
                goForward()
            }
        } label: {
            Text(step == .freeTrial
                 ? LocalizedKey.onboardingComplete.rawValue.localized
                 : LocalizedKey.onboardingContinue.rawValue.localized)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(LinearGradient.vocabBrandProgress, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .controlSize(.large)
        .modifier(OnboardingImpactFeedback(trigger: step))
        .accessibilityLabel(
            step == .freeTrial
                ? LocalizedKey.onboardingComplete.rawValue.localized
                : LocalizedKey.onboardingContinue.rawValue.localized
        )
    }
    
    private func goForward() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            step = next
        }
    }
    
    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            step = previous
        }
    }
    
    private func suggestLearningLanguageIfNeeded() {
        if settingsManager.targetLanguage == settingsManager.language,
           settingsManager.language != .english {
            settingsManager.targetLanguage = .english
        }
    }
    
    private func finish() {
        _ = UsageTracker.shared
        UsageTracker.markFreeTrialWelcomeShown()
        OnboardingStorage.markCompleted()
        onComplete()
    }
}

private struct OnboardingLanguageCard: View {
    let language: AppLanguage
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(language.onboardingGlyph)
                    .font(.headline)
                    .frame(width: 28)
                
                Text(language.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer(minLength: 0)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.vocabBrand)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.vocabBrand.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.vocabBrand : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct OnboardingSelectionFeedback: ViewModifier {
    let trigger: AppLanguage
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.sensoryFeedback(.selection, trigger: trigger)
        } else {
            content
        }
    }
}

private struct OnboardingImpactFeedback: ViewModifier {
    let trigger: OnboardingStep
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.sensoryFeedback(.impact(flexibility: .solid), trigger: trigger)
        } else {
            content
        }
    }
}

private extension AppLanguage {
    var onboardingGlyph: String {
        switch self {
        case .chinese:
            return "文"
        case .chineseTraditional:
            return "繁"
        case .english:
            return "A"
        case .japanese:
            return "あ"
        case .french:
            return "F"
        case .spanish:
            return "Ñ"
        case .korean:
            return "한"
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
