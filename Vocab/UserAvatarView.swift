//
//  UserAvatarView.swift
//  Vocab
//

import SwiftUI
import PhotosUI

/// 用户头像：优先显示本地上传图，否则显示姓名首字 / 默认人像
struct UserAvatarView: View {
    enum Style {
        /// 设置页：品牌渐变底 + 白字
        case settings
        /// 学习首页品牌粉底上：白底 + 品牌字色
        case onBrand
        /// 进度页浅色底：表面色底 + 品牌字色
        case onCanvas
    }
    
    var image: UIImage?
    var userName: String?
    var size: CGFloat = 60
    var style: Style = .settings
    
    private var monogram: String? {
        guard let userName, !userName.isEmpty else { return nil }
        return String(userName.prefix(1))
    }
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if style == .onBrand {
                Circle().strokeBorder(Color.white, lineWidth: 2)
            } else if style == .onCanvas {
                Circle().strokeBorder(Color.vocabInk.opacity(0.08), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
    
    @ViewBuilder
    private var placeholder: some View {
        ZStack {
            backgroundFill
            if let monogram {
                Text(monogram)
                    .font(size >= 56 ? .title2.weight(.semibold) : .headline.weight(.semibold))
                    .foregroundStyle(monogramForeground)
            } else {
                Image(systemName: "person.fill")
                    .font(size >= 56 ? .title2 : .headline)
                    .foregroundStyle(monogramForeground)
            }
        }
    }
    
    @ViewBuilder
    private var backgroundFill: some View {
        switch style {
        case .settings:
            Circle().fill(LinearGradient.vocabBrandProgress)
        case .onBrand:
            Circle().fill(Color.white.opacity(0.95))
        case .onCanvas:
            Circle().fill(Color.vocabSurface)
        }
    }
    
    private var monogramForeground: Color {
        switch style {
        case .settings:
            return .white
        case .onBrand, .onCanvas:
            return .vocabBrandDeep
        }
    }
}

/// 设置页：点按头像更换 / 删除本地头像
struct AvatarEditButton: View {
    @ObservedObject var authManager: AuthenticationManager
    var size: CGFloat = 60
    
    @State private var photoItem: PhotosPickerItem?
    @State private var showAvatarActions = false
    @State private var showPhotoPicker = false
    @State private var isLoading = false
    
    var body: some View {
        Button {
            showAvatarActions = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                UserAvatarView(
                    image: authManager.avatarImage,
                    userName: authManager.userName,
                    size: size,
                    style: .settings
                )
                
                Image(systemName: "camera.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.vocabBrand)
                    .font(.system(size: 22))
                    .background(Circle().fill(Color(.systemBackground)).padding(2))
                    .offset(x: 2, y: 2)
                
                if isLoading {
                    ProgressView()
                        .frame(width: size, height: size)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizedKey.changeAvatar.rawValue.localized)
        .confirmationDialog(
            LocalizedKey.changeAvatar.rawValue.localized,
            isPresented: $showAvatarActions,
            titleVisibility: .visible
        ) {
            Button(LocalizedKey.chooseFromPhotos.rawValue.localized) {
                showPhotoPicker = true
            }
            if authManager.avatarImage != nil {
                Button(LocalizedKey.removeAvatar.rawValue.localized, role: .destructive) {
                    authManager.clearAvatar()
                }
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadAndSave(item: newItem) }
        }
    }
    
    @MainActor
    private func loadAndSave(item: PhotosPickerItem) async {
        isLoading = true
        defer {
            isLoading = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                return
            }
            _ = authManager.updateAvatar(image)
        } catch {
            print("⚠️ 读取头像失败: \(error.localizedDescription)")
        }
    }
}
