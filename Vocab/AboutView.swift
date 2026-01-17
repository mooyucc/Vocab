//
//  AboutView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "1.0"
    }
    
    var buildNumber: String {
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return build
        }
        return "1"
    }
    
    var body: some View {
        Form {
            // 应用信息部分
            Section {
                VStack(spacing: 16) {
                    // 应用图标
                    Image(systemName: "book.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.indigo, Color.purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                        )
                    
                    // 应用名称
                    Text("Vocab")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    // 版本号
                    Text(String(format: LocalizedKey.version.rawValue.localized, appVersion))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            
            // 信息列表部分
            Section {
                NavigationLink {
                    FeatureIntroductionView()
                } label: {
                    Text(LocalizedKey.features)
                }
                
                NavigationLink {
                    VersionUpdateView()
                } label: {
                    Text(LocalizedKey.updates)
                }
            }
            
            // 法律信息部分
            Section {
                Link("《软件许可及服务协议》", destination: URL(string: "https://example.com/terms")!)
                    .foregroundStyle(.blue)
                
                Link("《隐私保护指引》", destination: URL(string: "https://example.com/privacy")!)
                    .foregroundStyle(.blue)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vocab 版权所有 © 2025")
                        .foregroundStyle(.secondary)
                    Text("All Rights Reserved")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(LocalizedKey.about.rawValue.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 功能介绍页面
struct FeatureIntroductionView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    FeatureItem(
                        icon: "book.fill",
                        title: "单词管理",
                        description: "轻松添加、编辑和管理您的单词库，支持自定义词库分类。"
                    )
                    
                    FeatureItem(
                        icon: "brain.head.profile",
                        title: "智能学习",
                        description: "AI 辅助录入单词，自动生成释义、例句和发音，让学习更高效。"
                    )
                    
                    FeatureItem(
                        icon: "camera.fill",
                        title: "拍照识别",
                        description: "使用相机拍照识别单词，快速添加新词汇到您的学习列表。"
                    )
                    
                    FeatureItem(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "学习进度",
                        description: "实时跟踪学习进度，查看已掌握和待学习的单词统计。"
                    )
                    
                    FeatureItem(
                        icon: "arrow.triangle.2.circlepath",
                        title: "复习系统",
                        description: "智能复习算法，帮助您巩固记忆，提高学习效率。"
                    )
                }
                .padding(.vertical, 8)
            } header: {
                Text(LocalizedKey.coreFeatures)
            }
        }
        .navigationTitle(LocalizedKey.features.rawValue.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// 版本更新页面
struct VersionUpdateView: View {
    var body: some View {
        Form {
            Section {
                VersionItem(
                    version: "1.0",
                    date: "2025年1月",
                    updates: [
                        "首次发布",
                        "支持单词添加和管理",
                        "AI 智能辅助录入",
                        "拍照识别单词功能",
                        "学习进度跟踪",
                        "复习系统"
                    ]
                )
            } header: {
                Text(LocalizedKey.versionHistory)
            }
        }
        .navigationTitle(LocalizedKey.updates.rawValue.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VersionItem: View {
    let version: String
    let date: String
    let updates: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(format: LocalizedKey.version.rawValue.localized, version))
                    .font(.headline)
                Spacer()
                Text(date)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(updates, id: \.self) { update in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(update)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
