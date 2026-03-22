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
    @State private var showMergeResult = false
    @State private var mergeResultMessage = ""
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showDocumentPicker = false
    @State private var showActivitySheet = false
    @State private var exportFileURL: URL?
    @State private var showSheetSelection = false
    @State private var selectedSheetIdsForCSV: Set<UUID> = []
    
    var body: some View {
        Form {
            // 本地数据部分
            Section {
                Button(action: {
                    importLocalData()
                }) {
                    Label(LocalizedKey.importCSVFile.rawValue.localized, systemImage: "square.and.arrow.down")
                }
                .disabled(isImporting)
                
                Button(action: {
                    showSheetSelection = true
                }) {
                    Label(LocalizedKey.exportCSVFile.rawValue.localized, systemImage: "doc.text")
                }
                .disabled(isExporting)
                
                // 一次性维护：合并/清理重复日期词库
                Button(action: {
                    mergeDuplicateDateSheets()
                }) {
                    Label("合并重复日期词库", systemImage: "square.stack.3d.up.fill")
                }
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
        .navigationTitle(LocalizedKey.vocabularyData.rawValue.localized)
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
        .alert("合并完成", isPresented: $showMergeResult) {
            Button("好", role: .cancel) { }
        } message: {
            Text(mergeResultMessage)
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(
                allowedContentTypes: [.commaSeparatedText],
                onDocumentPicked: { data in
                    importData(from: data)
                },
                onError: { message in
                    errorMessage = message
                    showImportError = true
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
        .sheet(isPresented: $showSheetSelection) {
            SheetSelectionView { selectedIds in
                selectedSheetIdsForCSV = selectedIds
                if !selectedIds.isEmpty {
                    exportCSV(selectedSheetIds: selectedIds)
                } else {
                    errorMessage = LocalizedKey.noSheetsSelected.rawValue.localized
                    showImportError = true
                }
            }
        }
    }
    
    private func exportLocalData() {
        // 导出所有数据为CSV
        exportCSV(wordsToExport: words)
    }
    
    private func importLocalData() {
        showDocumentPicker = true
    }
    
    private func exportCSV(wordsToExport: [Word]? = nil, selectedSheetIds: Set<UUID>? = nil) {
        isExporting = true
        
        Task {
            do {
                // 确定要导出的单词列表
                let wordsToExportFinal: [Word]
                if let selectedSheetIds = selectedSheetIds {
                    // 如果指定了选中的sheet，则过滤
                    wordsToExportFinal = self.words.filter { word in
                        if let sheetId = word.sheet?.id {
                            return selectedSheetIds.contains(sheetId)
                        }
                        return false
                    }
                } else if let wordsToExportParam = wordsToExport {
                    // 如果直接传入了单词列表，使用它
                    wordsToExportFinal = wordsToExportParam
                } else {
                    // 否则导出所有单词
                    wordsToExportFinal = self.words
                }
                
                // 如果没有单词，显示错误
                guard !wordsToExportFinal.isEmpty else {
                    await MainActor.run {
                        isExporting = false
                        errorMessage = LocalizedKey.noWordsInSelectedSheets.rawValue.localized
                        showImportError = true
                    }
                    return
                }
                
                // 日期格式化器
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                dateFormatter.timeStyle = .none
                
                // 创建CSV内容（在末尾追加新字段以兼容旧版本）
                var csvContent = "单词,词性,释义,音标,例句,例句翻译,已掌握,复习次数,最后复习时间,创建时间,词库,词根,近义词,反义词,推荐复习次数,推荐复习上次时间\n"
                
                for word in wordsToExportFinal.sorted(by: { $0.createdAt > $1.createdAt }) {
                    let term = escapeCSVField(word.term)
                    let partOfSpeech = escapeCSVField(word.partOfSpeech)
                    let definition = escapeCSVField(word.definition)
                    let pronunciation = escapeCSVField(word.pronunciation)
                    let example = escapeCSVField(word.example)
                    let exampleCn = escapeCSVField(word.exampleCn)
                    let learned = word.learned ? "是" : "否"
                    let reviewCount = String(word.reviewCount)
                    let lastReviewed = word.lastReviewed != nil ? dateFormatter.string(from: word.lastReviewed!) : ""
                    let spacedReviewCount = String(word.spacedReviewCount)
                    let spacedLastReviewed = word.spacedLastReviewed != nil ? dateFormatter.string(from: word.spacedLastReviewed!) : ""
                    let createdAt = dateFormatter.string(from: word.createdAt)
                    let sheetName = escapeCSVField(word.sheet?.localizedDisplayName ?? "")
                    let root = escapeCSVField(word.root)
                    let synonyms = escapeCSVField(word.synonyms)
                    let antonyms = escapeCSVField(word.antonyms)
                    
                    csvContent += "\(term),\(partOfSpeech),\(definition),\(pronunciation),\(example),\(exampleCn),\(learned),\(reviewCount),\(lastReviewed),\(createdAt),\(sheetName),\(root),\(synonyms),\(antonyms),\(spacedReviewCount),\(spacedLastReviewed)\n"
                }
                
                // 转换为UTF-8编码的Data（包含BOM以支持Excel正确显示中文）
                let bom = "\u{FEFF}"
                let csvData = (bom + csvContent).data(using: .utf8)!
                
                // 保存到临时文件
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("vocab_export_\(Date().timeIntervalSince1970).csv")
                
                try csvData.write(to: tempURL)
                
                await MainActor.run {
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
    
    
    private func escapeCSVField(_ field: String) -> String {
        // 如果字段包含逗号、引号或换行符，需要用引号包裹，并转义引号
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
    
    private func importData(from data: Data) {
        isImporting = true
        
        Task {
            do {
                // 从 Data 得到 CSV 字符串（避免在异步阶段访问安全作用域 URL）
                var csvContent: String
                if let content = String(data: data, encoding: .utf8) {
                    csvContent = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
                } else {
                    throw NSError(domain: "CSVImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取CSV文件（请使用 UTF-8 编码）"])
                }
                
                // 解析CSV
                let rows = parseCSV(csvContent)
                
                guard rows.count > 1 else {
                    throw NSError(domain: "CSVImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "CSV文件为空或格式不正确"])
                }
                
                // 获取表头
                let headers = rows[0]
                guard headers.count >= 3 else {
                    throw NSError(domain: "CSVImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "CSV文件格式不正确，至少需要包含单词、词性、释义列"])
                }
                
                // 在主线程上执行数据导入
                await MainActor.run {
                    do {
                        // 创建sheet名称到sheet对象的映射（使用规范化KEY，避免因语言切换造成重复）
                        var sheetMap: [String: WordSheet] = [:]
                        
                        // 日期解析器
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateStyle = .short
                        dateFormatter.timeStyle = .none
                        
                        // 导入所有数据行
                        for i in 1..<rows.count {
                            let row = rows[i]
                            guard row.count >= 3 else { continue } // 跳过不完整的行
                            
                            // 解析CSV行数据（根据表头顺序）
                            let term = row.count > 0 ? row[0] : ""
                            let partOfSpeech = row.count > 1 ? row[1] : ""
                            let definition = row.count > 2 ? row[2] : ""
                            let pronunciation = row.count > 3 ? row[3] : ""
                            let example = row.count > 4 ? row[4] : ""
                            let exampleCn = row.count > 5 ? row[5] : ""
                            let learnedStr = row.count > 6 ? row[6] : "否"
                            let reviewCountStr = row.count > 7 ? row[7] : "0"
                            let lastReviewedStr = row.count > 8 ? row[8] : ""
                            let createdAtStr = row.count > 9 ? row[9] : ""
                            let sheetName = row.count > 10 ? row[10] : ""
                            // 新增字段：词根 / 近义词 / 反义词（老版本CSV可能没有这些列，保持兼容）
                            let root = row.count > 11 ? row[11] : ""
                            let synonyms = row.count > 12 ? row[12] : ""
                            let antonyms = row.count > 13 ? row[13] : ""
                            let spacedReviewCountStr = row.count > 14 ? row[14] : "0"
                            let spacedLastReviewedStr = row.count > 15 ? row[15] : ""
                            
                            // 跳过空行
                            if term.isEmpty { continue }
                            
                            // 解析布尔值
                            let learned = learnedStr == "是" || learnedStr.lowercased() == "yes" || learnedStr == "true"
                            
                            // 解析数字
                            let reviewCount = Int(reviewCountStr) ?? 0
                            
                            // 解析日期
                            var lastReviewed: Date? = nil
                            if !lastReviewedStr.isEmpty {
                                lastReviewed = dateFormatter.date(from: lastReviewedStr)
                            }
                            
                            let spacedReviewCount = Int(spacedReviewCountStr) ?? 0
                            var spacedLastReviewed: Date? = nil
                            if !spacedLastReviewedStr.isEmpty {
                                spacedLastReviewed = dateFormatter.date(from: spacedLastReviewedStr)
                            }
                            
                            var createdAt = Date()
                            if !createdAtStr.isEmpty {
                                createdAt = dateFormatter.date(from: createdAtStr) ?? Date()
                            }
                            
                            // 处理sheet
                            var sheet: WordSheet? = nil
                            if !sheetName.isEmpty {
                                // 使用规范化KEY（日期 -> yyyy-MM-dd，普通名称保持原样）
                                let sheetKey = canonicalSheetKey(forName: sheetName)
                                
                                if let existingSheet = sheetMap[sheetKey] {
                                    sheet = existingSheet
                                } else {
                                    // 查找是否已存在相同日期/名称的sheet
                                    if let existing = sheets.first(where: { canonicalSheetKey(forName: $0.name) == sheetKey }) {
                                        sheet = existing
                                        sheetMap[sheetKey] = existing
                                    } else {
                                        // 创建新的sheet
                                        let newSheet = WordSheet(name: sheetName, createdAt: createdAt)
                                        modelContext.insert(newSheet)
                                        sheetMap[sheetKey] = newSheet
                                        sheet = newSheet
                                    }
                                }
                            }
                            
                            // 检查是否已存在相同的单词（避免重复导入）
                            let existingWord = words.first { $0.term == term && $0.sheet?.id == sheet?.id }
                            
                            if existingWord == nil {
                                // 创建新的word
                                let word = Word(
                                    term: term,
                                    definition: definition,
                                    partOfSpeech: partOfSpeech,
                                    pronunciation: pronunciation,
                                    example: example,
                                    exampleCn: exampleCn,
                                    root: root,
                                    synonyms: synonyms,
                                    antonyms: antonyms,
                                    learned: learned,
                                    reviewCount: reviewCount,
                                    lastReviewed: lastReviewed,
                                    spacedReviewCount: spacedReviewCount,
                                    spacedLastReviewed: spacedLastReviewed,
                                    createdAt: createdAt,
                                    sheet: sheet
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
    
    // 解析CSV内容
    private func parseCSV(_ content: String) -> [[String]] {
        var result: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        var i = content.startIndex
        
        while i < content.endIndex {
            let char = content[i]
            
            if char == "\"" {
                if insideQuotes && i < content.index(before: content.endIndex) && content[content.index(after: i)] == "\"" {
                    // 转义的引号
                    currentField += "\""
                    i = content.index(after: content.index(after: i))
                    continue
                } else {
                    // 切换引号状态
                    insideQuotes.toggle()
                }
            } else if char == "," && !insideQuotes {
                // 字段分隔符
                currentRow.append(currentField)
                currentField = ""
            } else if (char == "\n" || char == "\r") && !insideQuotes {
                // 行分隔符
                if char == "\r" && i < content.index(before: content.endIndex) && content[content.index(after: i)] == "\n" {
                    // 跳过\r\n
                    i = content.index(after: i)
                }
                currentRow.append(currentField)
                if !currentRow.isEmpty {
                    result.append(currentRow)
                }
                currentRow = []
                currentField = ""
            } else {
                currentField.append(char)
            }
            
            i = content.index(after: i)
        }
        
        // 添加最后一行
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.isEmpty {
                result.append(currentRow)
            }
        }
        
        return result
    }
    
    // MARK: - Sheet 名称规范化工具
    /// 将词库名称转换为规范化KEY：
    /// - 如果是日期（中/英格式），统一为 "yyyy-MM-dd"
    /// - 否则直接返回原始名称
    private func canonicalSheetKey(forName name: String) -> String {
        // 与 LocalizedString.localizedDisplayName 保持一致的日期解析规则
        let chineseFormatter = DateFormatter()
        chineseFormatter.locale = Locale(identifier: "zh_Hans")
        chineseFormatter.dateFormat = "yyyy年M月d日"
        
        let englishFormatter = DateFormatter()
        englishFormatter.locale = Locale(identifier: "en_US")
        englishFormatter.dateFormat = "MMMM d, yyyy"
        
        if let date = chineseFormatter.date(from: name) ?? englishFormatter.date(from: name) {
            let normalized = DateFormatter()
            normalized.calendar = Calendar(identifier: .gregorian)
            normalized.locale = Locale(identifier: "en_US_POSIX")
            normalized.dateFormat = "yyyy-MM-dd"
            return normalized.string(from: date)
        }
        return name
    }
    
    // MARK: - 合并重复日期词库（一次性维护工具）
    /// 查找名称解析为同一日期的多个词库，将其合并到一个主词库中，避免下拉列表中日期重复
    private func mergeDuplicateDateSheets() {
        // 按规范化KEY分组
        var groups: [String: [WordSheet]] = [:]
        for sheet in sheets {
            let key = canonicalSheetKey(forName: sheet.name)
            groups[key, default: []].append(sheet)
        }
        
        var mergedGroupCount = 0
        var movedWordCount = 0
        
        for (_, groupSheets) in groups {
            guard groupSheets.count > 1 else { continue }
            
            // 选择一个主词库：按创建时间最早者
            let sorted = groupSheets.sorted { $0.createdAt < $1.createdAt }
            guard let primary = sorted.first else { continue }
            let duplicates = sorted.dropFirst()
            
            for duplicate in duplicates {
                if let dupWords = duplicate.words {
                    for word in dupWords {
                        // 迁移单词到主词库
                        word.sheet = primary
                        movedWordCount += 1
                    }
                }
                // 删除多余的词库分组
                modelContext.delete(duplicate)
                mergedGroupCount += 1
            }
        }
        
        do {
            if mergedGroupCount > 0 {
                try modelContext.save()
                mergeResultMessage = "已合并 \(mergedGroupCount) 个重复日期词库，移动 \(movedWordCount) 个单词。"
            } else {
                mergeResultMessage = "未发现需要合并的重复日期词库。"
            }
        } catch {
            mergeResultMessage = "合并过程中保存失败：\(error.localizedDescription)"
        }
        
        showMergeResult = true
    }
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
    let onDocumentPicked: (Data) -> Void
    let onError: (String) -> Void
    
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
        Coordinator(onDocumentPicked: onDocumentPicked, onError: onError)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentPicked: (Data) -> Void
        let onError: (String) -> Void
        
        init(onDocumentPicked: @escaping (Data) -> Void, onError: @escaping (String) -> Void) {
            self.onDocumentPicked = onDocumentPicked
            self.onError = onError
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // 在 delegate 回调内同步读取文件，避免安全作用域在异步阶段失效（尤其 iCloud 选中的文件）
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            
            guard let data = try? Data(contentsOf: url) else {
                onError("无法读取所选文件，请确认文件存在且未被占用。")
                return
            }
            onDocumentPicked(data)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // 用户取消了选择
        }
    }
}

