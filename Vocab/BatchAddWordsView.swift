//
//  BatchAddWordsView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

struct BatchAddWordsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localizedString = LocalizedString.shared
    
    @Query(sort: \WordSheet.createdAt, order: .reverse) private var allSheets: [WordSheet]
    @Query private var words: [Word]
    
    let recognizedWords: [String]
    @State private var selectedWords: Set<String> = []
    @State private var selectedSheetId: UUID?
    @State private var isProcessing: Bool = false
    @State private var processedCount: Int = 0
    @State private var skippedCount: Int = 0
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showSkipAlert: Bool = false
    @State private var showPaywall: Bool = false
    @State private var showCreateSheet = false
    
    private var sortedSheets: [WordSheet] {
        WordSheetService.sortedSheets(allSheets)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Sheet 选择
                Section {
                    Picker(LocalizedKey.wordSheet.rawValue.localized, selection: $selectedSheetId) {
                        if WordSheetService.findTodaySheet(in: allSheets) == nil {
                            Text(DateFormatter.localizedDateString(from: Date()))
                                .tag(nil as UUID?)
                        }
                        ForEach(sortedSheets) { sheet in
                            Text(sheet.localizedDisplayName).tag(sheet.id as UUID?)
                        }
                    }
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label(LocalizedKey.newSheet.rawValue.localized, systemImage: "folder.badge.plus")
                    }
                } header: {
                    Text(LocalizedKey.wordSheet)
                } footer: {
                    Text(LocalizedKey.wordSheetDescription)
                }
                
                // 识别到的单词列表
                Section {
                    if recognizedWords.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "text.badge.xmark")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.tertiary)
                                Text(LocalizedKey.noWordsRecognized)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 32)
                    } else {
                        ForEach(recognizedWords, id: \.self) { word in
                            HStack {
                                Button(action: {
                                    if selectedWords.contains(word) {
                                        selectedWords.remove(word)
                                    } else {
                                        selectedWords.insert(word)
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        if selectedWords.contains(word) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.tint)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Text(word)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(LocalizedKey.recognizedWords)
                        Spacer()
                        if !recognizedWords.isEmpty {
                            Button(selectedWords.count == recognizedWords.count ? LocalizedKey.deselectAll.rawValue.localized : LocalizedKey.selectAll.rawValue.localized) {
                                if selectedWords.count == recognizedWords.count {
                                    selectedWords.removeAll()
                                } else {
                                    selectedWords = Set(recognizedWords)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.tint)
                        }
                    }
                } footer: {
                    if !recognizedWords.isEmpty {
                        Text(String(format: LocalizedKey.selectedCount.rawValue.localized, selectedWords.count, recognizedWords.count))
                    }
                }
                
                // 批量添加按钮
                if !recognizedWords.isEmpty {
                    Section {
                        Button(action: handleBatchAdd) {
                            HStack {
                                Spacer()
                                if isProcessing {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text(String(format: LocalizedKey.adding.rawValue.localized, processedCount, selectedWords.count))
                                    }
                                } else {
                                    Text(String(format: LocalizedKey.batchAdd.rawValue.localized, selectedWords.count))
                                        .fontWeight(.semibold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(selectedWords.isEmpty || isProcessing)
                        .accessibilityLabel(LocalizedKey.batchAddWords.rawValue.localized)
                    }
                }
            }
            .navigationTitle(LocalizedKey.batchAddWords.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(LocalizedKey.cancel.rawValue.localized) {
                        dismiss()
                    }
                }
            }
            .alert(LocalizedKey.addFailed.rawValue.localized, isPresented: $showError) {
                Button(LocalizedKey.ok.rawValue.localized, role: .cancel) { }
            } message: {
                Text(errorMessage ?? LocalizedKey.unknownError.rawValue.localized)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showCreateSheet) {
                WordSheetEditorView(sheet: nil) { created in
                    selectedSheetId = created.id
                }
            }
            .alert(LocalizedKey.batchAddCompleted.rawValue.localized, isPresented: $showSkipAlert) {
                Button(LocalizedKey.ok.rawValue.localized, role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(String(format: LocalizedKey.batchAddCompletedMessage.rawValue.localized, processedCount - skippedCount, skippedCount))
            }
            .onAppear {
                selectedWords = Set(recognizedWords)
                if selectedSheetId == nil {
                    selectedSheetId = WordSheetService.findTodaySheet(in: allSheets)?.id
                }
            }
        }
    }
    
    private func getOrCreateTodaySheet() -> WordSheet {
        WordSheetService.findOrCreateTodaySheet(in: allSheets, context: modelContext)
    }
    
    private var selectedSheet: WordSheet? {
        guard let id = selectedSheetId else { return nil }
        return allSheets.first { $0.id == id }
    }
    
    private func handleBatchAdd() {
        guard !selectedWords.isEmpty else { return }
        
        isProcessing = true
        processedCount = 0
        skippedCount = 0
        
        // 如果未选择 sheet，使用今天的 sheet
        let sheet = selectedSheet ?? getOrCreateTodaySheet()
        
        Task {
            let wordsToAdd = Array(selectedWords)
            
            for word in wordsToAdd {
                await MainActor.run {
                    processedCount += 1
                }
                
                // 检查是否重复
                let normalizedTerm = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let isDuplicate = words.contains { existingWord in
                    existingWord.sheet?.id == sheet.id &&
                    existingWord.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTerm
                }
                
                if isDuplicate {
                    // 跳过重复的单词
                    await MainActor.run {
                        skippedCount += 1
                    }
                    continue
                }
                
                do {
                    // 尝试获取单词详情
                    let details = try await DeepseekService.shared.generateWordDetails(for: word)
                    
                    await MainActor.run {
                        let newWord = Word(
                            term: word,
                            definition: details.definition,
                            partOfSpeech: details.partOfSpeech,
                            pronunciation: details.pronunciation,
                            example: details.example,
                            exampleCn: details.exampleCn,
                            sheet: sheet
                        )
                        
                        modelContext.insert(newWord)
                        WordSheetService.noteInserted(newWord)
                    }
                } catch {
                    // 检查是否是次数不足的错误
                    if let serviceError = error as? DeepseekServiceError,
                       case .noRemainingCalls = serviceError {
                        await MainActor.run {
                            showPaywall = true
                            isProcessing = false
                        }
                        return // 停止批量添加
                    } else {
                        // 如果AI填充失败，使用空值创建单词
                        await MainActor.run {
                            let newWord = Word(
                                term: word,
                                definition: "",
                                partOfSpeech: "",
                                pronunciation: "",
                                example: "",
                                exampleCn: "",
                                sheet: sheet
                            )
                            
                            modelContext.insert(newWord)
                            WordSheetService.noteInserted(newWord)
                        }
                    }
                }
                
                // 短暂延迟，避免API请求过快
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            }
            
            await MainActor.run {
                do {
                    try modelContext.save()
                    isProcessing = false
                    
                    // 如果有跳过的单词，显示提示
                    if skippedCount > 0 {
                        showSkipAlert = true
                    } else {
                        dismiss()
                    }
                } catch {
                    isProcessing = false
                    errorMessage = String(format: "保存失败: %@", error.localizedDescription)
                    showError = true
                }
            }
        }
    }
}
