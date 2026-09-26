//
//  WordSheetManageViews.swift
//  Vocab
//

import SwiftUI
import SwiftData

struct WordSheetEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localizedString = LocalizedString.shared
    @Query private var allSheets: [WordSheet]
    
    let sheet: WordSheet?
    var onSaved: ((WordSheet) -> Void)? = nil
    
    @State private var name: String = ""
    @State private var symbolName: String = "book.closed"
    @State private var colorName: String = "accent"
    @State private var isPinned: Bool = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    private var isEditing: Bool { sheet != nil }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(LocalizedKey.newSheetPlaceholder.rawValue.localized, text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text(LocalizedKey.sheetName)
                }
                
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        ForEach(WordSheetAppearance.symbols, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                                VocabHaptics.impact(.light)
                            } label: {
                                Image(systemName: symbol)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(symbolName == symbol ? Color.white : selectedColor)
                                    .frame(width: 44, height: 44)
                                    .background(symbolName == symbol ? selectedColor : selectedColor.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                            .accessibilityAddTraits(symbolName == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(LocalizedKey.sheetIcon)
                }
                
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(WordSheetAppearance.colorNames, id: \.self) { color in
                                Button {
                                    colorName = color
                                    VocabHaptics.impact(.light)
                                } label: {
                                    colorSwatch(for: color)
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            if colorName == color {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(color == "accent" || color == "orange" || color == "pink" || color == "gray" ? Color.vocabInk : .white)
                                            }
                                        }
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(color == "accent" ? LocalizedKey.resetSheetColor.rawValue.localized : color)
                                .accessibilityAddTraits(colorName == color ? .isSelected : [])
                            }
                        }
                    }
                    
                    if colorName != "accent" {
                        Button {
                            colorName = "accent"
                            VocabHaptics.impact(.light)
                        } label: {
                            Label(LocalizedKey.resetSheetColor.rawValue.localized, systemImage: "arrow.counterclockwise")
                        }
                    }
                } header: {
                    Text(LocalizedKey.sheetColor)
                } footer: {
                    Text(LocalizedKey.resetSheetColorHint)
                }
                
                Section {
                    Toggle(isOn: $isPinned) {
                        Label(LocalizedKey.pinSheet.rawValue.localized, systemImage: "pin.fill")
                    }
                }
            }
            .navigationTitle((isEditing ? LocalizedKey.editSheet : LocalizedKey.newSheet).rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedKey.cancel.rawValue.localized) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedKey.save.rawValue.localized) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let sheet {
                    name = sheet.localizedDisplayName
                    if WordSheetService.parsedDate(fromName: sheet.name) == nil {
                        name = sheet.name
                    }
                    symbolName = sheet.displaySymbolName
                    colorName = sheet.colorName.isEmpty ? "accent" : sheet.colorName
                    isPinned = sheet.isPinned
                }
            }
            .alert(LocalizedKey.editSheet.rawValue.localized, isPresented: $showError) {
                Button(LocalizedKey.ok.rawValue.localized, role: .cancel) { }
            } message: {
                Text(errorMessage ?? LocalizedKey.unknownError.rawValue.localized)
            }
        }
    }
    
    private var selectedColor: Color {
        if colorName == "accent" || colorName.isEmpty {
            return Color.vocabBrand
        }
        return WordSheetAppearance.color(named: colorName)
    }
    
    @ViewBuilder
    private func colorSwatch(for color: String) -> some View {
        if color == "accent" {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [Color.vocabBrand, Color.vocabSurface, Color.vocabGold, Color.vocabBrand],
                        center: .center
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.vocabInk.opacity(0.12), lineWidth: 1)
                }
        } else {
            Circle()
                .fill(WordSheetAppearance.color(named: color))
        }
    }
    
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = LocalizedKey.sheetNameEmpty.rawValue.localized
            showError = true
            return
        }
        if WordSheetService.existingSheet(named: trimmed, in: allSheets, excluding: sheet?.id) != nil {
            errorMessage = LocalizedKey.sheetNameExists.rawValue.localized
            showError = true
            return
        }
        
        let storedName = WordSheetService.parsedDate(fromName: trimmed) != nil
            ? WordSheetService.canonicalKey(forName: trimmed)
            : trimmed
        
        let saved: WordSheet
        if let sheet {
            sheet.name = storedName
            sheet.symbolName = symbolName
            sheet.colorName = colorName
            sheet.isPinned = isPinned
            try? modelContext.save()
            saved = sheet
        } else {
            saved = WordSheetService.createSheet(
                name: storedName,
                symbolName: symbolName,
                colorName: colorName,
                isPinned: isPinned,
                in: allSheets,
                context: modelContext
            )
        }
        VocabHaptics.notify(.success)
        onSaved?(saved)
        dismiss()
    }
}

