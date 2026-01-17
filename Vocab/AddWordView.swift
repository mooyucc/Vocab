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
    
    @State private var term: String = ""
    @State private var definition: String = ""
    @State private var partOfSpeech: String = ""
    @State private var pronunciation: String = ""
    @State private var example: String = ""
    @State private var exampleCn: String = ""
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
    
    var body: some View {
        NavigationStack {
            Form {
                // 单词输入
                Section {
                    HStack(spacing: 12) {
                        TextField("Apple", text: $term)
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
                    TextField("苹果", text: $definition)
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
                
                // 例句
                Section {
                    TextField("An apple a day keeps the doctor away.", text: $example, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(LocalizedKey.example)
                }
                
                // 翻译
                Section {
                    TextField("一天一苹果，医生远离我。", text: $exampleCn, axis: .vertical)
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
            .onAppear {
                if selectedSheetId == nil {
                    let todaySheet = getOrCreateTodaySheet()
                    selectedSheetId = todaySheet.id
                }
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
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func handleSubmit() {
        guard !term.isEmpty && !definition.isEmpty else { return }
        
        // 如果未选择 sheet，使用今天的 sheet
        let sheet = selectedSheet ?? getOrCreateTodaySheet()
        
        let newWord = Word(
            term: term,
            definition: definition,
            partOfSpeech: partOfSpeech,
            pronunciation: pronunciation,
            example: example,
            exampleCn: exampleCn,
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
