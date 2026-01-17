//
//  SettingsView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import AuthenticationServices
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var entitlementManager: EntitlementManager
    @ObservedObject private var settingsManager = AppSettingsManager.shared
    @State private var showSignOutAlert = false
    @State private var showEditNameSheet = false
    @State private var editingName = ""
    @State private var showPaywall = false
    
    var body: some View {
        NavigationStack {
            Form {
                // 用户账户部分
                Section {
                    if authManager.isSignedIn {
                        // 已登录状态
                        HStack(spacing: 16) {
                            // 用户头像占位符
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.indigo, Color.purple]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                                .overlay {
                                    if let name = authManager.userName, !name.isEmpty {
                                        Text(String(name.prefix(1)))
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.white)
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.title2)
                                            .foregroundStyle(.white)
                                    }
                                }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = authManager.userName, !name.isEmpty {
                                    Text(name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                } else {
                                    Text("Apple 用户")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }
                            }
                            
                            Spacer()
                            
                            // 编辑用户名按钮
                            Button(action: {
                                editingName = authManager.userName ?? ""
                                showEditNameSheet = true
                            }) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Button(role: .destructive, action: {
                            showSignOutAlert = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.square")
                                Text(LocalizedKey.signOut)
                            }
                        }
                    } else {
                        // 未登录状态
                        SignInWithAppleButton(
                            onRequest: { request in
                                request.requestedScopes = [.fullName, .email]
                            },
                            onCompletion: { result in
                                switch result {
                                case .success(let authorization):
                                    if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                        Task { @MainActor in
                                            let userIdentifier = appleIDCredential.user
                                            let email = appleIDCredential.email
                                            let fullName = appleIDCredential.fullName
                                            
                                            // 优先从 Apple 获取用户名（首次登录或再次登录时如果提供）
                                            var name: String?
                                            if let givenName = fullName?.givenName, let familyName = fullName?.familyName {
                                                name = "\(givenName) \(familyName)"
                                                print("✅ [SettingsView] 从 Apple 获取完整用户名: \(name!)")
                                            } else if let givenName = fullName?.givenName {
                                                name = givenName
                                                print("✅ [SettingsView] 从 Apple 获取名字: \(name!)")
                                            } else if let familyName = fullName?.familyName {
                                                name = familyName
                                                print("✅ [SettingsView] 从 Apple 获取姓氏: \(name!)")
                                            } else {
                                                print("⚠️ [SettingsView] Apple 未提供用户名（可能是再次登录）")
                                            }
                                            
                                            // 如果 Apple 提供了名字，使用它；如果没有提供，尝试从本地读取已保存的名字
                                            // 这样确保无论何时登录，都能读取到用户名
                                            if name == nil || name?.isEmpty == true {
                                                name = UserDefaults.standard.string(forKey: "userName")
                                                if let name = name {
                                                    print("📝 [SettingsView] 从本地读取已保存的用户名: \(name)")
                                                } else {
                                                    print("⚠️ [SettingsView] 本地也没有保存的用户名")
                                                }
                                            }
                                            
                                            // 保存用户信息（如果 Apple 提供了新名字，会更新保存；否则保持已保存的名字）
                                            authManager.saveUserInfo(identifier: userIdentifier, email: email, name: name)
                                        }
                                    }
                                case .failure(let error):
                                    // 检查是否是用户取消
                                    if let authError = error as? ASAuthorizationError,
                                       authError.code == .canceled {
                                        print("用户取消了登录")
                                        // 不显示错误提示，因为这是用户主动取消
                                    } else {
                                        print("登录失败: \(error.localizedDescription)")
                                        // 可以在这里添加用户友好的错误提示
                                    }
                                }
                            }
                        )
                        .frame(height: 50)
                        .cornerRadius(10)
                    }
                } header: {
                    Text(LocalizedKey.account)
                }
                
                // 通用设置部分
                Section {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        Label(LocalizedKey.general.rawValue.localized, systemImage: "gearshape")
                    }
                } header: {
                    Text(LocalizedKey.general)
                }
                
                // 数据部分
                Section {
                    NavigationLink {
                        DataSettingsView()
                    } label: {
                        Label(LocalizedKey.data.rawValue.localized, systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text(LocalizedKey.data)
                }
                
                // 订阅部分
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Label("订阅会员", systemImage: "crown.fill")
                                .foregroundColor(.primary)
                            Spacer()
                            if entitlementManager.isSubscriptionActive {
                                Text(entitlementManager.currentEntitlement == .pro ? "Pro" : "免费")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("订阅")
                }
                
                // 应用设置部分
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label(LocalizedKey.about.rawValue.localized, systemImage: "info.circle")
                    }
                    
                    NavigationLink {
                        Text(LocalizedKey.help)
                            .navigationTitle(LocalizedKey.help.rawValue.localized)
                    } label: {
                        Label(LocalizedKey.help.rawValue.localized, systemImage: "questionmark.circle")
                    }
                } header: {
                    Text(LocalizedKey.app)
                }
            }
            .navigationTitle(LocalizedKey.settings.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LocalizedKey.done.rawValue.localized) {
                        dismiss()
                    }
                }
            }
            .alert(LocalizedKey.signOut.rawValue.localized, isPresented: $showSignOutAlert) {
                Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) { }
                Button(LocalizedKey.signOut.rawValue.localized, role: .destructive) {
                    authManager.signOut()
                }
            } message: {
                Text(LocalizedKey.signOutConfirm)
            }
            .sheet(isPresented: $showEditNameSheet) {
                EditUserNameView(
                    userName: $editingName,
                    onSave: { newName in
                        authManager.updateUserName(newName)
                        showEditNameSheet = false
                    },
                    onCancel: {
                        showEditNameSheet = false
                    }
                )
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .preferredColorScheme(settingsManager.appearanceMode.colorScheme)
        }
    }
}

