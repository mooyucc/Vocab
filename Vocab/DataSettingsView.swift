//
//  DataSettingsView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData
import Foundation
import UIKit
import UniformTypeIdentifiers

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var words: [Word]
    @Query private var sheets: [WordSheet]
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showExportSuccess = false
    @State private var showImportSuccess = false
    @State private var showImportError = false
    @State private var errorMessage = ""
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showDocumentPicker = false
    @State private var showActivitySheet = false
    @State private var exportFileURL: URL?
    
    var body: some View {
        Form {
            // 本地数据部分
            Section {
                Button(action: {
                    importLocalData()
                }) {
                    Label(LocalizedKey.importData.rawValue.localized, systemImage: "square.and.arrow.down")
                }
                .disabled(isImporting)
                
                Button(action: {
                    exportLocalData()
                }) {
                    Label(LocalizedKey.exportData.rawValue.localized, systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting)
            } header: {
                Text(LocalizedKey.localData)
            } footer: {
                Text(LocalizedKey.dataBackup)
            }
            
            // 删除账户部分
            Section {
                NavigationLink {
                    DeleteAccountConfirmView(
                        modelContext: modelContext,
                        words: words,
                        sheets: sheets
                    )
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.minus")
                            .foregroundStyle(.red)
                        Text(LocalizedKey.deleteAccount)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text(LocalizedKey.deleteAccount)
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedKey.deleteAccountDescription)
                    Text(LocalizedKey.deleteAccountWarning)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(LocalizedKey.data.rawValue.localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert(LocalizedKey.exportSuccess.rawValue.localized, isPresented: $showExportSuccess) {
            Button(LocalizedKey.ok.rawValue.localized, role: .cancel) { }
        } message: {
            Text(LocalizedKey.dataExported)
        }
        .alert(LocalizedKey.importSuccess.rawValue.localized, isPresented: $showImportSuccess) {
            Button(LocalizedKey.ok.rawValue.localized, role: .cancel) { }
        } message: {
            Text(LocalizedKey.dataImported)
        }
        .alert(LocalizedKey.importFailed.rawValue.localized, isPresented: $showImportError) {
            Button(LocalizedKey.ok.rawValue.localized, role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(
                allowedContentTypes: [.json],
                onDocumentPicked: { url in
                    importData(from: url)
                }
            )
        }
        .sheet(isPresented: $showActivitySheet) {
            if let fileURL = exportFileURL {
                ActivityViewController(
                    activityItems: [fileURL],
                    onComplete: { activityType, completed, error in
                        isExporting = false
                        showActivitySheet = false
                        exportFileURL = nil
                        if completed {
                            showExportSuccess = true
                        }
                    }
                )
            }
        }
    }
    
    private func exportLocalData() {
        isExporting = true
        
        Task {
            do {
                let exportData = ExportData(
                    words: words.map { word in
                        ExportWord(
                            id: word.id.uuidString,
                            term: word.term,
                            definition: word.definition,
                            partOfSpeech: word.partOfSpeech,
                            pronunciation: word.pronunciation,
                            example: word.example,
                            exampleCn: word.exampleCn,
                            learned: word.learned,
                            reviewCount: word.reviewCount,
                            lastReviewed: word.lastReviewed?.timeIntervalSince1970,
                            createdAt: word.createdAt.timeIntervalSince1970,
                            sheetId: word.sheet?.id.uuidString
                        )
                    },
                    sheets: sheets.map { sheet in
                        ExportSheet(
                            id: sheet.id.uuidString,
                            name: sheet.name,
                            createdAt: sheet.createdAt.timeIntervalSince1970
                        )
                    }
                )
                
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                
                let jsonData = try encoder.encode(exportData)
                
                // 保存到临时文件
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("vocab_export_\(Date().timeIntervalSince1970).json")
                
                try jsonData.write(to: tempURL)
                
                await MainActor.run {
                    // 保存文件 URL，显示分享菜单
                    exportFileURL = tempURL
                    isExporting = false
                    showActivitySheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    errorMessage = String(format: "导出失败: %@", error.localizedDescription)
                    showImportError = true
                }
            }
        }
    }
    
    private func importLocalData() {
        showDocumentPicker = true
    }
    
    private func importData(from url: URL) {
        isImporting = true
        
        Task {
            do {
                // 读取文件内容
                let jsonData = try Data(contentsOf: url)
                
                // 解析 JSON
                let decoder = JSONDecoder()
                let exportData = try decoder.decode(ExportData.self, from: jsonData)
                
                // 在主线程上执行数据导入
                await MainActor.run {
                    do {
                        // 创建 sheet ID 映射（用于关联 words 和 sheets）
                        var sheetMap: [String: WordSheet] = [:]
                        
                        // 先导入所有 sheets
                        for exportSheet in exportData.sheets {
                            // 检查是否已存在相同 ID 的 sheet
                            let existingSheet = sheets.first { $0.id.uuidString == exportSheet.id }
                            
                            if let existing = existingSheet {
                                // 如果已存在，更新名称（保留现有 sheet）
                                existing.name = exportSheet.name
                                sheetMap[exportSheet.id] = existing
                            } else {
                                // 创建新的 sheet
                                let sheet = WordSheet(
                                    id: UUID(uuidString: exportSheet.id) ?? UUID(),
                                    name: exportSheet.name,
                                    createdAt: Date(timeIntervalSince1970: exportSheet.createdAt)
                                )
                                modelContext.insert(sheet)
                                sheetMap[exportSheet.id] = sheet
                            }
                        }
                        
                        // 导入所有 words
                        for exportWord in exportData.words {
                            // 检查是否已存在相同 ID 的 word
                            let existingWord = words.first { $0.id.uuidString == exportWord.id }
                            
                            if existingWord == nil {
                                // 只导入不存在的 word（避免重复）
                                let word = Word(
                                    id: UUID(uuidString: exportWord.id) ?? UUID(),
                                    term: exportWord.term,
                                    definition: exportWord.definition,
                                    partOfSpeech: exportWord.partOfSpeech,
                                    pronunciation: exportWord.pronunciation,
                                    example: exportWord.example,
                                    exampleCn: exportWord.exampleCn,
                                    learned: exportWord.learned,
                                    reviewCount: exportWord.reviewCount,
                                    lastReviewed: exportWord.lastReviewed != nil ? Date(timeIntervalSince1970: exportWord.lastReviewed!) : nil,
                                    createdAt: Date(timeIntervalSince1970: exportWord.createdAt),
                                    sheet: exportWord.sheetId != nil ? sheetMap[exportWord.sheetId!] : nil
                                )
                                modelContext.insert(word)
                            }
                        }
                        
                        // 保存上下文
                        try modelContext.save()
                        
                        isImporting = false
                        showImportSuccess = true
                    } catch {
                        isImporting = false
                        errorMessage = String(format: "导入数据失败: %@", error.localizedDescription)
                        showImportError = true
                    }
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    errorMessage = String(format: "读取文件失败: %@", error.localizedDescription)
                    showImportError = true
                }
            }
        }
    }
}

// 导出数据结构
struct ExportData: Codable {
    let words: [ExportWord]
    let sheets: [ExportSheet]
}

struct ExportWord: Codable {
    let id: String
    let term: String
    let definition: String
    let partOfSpeech: String
    let pronunciation: String
    let example: String
    let exampleCn: String
    let learned: Bool
    let reviewCount: Int
    let lastReviewed: Double?
    let createdAt: Double
    let sheetId: String?
}

struct ExportSheet: Codable {
    let id: String
    let name: String
    let createdAt: Double
}

// 文件分享视图控制器封装（用于导出）
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let onComplete: (UIActivity.ActivityType?, Bool, Error?) -> Void
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityVC = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        
        // 设置完成回调
        activityVC.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            onComplete(activityType, completed, error)
        }
        
        return activityVC
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // 不需要更新
    }
}

// 文件选择器封装（用于导入）
struct DocumentPicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onDocumentPicked: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentPicked: onDocumentPicked)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentPicked: (URL) -> Void
        
        init(onDocumentPicked: @escaping (URL) -> Void) {
            self.onDocumentPicked = onDocumentPicked
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // 确保可以访问文件
            guard url.startAccessingSecurityScopedResource() else {
                print("无法访问文件")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            onDocumentPicked(url)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // 用户取消了选择
        }
    }
}

