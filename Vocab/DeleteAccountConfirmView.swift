//
//  DeleteAccountConfirmView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

struct DeleteAccountConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    let modelContext: ModelContext
    let words: [Word]
    let sheets: [WordSheet]
    
    @State private var showDeleteAlert = false
    @State private var isDeleting = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.title2)
                        Text("警告")
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                    
                    Text("删除账户是不可逆的操作。")
                        .font(.subheadline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("删除后将清除以下内容：")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• 账户信息和登录状态")
                            Text(String(format: "• 所有单词数据（%d %@）", words.count, LocalizedKey.word.rawValue.localized))
                            Text(String(format: "• 所有词库（%d %@）", sheets.count, LocalizedKey.wordSheet.rawValue.localized))
                            Text("• 本地备份数据")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Text("此操作无法撤销，请谨慎操作。")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                Button(role: .destructive, action: {
                    showDeleteAlert = true
                }) {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("确认删除账户")
                        }
                        Spacer()
                    }
                }
                .disabled(isDeleting)
            }
        }
        .navigationTitle(LocalizedKey.deleteAccount.rawValue.localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert(LocalizedKey.confirmDelete.rawValue.localized, isPresented: $showDeleteAlert) {
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) { }
            Button(LocalizedKey.delete.rawValue.localized, role: .destructive) {
                deleteAccountAndData()
            }
        } message: {
            Text(LocalizedKey.deleteAccountConfirm)
        }
    }
    
    private func deleteAccountAndData() {
        isDeleting = true
        
        Task {
            do {
                // 删除所有单词
                for word in words {
                    modelContext.delete(word)
                }
                
                // 删除所有词库
                for sheet in sheets {
                    modelContext.delete(sheet)
                }
                
                // 保存更改
                try modelContext.save()
                
                // 清除账户信息
                await MainActor.run {
                    authManager.signOut()
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    print("删除数据失败: \(error.localizedDescription)")
                }
            }
        }
    }
}