// Sign in with Apple 按钮封装
struct SignInWithAppleButton: View {
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void
    
    var body: some View {
        SignInWithAppleButtonView(onRequest: onRequest, onCompletion: onCompletion)
    }
}

struct SignInWithAppleButtonView: UIViewRepresentable {
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void
    
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.cornerRadius = 10
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleAuthorization), for: .touchUpInside)
        return button
    }
    
    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onRequest: onRequest, onCompletion: onCompletion)
    }
    
    class Coordinator: NSObject {
        let onRequest: (ASAuthorizationAppleIDRequest) -> Void
        let onCompletion: (Result<ASAuthorization, Error>) -> Void
        var authorizationController: ASAuthorizationController?
        
        init(onRequest: @escaping (ASAuthorizationAppleIDRequest) -> Void,
             onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
            self.onRequest = onRequest
            self.onCompletion = onCompletion
        }
        
        @objc func handleAuthorization() {
            // 防止重复请求
            guard authorizationController == nil else {
                print("授权请求已在进行中")
                return
            }
            
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            
            // 调用自定义的 onRequest 回调
            onRequest(request)
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            
            // 保存 controller 引用，防止被释放
            self.authorizationController = controller
            controller.performRequests()
        }
    }
}

extension SignInWithAppleButtonView.Coordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onCompletion(.success(authorization))
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onCompletion(.failure(error))
    }
}

extension SignInWithAppleButtonView.Coordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("无法获取窗口")
        }
        return window
    }
}

// 编辑用户名视图
struct EditUserNameView: View {
    @Binding var userName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var isTextFieldFocused: Bool
    @State private var editedName: String
    
    init(userName: Binding<String>, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self._userName = userName
        self.onSave = onSave
        self.onCancel = onCancel
        self._editedName = State(initialValue: userName.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("用户名", text: $editedName)
                        .focused($isTextFieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                } header: {
                    Text("用户名")
                } footer: {
                    Text("修改后的用户名将显示在应用中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("编辑用户名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(LocalizedKey.cancel.rawValue.localized) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LocalizedKey.save.rawValue.localized) {
                        let trimmedName = editedName.trimmingCharacters(in: .whitespaces)
                        if !trimmedName.isEmpty {
                            onSave(trimmedName)
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(editedName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // 延迟一下再聚焦，确保视图已完全显示
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
