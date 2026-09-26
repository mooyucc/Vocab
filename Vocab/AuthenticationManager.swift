//
//  AuthenticationManager.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import Foundation
import AuthenticationServices
import Combine
import UIKit

@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isSignedIn: Bool = false
    @Published var userIdentifier: String?
    @Published var userEmail: String?
    @Published var userName: String?
    @Published var avatarImage: UIImage?
    
    private let userDefaults = UserDefaults.standard
    private let userIdentifierKey = "userIdentifier"
    private let userEmailKey = "userEmail"
    private let userNameKey = "userName"
    private let avatarFileName = "userAvatar.jpg"
    private let avatarMaxPixel: CGFloat = 512
    
    override init() {
        super.init()
        loadUserInfo()
        // 如果已登录但没有用户名，尝试验证登录状态
        if isSignedIn, let identifier = userIdentifier, userName == nil || userName?.isEmpty == true {
            checkAppleIDCredentialState(for: identifier)
        }
    }
    
    private func loadUserInfo() {
        userIdentifier = userDefaults.string(forKey: userIdentifierKey)
        userEmail = userDefaults.string(forKey: userEmailKey)
        userName = userDefaults.string(forKey: userNameKey)
        isSignedIn = userIdentifier != nil
        avatarImage = loadAvatarFromDisk()
    }
    
    private var avatarFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(avatarFileName)
    }
    
    private func loadAvatarFromDisk() -> UIImage? {
        let url = avatarFileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
    
    /// 保存用户头像（居中裁方并压缩后写入 Documents）
    @discardableResult
    func updateAvatar(_ image: UIImage) -> Bool {
        let prepared = image.normalized().squaredAndResized(maxPixel: avatarMaxPixel)
        guard let data = prepared.jpegData(compressionQuality: 0.86) else {
            print("⚠️ 头像 JPEG 编码失败")
            return false
        }
        do {
            try data.write(to: avatarFileURL, options: .atomic)
            avatarImage = prepared
            print("✅ 头像已保存")
            return true
        } catch {
            print("⚠️ 头像保存失败: \(error.localizedDescription)")
            return false
        }
    }
    
    func clearAvatar() {
        let url = avatarFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        avatarImage = nil
    }
    
    // 检查 Apple ID 凭证状态（用于验证登录状态，但无法获取用户名）
    private func checkAppleIDCredentialState(for userIdentifier: String) {
        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: userIdentifier) { [weak self] credentialState, error in
            Task { @MainActor in
                guard let self = self else { return }
                
                if let error = error {
                    print("检查 Apple ID 凭证状态失败: \(error.localizedDescription)")
                    return
                }
                
                switch credentialState {
                case .authorized:
                    // 用户已授权，但无法通过此方法获取用户名
                    // 用户名只能通过首次登录时获取，或由用户手动设置
                    print("Apple ID 凭证状态：已授权")
                case .revoked, .notFound:
                    // 用户已撤销授权或未找到，清除登录状态
                    print("Apple ID 凭证状态：已撤销或未找到")
                    self.signOut()
                case .transferred:
                    // 凭证已转移
                    print("Apple ID 凭证状态：已转移")
                @unknown default:
                    print("Apple ID 凭证状态：未知")
                }
            }
        }
    }
    
    func saveUserInfo(identifier: String, email: String?, name: String?) {
        userDefaults.set(identifier, forKey: userIdentifierKey)
        
        // 处理邮箱：如果提供了新邮箱（首次登录或再次登录时提供），更新保存
        if let email = email, !email.isEmpty {
            userDefaults.set(email, forKey: userEmailKey)
            userEmail = email
            print("✅ 保存新邮箱: \(email)")
        } else {
            // 如果没有新邮箱，保持已保存的邮箱
            userEmail = userDefaults.string(forKey: userEmailKey)
            print("📧 使用已保存的邮箱: \(userEmail ?? "无")")
        }
        
        // 处理用户名：如果提供了新名字（首次登录或再次登录时 Apple 提供），更新保存
        if let name = name, !name.isEmpty {
            // 如果提供了新名字（无论是首次还是再次登录），都更新保存
            userDefaults.set(name, forKey: userNameKey)
            userName = name
            print("✅ 保存新用户名: \(name)")
        } else {
            // 如果没有提供新名字，从本地读取已保存的名字
            let savedName = userDefaults.string(forKey: userNameKey)
            userName = savedName
            if let savedName = savedName {
                print("📝 从本地读取已保存的用户名: \(savedName)")
            } else {
                print("⚠️ 未找到已保存的用户名")
            }
        }
        
        userIdentifier = identifier
        isSignedIn = true
        
        // 确保 UserDefaults 立即同步
        userDefaults.synchronize()
    }
    
    func updateUserName(_ newName: String) {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else {
            print("⚠️ 用户名不能为空")
            return
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        userDefaults.set(trimmedName, forKey: userNameKey)
        userName = trimmedName
        userDefaults.synchronize()
        print("✅ 用户名已更新: \(trimmedName)")
    }
    
    func signOut() {
        userDefaults.removeObject(forKey: userIdentifierKey)
        userDefaults.removeObject(forKey: userEmailKey)
        userDefaults.removeObject(forKey: userNameKey)
        userIdentifier = nil
        userEmail = nil
        userName = nil
        isSignedIn = false
        // 头像为设备本地偏好，退出登录时保留；删除账号时再 clearAvatar()
    }
}

