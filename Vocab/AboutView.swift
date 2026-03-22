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
        return "2.3"
    }
    
    var buildNumber: String {
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return build
        }
        return "10"
    }
    
    var body: some View {
        Form {
            // 应用信息部分
            Section {
                VStack(spacing: 16) {
                    // 应用图标
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    
                    // 应用名称
                    Text("Vocab Ai")
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
                Link(LocalizedKey.softwareLicense.rawValue.localized, destination: URL(string: "https://mooyu.cc/moovocablicense.html")!)
                    .foregroundStyle(.blue)
                
                Link(LocalizedKey.privacyPolicy.rawValue.localized, destination: URL(string: "https://mooyu.cc/moovocabprivacy.html")!)
                    .foregroundStyle(.blue)
            } footer: {
                VStack(alignment: .center, spacing: 8) {
                    Text(LocalizedKey.copyright.rawValue.localized)
                        .foregroundStyle(.secondary)
                    Text("All Rights Reserved")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
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
                        title: LocalizedKey.wordManagement.rawValue.localized,
                        description: LocalizedKey.wordManagementDescription.rawValue.localized
                    )
                    
                    FeatureItem(
                        icon: "brain.head.profile",
                        title: LocalizedKey.intelligentLearning.rawValue.localized,
                        description: LocalizedKey.intelligentLearningDescription.rawValue.localized
                    )
                    
                    FeatureItem(
                        icon: "camera.fill",
                        title: LocalizedKey.cameraRecognition.rawValue.localized,
                        description: LocalizedKey.cameraRecognitionDescription.rawValue.localized
                    )
                    
                    FeatureItem(
                        icon: "chart.line.uptrend.xyaxis",
                        title: LocalizedKey.learningProgress.rawValue.localized,
                        description: LocalizedKey.learningProgressDescription.rawValue.localized
                    )
                    
                    FeatureItem(
                        icon: "arrow.triangle.2.circlepath",
                        title: LocalizedKey.reviewSystem.rawValue.localized,
                        description: LocalizedKey.reviewSystemDescription.rawValue.localized
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
                    version: "2.4",
                    date: LocalizedKey.versionUpdate24Date.rawValue.localized,
                    updates: [
                        LocalizedKey.versionUpdate24RecommendedReview.rawValue.localized,
                        LocalizedKey.versionUpdate24ProgressTab.rawValue.localized,
                        LocalizedKey.versionUpdate24StudyUI.rawValue.localized,
                        LocalizedKey.versionUpdate24SettingsData.rawValue.localized,
                        LocalizedKey.versionUpdate24AIPaywall.rawValue.localized,
                        LocalizedKey.versionUpdate24Stability.rawValue.localized
                    ]
                )
                VersionItem(
                    version: "2.3",
                    date: LocalizedKey.versionDateFormat.rawValue.localized,
                    updates: [
                        LocalizedKey.firstRelease.rawValue.localized,
                        LocalizedKey.supportWordAdd.rawValue.localized,
                        LocalizedKey.aiSmartFillFeature.rawValue.localized,
                        LocalizedKey.cameraRecognizeFeature.rawValue.localized,
                        LocalizedKey.progressTracking.rawValue.localized,
                        LocalizedKey.reviewSystemFeature.rawValue.localized
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