struct MergeSheetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localizedString = LocalizedString.shared
    @Query private var allSheets: [WordSheet]
    
    var presetSourceIds: Set<UUID> = []
    
    @State private var sourceIds: Set<UUID> = []
    @State private var targetId: UUID?
    @State private var showDuplicatePolicy = false
    @State private var duplicateCount = 0
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var sheets: [WordSheet] {
        WordSheetService.sortedSheets(allSheets)
    }
    
    private var canMerge: Bool {
        guard let targetId else { return false }
        return sourceIds.contains(where: { $0 != targetId })
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(sheets) { sheet in
                        Button {
                            if sourceIds.contains(sheet.id) {
                                sourceIds.remove(sheet.id)
                            } else {
                                sourceIds.insert(sheet.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                sheetGlyph(sheet)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sheet.localizedDisplayName)
                                        .foregroundStyle(.primary)
                                    Text(LocalizedFormat.wordCount(sheet.wordCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: sourceIds.contains(sheet.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(sourceIds.contains(sheet.id) ? Color.vocabBrand : .secondary)
                            }
                        }
                    }
                } header: {
                    Text(LocalizedKey.mergeSelectSources)
                }
                
                Section {
                    Picker(LocalizedKey.mergeSelectTarget.rawValue.localized, selection: $targetId) {
                        Text("—").tag(UUID?.none)
                        ForEach(sheets) { sheet in
                            Text(sheet.localizedDisplayName).tag(Optional(sheet.id))
                        }
                    }
                } header: {
                    Text(LocalizedKey.mergeSelectTarget)
                } footer: {
                    Text(LocalizedKey.mergeNeedSourceTarget)
                }
                
                Section {
                    Button {
                        prepareMerge()
                    } label: {
                        Text(LocalizedKey.mergeConfirm)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canMerge)
                }
            }
            .navigationTitle(LocalizedKey.mergeSheets.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedKey.cancel.rawValue.localized) { dismiss() }
                }
            }
            .onAppear {
                if sourceIds.isEmpty {
                    sourceIds = presetSourceIds
                }
            }
            .alert(LocalizedKey.mergeSheets.rawValue.localized, isPresented: $showError) {
                Button(LocalizedKey.ok.rawValue.localized, role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog(
                LocalizedKey.mergeDuplicatesTitle.rawValue.localized,
                isPresented: $showDuplicatePolicy,
                titleVisibility: .visible
            ) {
                Button(LocalizedKey.keepBetterProgress.rawValue.localized) {
                    performMerge(policy: .keepBetterProgress)
                }
                Button(LocalizedKey.keepBoth.rawValue.localized) {
                    performMerge(policy: .keepBoth)
                }
                Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) { }
            } message: {
                Text(String(format: LocalizedKey.mergeDuplicatesMessage.rawValue.localized, duplicateCount))
            }
        }
    }
    
    private func sheetGlyph(_ sheet: WordSheet) -> some View {
        Image(systemName: sheet.displaySymbolName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(sheet.tintColor)
            .frame(width: 28, height: 28)
            .background(sheet.tintColor.opacity(0.12), in: Circle())
    }
    
    private func prepareMerge() {
        guard let targetId,
              let target = sheets.first(where: { $0.id == targetId }) else {
            errorMessage = LocalizedKey.mergeNeedSourceTarget.rawValue.localized
            showError = true
            return
        }
        let sources = sheets.filter { sourceIds.contains($0.id) && $0.id != targetId }
        guard !sources.isEmpty else {
            errorMessage = LocalizedKey.mergeNeedSourceTarget.rawValue.localized
            showError = true
            return
        }
        let count = WordSheetService.duplicateCount(merging: sources, into: target)
        if count > 0 {
            duplicateCount = count
            showDuplicatePolicy = true
        } else {
            performMerge(policy: .keepBoth)
        }
    }
    
    private func performMerge(policy: WordSheetDuplicatePolicy) {
        guard let targetId,
              let target = sheets.first(where: { $0.id == targetId }) else { return }
        let sources = sheets.filter { sourceIds.contains($0.id) && $0.id != targetId }
        WordSheetService.merge(sources: sources, into: target, policy: policy, context: modelContext)
        VocabHaptics.notify(.success)
        dismiss()
    }
}