extension UIImage {
    /// 居中裁成正方形并限制边长（调用前建议先 `normalized()`）
    func squaredAndResized(maxPixel: CGFloat) -> UIImage {
        let side = min(size.width, size.height)
        guard side > 0 else { return self }
        let outputSide = min(side, maxPixel)
        let scaleX = outputSide / size.width
        let scaleY = outputSide / size.height
        let drawScale = max(scaleX, scaleY)
        let drawSize = CGSize(width: size.width * drawScale, height: size.height * drawScale)
        let origin = CGPoint(
            x: (outputSide - drawSize.width) / 2,
            y: (outputSide - drawSize.height) / 2
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

extension AuthenticationManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            let userIdentifier = appleIDCredential.user
            let email = appleIDCredential.email
            let fullName = appleIDCredential.fullName
            
            print("🔐 Apple 登录成功，userIdentifier: \(userIdentifier)")
            print("📧 Apple 提供的邮箱: \(email ?? "nil")")
            print("👤 Apple 提供的 fullName: \(fullName?.givenName ?? "nil") \(fullName?.familyName ?? "nil")")
            
            // 优先从 Apple 获取用户名（首次登录或某些情况下会提供）
            var name: String?
            if let givenName = fullName?.givenName, let familyName = fullName?.familyName {
                name = "\(givenName) \(familyName)"
                print("✅ 从 Apple 获取完整用户名: \(name!)")
            } else if let givenName = fullName?.givenName {
                name = givenName
                print("✅ 从 Apple 获取名字: \(name!)")
            } else if let familyName = fullName?.familyName {
                name = familyName
                print("✅ 从 Apple 获取姓氏: \(name!)")
            } else {
                print("⚠️ Apple 未提供用户名（可能是再次登录）")
            }
            
            // 如果 Apple 提供了名字，使用它；如果没有提供，尝试从本地读取已保存的名字
            // 这样确保无论何时登录，都能读取到用户名
            if name == nil || name?.isEmpty == true {
                name = userDefaults.string(forKey: userNameKey)
                if let name = name {
                    print("📝 从本地读取已保存的用户名: \(name)")
                } else {
                    print("⚠️ 本地也没有保存的用户名")
                }
            }
            
            // 保存用户信息（如果 Apple 提供了新名字，会更新保存；否则保持已保存的名字）
            saveUserInfo(identifier: userIdentifier, email: email, name: name)
            
            // 登录后立即重新加载用户信息，确保 UI 更新
            loadUserInfo()
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Apple 登录失败: \(error.localizedDescription)")
    }
}

extension AuthenticationManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("无法获取窗口")
        }
        return window
    }
}
