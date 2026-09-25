//
//  ContentView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData
import UIKit

enum AppView {
    case study
    case exercise
    case guess
    case list
}

/// 词库为空时的统一空状态：说明 + 可点的添加入口
struct EmptyLibraryPrompt: View {
    var title: String
    var systemImage: String
    var descriptionKey: LocalizedKey = .goAddWords
    var buttonTitleKey: LocalizedKey = .goToLibraryAdd
    var action: () -> Void
    
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(descriptionKey)
        } actions: {
            Button(action: action) {
                Label(buttonTitleKey.rawValue.localized, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.vocabBrand)
            .controlSize(.large)
            .accessibilityLabel(buttonTitleKey.rawValue.localized)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView: View {
    @State private var selectedTab: AppView = .study
    @State private var isExerciseInProgress = false
    @State private var isGuessSessionActive = false
    @State private var endGuessSessionRequested = false
    @State private var showLeaveGuessConfirm = false
    @State private var showFreeTrialWelcome = false
    @State private var showOnboarding = OnboardingStorage.shouldShow
    @ObservedObject private var localizedString = LocalizedString.shared
    
    private var tabSelection: Binding<AppView> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if selectedTab == .guess && newValue != .guess && isGuessSessionActive {
                    showLeaveGuessConfirm = true
                } else {
                    selectedTab = newValue
                }
            }
        )
    }

    var body: some View {
        if showOnboarding {
            OnboardingView {
                showOnboarding = false
            }
        } else {
            mainTabs
        }
    }
    
    private var mainTabs: some View {
        TabView(selection: tabSelection) {
            StudyView(selectedTab: $selectedTab)
                .tabItem {
                    Label(LocalizedKey.tabStudy.rawValue.localized, systemImage: "brain.head.profile")
                }
                .tag(AppView.study)
            
            ExerciseView(isExerciseInProgress: $isExerciseInProgress, selectedTab: $selectedTab)
                .tabItem {
                    Label(LocalizedKey.tabExercise.rawValue.localized, systemImage: "text.badge.checkmark")
                }
                .tag(AppView.exercise)
            
            GuessWordGameView(
                isSessionActive: $isGuessSessionActive,
                endSessionRequested: $endGuessSessionRequested,
                selectedTab: $selectedTab
            )
                .tabItem {
                    Label(LocalizedKey.tabGuess.rawValue.localized, systemImage: "puzzlepiece.extension")
                }
                .tag(AppView.guess)
            
            WordListView()
                .tabItem {
                    Label(LocalizedKey.tabWordList.rawValue.localized, systemImage: "list.bullet")
                }
                .tag(AppView.list)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .applyTabViewStyle()
        .onAppear {
            _ = UsageTracker.shared
            if UsageTracker.shouldShowFreeTrialWelcome {
                showFreeTrialWelcome = true
            }
        }
        .sheet(isPresented: $showFreeTrialWelcome) {
            FreeTrialWelcomeView(onDismiss: {
                showFreeTrialWelcome = false
            })
        }
        .alert(
            LocalizedKey.guessLeaveTitle.rawValue.localized,
            isPresented: $showLeaveGuessConfirm
        ) {
            Button(LocalizedKey.guessLeaveConfirm.rawValue.localized) {
                endGuessSessionRequested = true
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {}
        } message: {
            Text(LocalizedKey.guessLeaveMessage)
        }
    }
}

// iOS 26+ 样式扩展
extension View {
    @ViewBuilder
    func applyTabViewStyle() -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26+ 使用沉浸式浮动标签栏（SwiftUI 8）
            // 注意：这些 API 可能在 iOS 26 SDK 发布前不可用
            // 如果编译错误，请暂时注释掉以下两行，使用标准样式
            self.tabViewStyle(.automatic)
            // self.tabViewStyle(.expanded)
            // self.tabBarToolbar(.visible)
        } else {
            // iOS 18-25 使用标准样式
            self.tabViewStyle(.automatic)
        }
    }
    
    /// 点击空白处收起键盘（不阻断按钮等控件点击）
    func dismissKeyboardOnTap() -> some View {
        background(DismissKeyboardTapCatcher())
    }
}

/// 用 UIKit 手势收起键盘，`cancelsTouchesInView = false` 避免抢走 Form / 按钮点击。
private struct DismissKeyboardTapCatcher: UIViewRepresentable {
    func makeUIView(context: Context) -> DismissKeyboardHostView {
        DismissKeyboardHostView()
    }
    
    func updateUIView(_ uiView: DismissKeyboardHostView, context: Context) {}
}

private final class DismissKeyboardHostView: UIView, UIGestureRecognizerDelegate {
    private weak var attachedTo: UIView?
    private var tap: UITapGestureRecognizer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        detachTap()
        guard window != nil, let host = superview else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        host.addGestureRecognizer(recognizer)
        attachedTo = host
        tap = recognizer
    }
    
    deinit {
        detachTap()
    }
    
    private func detachTap() {
        if let tap {
            attachedTo?.removeGestureRecognizer(tap)
        }
        tap = nil
        attachedTo = nil
    }
    
    @objc private func handleTap() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UIControl || current is UITextField || current is UITextView {
                return false
            }
            view = current.superview
        }
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationManager.shared)
        .modelContainer(for: [Word.self, WordSheet.self], inMemory: true)
}