struct ReorderSheetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localizedString = LocalizedString.shared
    @Query private var allSheets: [WordSheet]
    
    @State private var pinned: [WordSheet] = []
    @State private var unpinned: [WordSheet] = []
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pinned, id: \.id) { sheet in
                        reorderRow(sheet)
                    }
                    .onMove(perform: movePinned)
                } header: {
                    Text(LocalizedKey.pinnedSheets)
                }
                
                Section {
                    ForEach(unpinned, id: \.id) { sheet in
                        reorderRow(sheet)
                    }
                    .onMove(perform: moveUnpinned)
                } header: {
                    Text(LocalizedKey.otherSheets)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(LocalizedKey.reorderSheets.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedKey.done.rawValue.localized) { dismiss() }
                }
            }
            .onAppear(perform: reload)
            .onChange(of: allSheets.count) { _, _ in
                reload()
            }
        }
    }
    
    private func reorderRow(_ sheet: WordSheet) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sheet.displaySymbolName)
                .foregroundStyle(sheet.tintColor)
                .frame(width: 28)
            Text(sheet.localizedDisplayName)
            Spacer()
        }
    }
    
    private func reload() {
        let sorted = WordSheetService.sortedSheets(allSheets)
        pinned = sorted.filter(\.isPinned)
        unpinned = sorted.filter { !$0.isPinned }
    }
    
    private func movePinned(from offsets: IndexSet, to destination: Int) {
        pinned.move(fromOffsets: offsets, toOffset: destination)
        WordSheetService.applySortOrder(pinned: pinned, unpinned: unpinned)
        try? modelContext.save()
    }
    
    private func moveUnpinned(from offsets: IndexSet, to destination: Int) {
        unpinned.move(fromOffsets: offsets, toOffset: destination)
        WordSheetService.applySortOrder(pinned: pinned, unpinned: unpinned)
        try? modelContext.save()
    }
}

