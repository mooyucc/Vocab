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
    
    @Query(sort: \WordSheet.createdAt, order: .reverse) private var allSheets: [WordSheet]
    
    let recognizedWords: [String]
    @State private var selectedWords: Set<String> = []
    @State private var selectedSheetId: UUID?
    @State private var isProcessing: Bool = false
    @State private var processedCount: Int = 0
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Sheet 选择
                Section {
                    Picker(LocalizedKey.wordSheet.rawValue.localized, selection: $selectedSheetId) {
                        ForEach(allSheets) { sheet in
                            Text(sheet.localizedDisplayName).tag(sheet.id as UUID?)
                        }
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
            .onAppear {
                // 默认选择所有单词
                selectedWords = Set(recognizedWords)
                
                // 设置默认sheet
                if selectedSheetId == nil {
                    let todaySheet = getOrCreateTodaySheet()
                    selectedSheetId = todaySheet.id
                }
            }
        }
    }
    
    private func getOrCreateTodaySheet() -> WordSheet {
        let formatter = DateFormatter()
        // 根据语言设置日期格式和 locale
        let language = AppSettingsManager.shared.language
        if language == .chinese {
            formatter.locale = Locale(identifier: "zh_Hans")
            formatter.dateFormat = "yyyy年M月d日"
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = "MMMM d, yyyy"
        }
        let todayName = formatter.string(from: Date())
        
        // 查找今天是否已有 sheet
        if let existingSheet = allSheets.first(where: { $0.name == todayName }) {
            return existingSheet
        }
        
        // 创建新的 sheet
        let newSheet = WordSheet(name: todayName)
        modelContext.insert(newSheet)
        try? modelContext.save()
        return newSheet
    }
    
    private var selectedSheet: WordSheet? {
        guard let id = selectedSheetId else { return nil }
        return allSheets.first { $0.id == id }
    }
    
    private func handleBatchAdd() {
        guard !selectedWords.isEmpty else { return }
        
        isProcessing = true
        processedCount = 0
        
        // 如果未选择 sheet，使用今天的 sheet
        let sheet = selectedSheet ?? getOrCreateTodaySheet()
        
        Task {
            let wordsToAdd = Array(selectedWords)
            
            for word in wordsToAdd {
                await MainActor.run {
                    processedCount += 1
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
                    }
                } catch {
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
                    }
                }
                
                // 短暂延迟，避免API请求过快
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2秒
            }
            
            await MainActor.run {
                do {
                    try modelContext.save()
                    isProcessing = false
                    dismiss()
                } catch {
                    isProcessing = false
                    errorMessage = String(format: "保存失败: %@", error.localizedDescription)
                    showError = true
                }
            }
        }
    }
}
