//
//  AddWordView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

struct AddWordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \WordSheet.createdAt, order: .reverse) private var allSheets: [WordSheet]
    @Query private var words: [Word]
    
    @State private var term: String = ""
    @State private var definition: String = ""
    @State private var partOfSpeech: String = ""
    @State private var pronunciation: String = ""
    @State private var example: String = ""
    @State private var exampleCn: String = ""
    @State private var root: String = ""
    @State private var synonyms: String = ""
    @State private var antonyms: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var selectedSheetId: UUID?
    @State private var selectedImage: UIImage?
    @State private var isRecognizing: Bool = false
    @State private var showBatchAddView: Bool = false
    @State private var recognizedWords: [String] = []
    @State private var showCameraPicker: Bool = false
    @State private var showImageCropView: Bool = false
    @State private var imageToCrop: UIImage?
    @State private var showDuplicateAlert: Bool = false
    @State private var pendingWordData: (term: String, definition: String, partOfSpeech: String, pronunciation: String, example: String, exampleCn: String, root: String, synonyms: String, antonyms: String)?
    @State private var showPaywall: Bool = false
    
    // MARK: - 示例占位内容（根据学习语言 & 母语适配）
    private var sampleWordPlaceholder: String {
        switch AppSettingsManager.shared.targetLanguage {
        case .chinese:
            return "苹果"
        case .chineseTraditional:
            return "蘋果"
        case .english:
            return "Apple"
        case .japanese:
            return "りんご"
        case .french:
            return "pomme"
        case .spanish:
            return "manzana"
        case .korean:
            return "사과"
        }
    }
    
    private var sampleDefinitionPlaceholder: String {
        // 释义使用用户母语（界面语言）
        switch AppSettingsManager.shared.language {
        case .chinese:
            return "苹果"
        case .chineseTraditional:
            return "蘋果"
        case .english:
            return "Apple (a kind of fruit)"
        case .japanese:
            return "りんご（果物の一種）"
        case .french:
            return "Pomme (un type de fruit)"
        case .spanish:
            return "Manzana (un tipo de fruta)"
        case .korean:
            return "사과(과일의 한 종류)"
        }
    }
    
    private var sampleExamplePlaceholder: String {
        // 例句使用学习语言
        switch AppSettingsManager.shared.targetLanguage {
        case .chinese:
            return "每天吃一个苹果有益健康。"
        case .chineseTraditional:
            return "每天吃一個蘋果有益健康。"
        case .english:
            return "An apple a day keeps the doctor away."
        case .japanese:
            return "毎日りんごを一つ食べると健康に良いです。"
        case .french:
            return "Une pomme par jour garde le docteur loin."
        case .spanish:
            return "Una manzana al día mantiene al médico lejos."
        case .korean:
            return "하루에 사과 한 개는 건강에 좋습니다."
        }
    }
    
    private var sampleExampleTranslationPlaceholder: String {
        // 例句翻译使用用户母语
        switch AppSettingsManager.shared.language {
        case .chinese:
            return "一天一苹果，医生远离我。"
        case .chineseTraditional:
            return "一天一顆蘋果，醫生遠離我。"
        case .english:
            return "Eat an apple every day and you will stay healthy."
        case .japanese:
            return "毎日りんごを一つ食べると健康を保てるという意味です。"
        case .french:
            return "Manger une pomme par jour aide à rester en bonne santé."
        case .spanish:
            return "Comer una manzana al día ayuda a mantenerse sano."
        case .korean:
            return "하루에 사과 한 개를 먹으면 건강을 지킬 수 있다는 뜻입니다."
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 单词输入
                Section {
                    HStack(spacing: 12) {
                        TextField(sampleWordPlaceholder, text: $term)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Button(action: handleAutoFill) {
                            HStack(spacing: 4) {
                                if isLoading {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(LocalizedKey.aiFill)
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isLoading || term.isEmpty || isRecognizing)
                        .accessibilityLabel("\(LocalizedKey.aiFill.rawValue.localized) \(LocalizedKey.word.rawValue.localized)")
                    }
                } header: {
                    Text(LocalizedKey.word)
                }
            
                
                // 定义
                Section {
                    TextField(sampleDefinitionPlaceholder, text: $definition)
                } header: {
                    Text(LocalizedKey.definition)
                }
                
                // 词性和音标
                Section {
                    HStack(spacing: 16) {
                        TextField("n.", text: $partOfSpeech)
                        TextField("/.../", text: $pronunciation)
                            .fontDesign(.serif)
                    }
                } header: {
                    Text(LocalizedKey.partOfSpeech)
                }
                
                // 词根
                Section {
                    TextField(LocalizedKey.rootPlaceholder.rawValue.localized, text: $root, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text(LocalizedKey.root)
                }
                
                // 近义词 / 反义词
                Section {
                    TextField(LocalizedKey.synonymsPlaceholder.rawValue.localized, text: $synonyms, axis: .vertical)
                        .lineLimit(1...3)
                    TextField(LocalizedKey.antonymsPlaceholder.rawValue.localized, text: $antonyms, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text(LocalizedKey.synonymsAntonyms)
                }
                
                // 例句
                Section {
                    TextField(sampleExamplePlaceholder, text: $example, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(LocalizedKey.example)
                }
                
                // 翻译
                Section {
                    TextField(sampleExampleTranslationPlaceholder, text: $exampleCn, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text(LocalizedKey.translation)
                }
                
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
                
                // 保存按钮
                Section {
                    Button(action: handleSubmit) {
                        HStack {
                            Spacer()
                            Text(LocalizedKey.saveWord)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(term.isEmpty || definition.isEmpty)
                    .accessibilityLabel(LocalizedKey.saveWord.rawValue.localized)
                }
            }
            .navigationTitle(LocalizedKey.addNewWordTitle.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showCameraPicker = true
                    }) {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(.tint)
                    }
                    .disabled(isLoading || isRecognizing)
                    .accessibilityLabel(LocalizedKey.cameraRecognize.rawValue.localized)
                }
            }
            .alert(LocalizedKey.aiGenerateFailed.rawValue.localized, isPresented: $showError) {
                Button(LocalizedKey.ok.rawValue.localized, role: .cancel) { }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
            .alert(LocalizedKey.duplicateWordTitle.rawValue.localized, isPresented: $showDuplicateAlert) {
                Button(LocalizedKey.skip.rawValue.localized, role: .cancel) {
                    pendingWordData = nil
                }
                Button(LocalizedKey.addAnyway.rawValue.localized) {
                    if let data = pendingWordData {
                        saveWord(
                            term: data.term,
                            definition: data.definition,
                            partOfSpeech: data.partOfSpeech,
                            pronunciation: data.pronunciation,
                            example: data.example,
                            exampleCn: data.exampleCn,
                            root: data.root,
                            synonyms: data.synonyms,
                            antonyms: data.antonyms
                        )
                        pendingWordData = nil
                    }
                }
            } message: {
                if let data = pendingWordData {
                    Text(String(format: LocalizedKey.duplicateWordMessage.rawValue.localized, data.term))
                }
            }
            .onAppear {
                if selectedSheetId == nil {
                    let todaySheet = getOrCreateTodaySheet()
                    selectedSheetId = todaySheet.id
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showBatchAddView) {
                BatchAddWordsView(recognizedWords: recognizedWords)
            }
            .fullScreenCover(isPresented: $showCameraPicker) {
                CustomCameraView(selectedImage: $selectedImage, isPresented: $showCameraPicker)
                    .ignoresSafeArea(.all)
            }
            .fullScreenCover(isPresented: $showImageCropView) {
                if let image = imageToCrop {
                    ImageCropView(
                        image: image,
                        isPresented: $showImageCropView,
                        onCropSelected: { croppedImage in
                            Task {
                                await handleImageSelected(croppedImage)
                            }
                        }
                    )
                    .ignoresSafeArea(.all)
                }
            }
            .onChange(of: selectedImage) { oldValue, newValue in
                if let image = newValue {
                    // 显示区域选择视图而不是直接识别
                    imageToCrop = image
                    showImageCropView = true
                    selectedImage = nil // 重置，避免重复触发
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
    
    private func handleAutoFill() {
        guard !term.isEmpty else { return }
        
        isLoading = true
        
        Task {
            do {
                let details = try await DeepseekService.shared.generateWordDetails(for: term)
                await MainActor.run {
                    definition = details.definition
                    partOfSpeech = details.partOfSpeech
                    pronunciation = details.pronunciation
                    example = details.example
                    exampleCn = details.exampleCn
                    root = details.root ?? ""
                    synonyms = details.synonyms ?? ""
                    antonyms = details.antonyms ?? ""
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // 检查是否是次数不足的错误
                    if let serviceError = error as? DeepseekServiceError,
                       case .noRemainingCalls = serviceError {
                        showPaywall = true
                    } else {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
    
    private func handleSubmit() {
        guard !term.isEmpty && !definition.isEmpty else { return }
        
        // 检查是否重复
        let sheet = selectedSheet ?? getOrCreateTodaySheet()
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // 检查当前sheet中是否已有相同单词（忽略大小写和空格）
        let isDuplicate = words.contains { word in
            word.sheet?.id == sheet.id &&
            word.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTerm
        }
        
        if isDuplicate {
            // 保存待添加的单词数据，显示提示对话框
            pendingWordData = (
                term: term,
                definition: definition,
                partOfSpeech: partOfSpeech,
                pronunciation: pronunciation,
                example: example,
                exampleCn: exampleCn,
                root: root,
                synonyms: synonyms,
                antonyms: antonyms
            )
            showDuplicateAlert = true
        } else {
            // 没有重复，直接保存
            saveWord(
                term: term,
                definition: definition,
                partOfSpeech: partOfSpeech,
                pronunciation: pronunciation,
                example: example,
                exampleCn: exampleCn,
                root: root,
                synonyms: synonyms,
                antonyms: antonyms
            )
        }
    }
    
    private func saveWord(term: String, definition: String, partOfSpeech: String, pronunciation: String, example: String, exampleCn: String, root: String, synonyms: String, antonyms: String) {
        // 如果未选择 sheet，使用今天的 sheet
        let sheet = selectedSheet ?? getOrCreateTodaySheet()
        
        let newWord = Word(
            term: term,
            definition: definition,
            partOfSpeech: partOfSpeech,
            pronunciation: pronunciation,
            example: example,
            exampleCn: exampleCn,
            root: root,
            synonyms: synonyms,
            antonyms: antonyms,
            sheet: sheet
        )
        
        modelContext.insert(newWord)
        try? modelContext.save()
        dismiss()
    }
    
    private func handleImageSelected(_ image: UIImage) async {
        isRecognizing = true
        
        do {
            // 识别文字（图片已经是裁剪后的，直接识别整张图片）
            let words = try await TextRecognitionService.shared.recognizeWords(from: image)
            
            await MainActor.run {
                isRecognizing = false
                
                if words.isEmpty {
                    errorMessage = LocalizedKey.noWordsRecognizedError.rawValue.localized
                    showError = true
                } else {
                    recognizedWords = words
                    showBatchAddView = true
                }
            }
        } catch {
            await MainActor.run {
                isRecognizing = false
                errorMessage = String(format: LocalizedKey.recognizeFailed.rawValue.localized, error.localizedDescription)
                showError = true
            }
        }
    }
}