struct MergeIntoSheetPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localizedString = LocalizedString.shared
    @Query private var allSheets: [WordSheet]
    
    let source: WordSheet
    
    @State private var showDuplicatePolicy = false
    @State private var duplicateCount = 0
    @State private var pendingTarget: WordSheet?
    
    private var targets: [WordSheet] {
        WordSheetService.sortedSheets(allSheets).filter { $0.id != source.id }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if targets.isEmpty {
                    ContentUnavailableView(
                        LocalizedKey.noTargetSheet.rawValue.localized,
                        systemImage: "folder",
                        description: Text(LocalizedKey.mergeNeedSourceTarget)
                    )
                } else {
                    List(targets) { sheet in
                        Button {
                            choose(sheet)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: sheet.displaySymbolName)
                                    .foregroundStyle(sheet.tintColor)
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sheet.localizedDisplayName)
                                        .foregroundStyle(.primary)
                                    Text(LocalizedFormat.wordCount(sheet.wordCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(LocalizedKey.mergeInto.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedKey.cancel.rawValue.localized) { dismiss() }
                }
            }
            .confirmationDialog(
                LocalizedKey.mergeDuplicatesTitle.rawValue.localized,
                isPresented: $showDuplicatePolicy,
                titleVisibility: .visible
            ) {
                Button(LocalizedKey.keepBetterProgress.rawValue.localized) {
                    if let pendingTarget {
                        WordSheetService.merge(source: source, into: pendingTarget, policy: .keepBetterProgress, context: modelContext)
                        VocabHaptics.notify(.success)
                        dismiss()
                    }
                }
                Button(LocalizedKey.keepBoth.rawValue.localized) {
                    if let pendingTarget {
                        WordSheetService.merge(source: source, into: pendingTarget, policy: .keepBoth, context: modelContext)
                        VocabHaptics.notify(.success)
                        dismiss()
                    }
                }
                Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {
                    pendingTarget = nil
                }
            } message: {
                Text(String(format: LocalizedKey.mergeDuplicatesMessage.rawValue.localized, duplicateCount))
            }
        }
    }
    
    private func choose(_ target: WordSheet) {
        let count = WordSheetService.duplicateCount(merging: [source], into: target)
        if count > 0 {
            pendingTarget = target
            duplicateCount = count
            showDuplicatePolicy = true
        } else {
            WordSheetService.merge(source: source, into: target, policy: .keepBoth, context: modelContext)
            VocabHaptics.notify(.success)
            dismiss()
        }
    }
}

struct MoveWordsSheetPicker: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var localizedString = LocalizedString.shared
    @Query private var allSheets: [WordSheet]
    
    let words: [Word]
    
    @State private var showDuplicatePolicy = false
    @State private var duplicateCount = 0
    @State private var pendingTarget: WordSheet?
    @State private var showError = false
    
    private var sheets: [WordSheet] {
        WordSheetService.sortedSheets(allSheets)
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if sheets.isEmpty {
                    ContentUnavailableView(
                        LocalizedKey.noTargetSheet.rawValue.localized,
                        systemImage: "folder",
                        description: Text(LocalizedKey.goAddWords)
                    )
                } else {
                    List(sheets) { sheet in
                        Button {
                            choose(sheet)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: sheet.displaySymbolName)
                                    .foregroundStyle(sheet.tintColor)
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sheet.localizedDisplayName)
                                        .foregroundStyle(.primary)
                                    Text(LocalizedFormat.wordCount(sheet.wordCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(LocalizedKey.moveToSheet.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedKey.cancel.rawValue.localized) { dismiss() }
                }
            }
            .alert(LocalizedKey.noTargetSheet.rawValue.localized, isPresented: $showError) {
                Button(LocalizedKey.ok.rawValue.localized, role: .cancel) { }
            }
            .confirmationDialog(
                LocalizedKey.mergeDuplicatesTitle.rawValue.localized,
                isPresented: $showDuplicatePolicy,
                titleVisibility: .visible
            ) {
                Button(LocalizedKey.keepBetterProgress.rawValue.localized) {
                    if let pendingTarget {
                        WordSheetService.move(words: words, to: pendingTarget, policy: .keepBetterProgress, context: modelContext)
                        VocabHaptics.notify(.success)
                        dismiss()
                    }
                }
                Button(LocalizedKey.keepBoth.rawValue.localized) {
                    if let pendingTarget {
                        WordSheetService.move(words: words, to: pendingTarget, policy: .keepBoth, context: modelContext)
                        VocabHaptics.notify(.success)
                        dismiss()
                    }
                }
                Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {
                    pendingTarget = nil
                }
            } message: {
                Text(String(format: LocalizedKey.mergeDuplicatesMessage.rawValue.localized, duplicateCount))
            }
        }
    }
    
    private func choose(_ sheet: WordSheet) {
        let count = WordSheetService.duplicateCount(moving: words, to: sheet)
        if count > 0 {
            pendingTarget = sheet
            duplicateCount = count
            showDuplicatePolicy = true
        } else {
            WordSheetService.move(words: words, to: sheet, policy: .keepBoth, context: modelContext)
            VocabHaptics.notify(.success)
            dismiss()
        }
    }
}
