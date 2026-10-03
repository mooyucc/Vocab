//
//  EditWordView.swift
//  Vocab
//
//  编辑已有单词（保留复习进度）
//

import SwiftUI
import SwiftData

struct EditWordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localizedString = LocalizedString.shared
    
    let word: Word
    
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
    @State private var selectedSheetId: UUID?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showDuplicateAlert: Bool = false
    @State private var showPaywall: Bool = false
    @State private var showCreateSheet = false
    @State private var errorTitleKey: LocalizedKey = .aiGenerateFailed
    @State private var didLoadInitialValues = false
    
    private var canSaveWord: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var sortedSheets: [WordSheet] {
        WordSheetService.sortedSheets(allSheets)
    }
    
    private var selectedSheet: WordSheet? {
        guard let id = selectedSheetId else { return nil }
        return allSheets.first { $0.id == id }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField(LocalizedKey.word.rawValue.localized, text: $term)
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
                        .disabled(isLoading || term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("\(LocalizedKey.aiFill.rawValue.localized) \(LocalizedKey.word.rawValue.localized)")
                    }
                } header: {
                    Text(LocalizedKey.word)
                }
                
                Section {
                    TextField(LocalizedKey.definition.rawValue.localized, text: $definition, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text(LocalizedKey.definition)
                }
                
                Section {
                    HStack(spacing: 16) {
                        TextField("n.", text: $partOfSpeech)
                        TextField("/.../", text: $pronunciation)
                            .fontDesign(.serif)
                    }
                } header: {
                    Text(LocalizedKey.partOfSpeech)
                }
                
                Section {
                    TextField(LocalizedKey.rootPlaceholder.rawValue.localized, text: $root, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text(LocalizedKey.root)
                }
                
                Section {
                    TextField(LocalizedKey.synonymsPlaceholder.rawValue.localized, text: $synonyms, axis: .vertical)
                        .lineLimit(1...3)
                    TextField(LocalizedKey.antonymsPlaceholder.rawValue.localized, text: $antonyms, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text(LocalizedKey.synonymsAntonyms)
                }
                
                Section {
                    TextField(LocalizedKey.example.rawValue.localized, text: $example, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text(LocalizedKey.example)
                }
                
                Section {
                    TextField(LocalizedKey.translation.rawValue.localized, text: $exampleCn, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text(LocalizedKey.translation)
                }
                
                Section {
                    Picker(LocalizedKey.wordSheet.rawValue.localized, selection: $selectedSheetId) {
                        ForEach(sortedSheets) { sheet in
                            Text(sheet.localizedDisplayName).tag(Optional(sheet.id))
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
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .navigationTitle(LocalizedKey.editWordTitle.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedKey.cancel.rawValue.localized) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedKey.saveWord.rawValue.localized) {
                        handleSubmit()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSaveWord || isLoading)
                }
            }
            .alert(errorTitleKey.rawValue.localized, isPresented: $showError) {
                Button(LocalizedKey.ok.rawValue.localized, role: .cancel) { }
            } message: {
                Text(errorMessage ?? LocalizedKey.unknownError.rawValue.localized)
            }
            .alert(LocalizedKey.duplicateWordTitle.rawValue.localized, isPresented: $showDuplicateAlert) {
                Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) { }
                Button(LocalizedKey.save.rawValue.localized) {
                    applyEdits()
                }
            } message: {
                Text(String(format: LocalizedKey.duplicateWordMessage.rawValue.localized, term.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            .onAppear {
                loadInitialValuesIfNeeded()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showCreateSheet) {
                WordSheetEditorView(sheet: nil) { created in
                    selectedSheetId = created.id
                }
            }
        }
    }
    
    private func loadInitialValuesIfNeeded() {
        guard !didLoadInitialValues else { return }
        didLoadInitialValues = true
        term = word.term
        definition = word.definition
        partOfSpeech = word.partOfSpeech
        pronunciation = word.pronunciation
        example = word.example
        exampleCn = word.exampleCn
        root = word.root
        synonyms = word.synonyms
        antonyms = word.antonyms
        selectedSheetId = word.sheet?.id
    }
    
    private func handleAutoFill() {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isLoading = true
        
        Task {
            do {
                let details = try await DeepseekService.shared.generateWordDetails(for: trimmed)
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
                    if let serviceError = error as? DeepseekServiceError,
                       case .noRemainingCalls = serviceError {
                        showPaywall = true
                    } else {
                        errorTitleKey = .aiGenerateFailed
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
    
    private func handleSubmit() {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return }
        
        let targetSheet = selectedSheet ?? word.sheet
        let normalizedTerm = WordSheetService.normalizedTerm(trimmedTerm)
        
        let isDuplicate = targetSheet != nil && words.contains { other in
            other.id != word.id &&
            other.sheet?.id == targetSheet?.id &&
            WordSheetService.normalizedTerm(other.term) == normalizedTerm
        }
        
        if isDuplicate {
            showDuplicateAlert = true
        } else {
            applyEdits()
        }
    }
    
    private func applyEdits() {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return }
        
        word.term = trimmedTerm
        word.definition = definition
        word.partOfSpeech = partOfSpeech
        word.pronunciation = pronunciation
        word.example = example
        word.exampleCn = exampleCn
        word.root = root
        word.synonyms = synonyms
        word.antonyms = antonyms
        
        if let targetSheet = selectedSheet, targetSheet.id != word.sheet?.id {
            WordSheetService.move(
                words: [word],
                to: targetSheet,
                policy: .keepBoth,
                context: modelContext
            )
        }
        
        do {
            try modelContext.save()
            VocabHaptics.notify(.success)
            dismiss()
        } catch {
            errorTitleKey = .saveFailed
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    let word = Word(
        term: "meticulously",
        definition: "仔细地；一丝不苟地",
        partOfSpeech: "adv.",
        pronunciation: "/məˈtɪkjələsli/",
        example: "She meticulously checked every detail.",
        exampleCn: "她一丝不苟地检查了每一个细节。"
    )
    return EditWordView(word: word)
        .modelContainer(for: [Word.self, WordSheet.self], inMemory: true)
}
