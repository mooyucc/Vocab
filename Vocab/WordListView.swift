//
//  WordListView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

struct WordListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var localizedString = LocalizedString.shared
    @Query private var allSheets: [WordSheet]
    
    @State private var searchText: String = ""
    @State private var filter: WordListFilter = .grouped
    @State private var showAddWord = false
    @State private var expandedSheetIds: Set<UUID> = []
    @State private var selectedWord: Word?
    @State private var isSelectingWords = false
    @State private var selectedWordsById: [UUID: Word] = [:]
    @State private var editorSession: SheetEditorSession?
    @State private var showMerge = false
    @State private var mergePresetSourceIds: Set<UUID> = []
    @State private var mergeSession: MergeSheetSession?
    @State private var showReorder = false
    @State private var wordsToMove: [Word] = []
    @State private var showMovePicker = false
    @State private var sheetToDelete: WordSheet?
    @State private var wordToDelete: Word?
    @State private var showDeleteWordsConfirm = false
    @State private var wordCounts: [UUID: Int] = [:]
    @State private var countRefreshGeneration = 0
    
    private var needsWordQuery: Bool {
        !searchText.isEmpty || filter == .unlearned || filter == .dueReview
    }
    
    private var selectedWordIds: Set<UUID> {
        Set(selectedWordsById.keys)
    }
    
    private var sortedSheets: [WordSheet] {
        WordSheetService.sortedSheets(allSheets)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                if needsWordQuery {
                    WordListWordsLoader { words in
                        queryContent(words: words)
                    }
                } else if allSheets.isEmpty {
                    emptyState(allWordsEmpty: true)
                } else {
                    sheetOnlyScroll
                }
            }
            
            if !isSelectingWords {
                addWordButton
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            if isSelectingWords {
                selectionBar
            }
        }
        .sheet(isPresented: $showAddWord, onDismiss: scheduleCountRefresh) {
            AddWordView()
        }
        .sheet(item: $selectedWord) { word in
            wordDetailSheet(word)
        }
        .sheet(item: $editorSession, onDismiss: scheduleCountRefresh) { session in
            WordSheetEditorView(sheet: session.sheet)
        }
        .sheet(isPresented: $showMerge, onDismiss: scheduleCountRefresh) {
            MergeSheetsView(presetSourceIds: mergePresetSourceIds)
        }
        .sheet(item: $mergeSession, onDismiss: scheduleCountRefresh) { session in
            MergeIntoSheetPicker(source: session.sheet)
        }
        .sheet(isPresented: $showReorder, onDismiss: scheduleCountRefresh) {
            ReorderSheetsView()
        }
        .sheet(isPresented: $showMovePicker, onDismiss: scheduleCountRefresh) {
            MoveWordsSheetPicker(words: wordsToMove)
        }
        .alert(
            LocalizedKey.deleteSheet.rawValue.localized,
            isPresented: Binding(
                get: { sheetToDelete != nil },
                set: { if !$0 { sheetToDelete = nil } }
            )
        ) {
            Button(LocalizedKey.delete.rawValue.localized, role: .destructive) {
                if let sheetToDelete {
                    modelContext.delete(sheetToDelete)
                    try? modelContext.save()
                    VocabHaptics.notify(.warning)
                    scheduleCountRefresh()
                }
                sheetToDelete = nil
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {
                sheetToDelete = nil
            }
        } message: {
            if let sheetToDelete {
                Text(String(format: LocalizedKey.deleteSheetMessage.rawValue.localized, sheetToDelete.localizedDisplayName, wordCount(for: sheetToDelete.id)))
            }
        }
        .alert(
            LocalizedKey.deleteWordConfirmTitle.rawValue.localized,
            isPresented: Binding(
                get: { wordToDelete != nil },
                set: { if !$0 { wordToDelete = nil } }
            )
        ) {
            Button(LocalizedKey.delete.rawValue.localized, role: .destructive) {
                if let wordToDelete {
                    deleteWord(wordToDelete)
                    VocabHaptics.notify(.warning)
                }
                wordToDelete = nil
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {
                wordToDelete = nil
            }
        } message: {
            if let wordToDelete {
                Text(String(format: LocalizedKey.deleteWordConfirmMessage.rawValue.localized, wordToDelete.term))
            }
        }
        .alert(
            LocalizedKey.deleteWordsConfirmTitle.rawValue.localized,
            isPresented: $showDeleteWordsConfirm
        ) {
            Button(LocalizedKey.delete.rawValue.localized, role: .destructive) {
                deleteSelectedWords()
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) { }
        } message: {
            Text(String(format: LocalizedKey.deleteWordsConfirmMessage.rawValue.localized, selectedWordsById.count))
        }
        .modifier(SelectionHapticsModifier(count: selectedWordsById.count))
        .onAppear {
            scheduleCountRefresh()
        }
        .onChange(of: allSheets.count) { _, _ in
            scheduleCountRefresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                scheduleCountRefresh()
            }
        }
    }
    
    private var header: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text(LocalizedKey.myWordList)
                    .font(.largeTitle)
                    .fontWeight(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if isSelectingWords {
                    Button(LocalizedKey.done.rawValue.localized) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelectingWords = false
                            selectedWordsById.removeAll()
                        }
                    }
                    .fontWeight(.semibold)
                } else {
                    Menu {
                        Button {
                            editorSession = SheetEditorSession(sheet: nil)
                        } label: {
                            Label(LocalizedKey.newSheet.rawValue.localized, systemImage: "folder.badge.plus")
                        }
                        Button {
                            mergePresetSourceIds = []
                            showMerge = true
                        } label: {
                            Label(LocalizedKey.mergeSheets.rawValue.localized, systemImage: "square.stack.3d.up.fill")
                        }
                        Button {
                            showReorder = true
                        } label: {
                            Label(LocalizedKey.reorderSheets.rawValue.localized, systemImage: "arrow.up.arrow.down")
                        }
                        Divider()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectingWords = true
                            }
                        } label: {
                            Label(LocalizedKey.selectWords.rawValue.localized, systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(LocalizedKey.more.rawValue.localized)
                }
            }
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                
                TextField(LocalizedKey.searchWords.rawValue.localized, text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 12)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(LocalizedKey.searchWords.rawValue.localized)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WordListFilter.allCases) { item in
                        filterChip(item)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Color(.systemBackground))
    }
    
    private func filterChip(_ item: WordListFilter) -> some View {
        let selected = filter == item
        return Button {
            VocabHaptics.impact(.light)
            withAnimation(.easeInOut(duration: 0.2)) {
                filter = item
            }
        } label: {
            Label(item.titleKey.rawValue.localized, systemImage: item.systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.vocabBrand : Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    
    @ViewBuilder
    private func queryContent(words: [Word]) -> some View {
        let snapshot = WordListSnapshot(
            words: words,
            sheets: allSheets,
            searchText: searchText,
            filter: filter
        )
        if snapshot.isEmpty {
            emptyState(allWordsEmpty: words.isEmpty)
        } else {
            wordScroll(snapshot)
        }
    }
    
    @ViewBuilder
    private func emptyState(allWordsEmpty: Bool) -> some View {
        let title: String = {
            if !searchText.isEmpty { return LocalizedKey.noResults.rawValue.localized }
            switch filter {
            case .unlearned: return LocalizedKey.noUnlearnedWords.rawValue.localized
            case .dueReview: return LocalizedKey.noDueReviewWords.rawValue.localized
            case .grouped, .byMonth: return LocalizedKey.noWordsYet.rawValue.localized
            }
        }()
        let description: String = {
            if !searchText.isEmpty { return LocalizedKey.tryOtherKeywords.rawValue.localized }
            switch filter {
            case .unlearned, .dueReview: return LocalizedKey.goAddWords.rawValue.localized
            case .grouped, .byMonth: return LocalizedKey.goAddWords.rawValue.localized
            }
        }()
        let icon = searchText.isEmpty ? (filter == .dueReview ? "clock" : "book.closed") : "magnifyingglass"
        
        if searchText.isEmpty && allWordsEmpty {
            ContentUnavailableView {
                Label(LocalizedKey.noWordsYet.rawValue.localized, systemImage: "book.closed")
            } description: {
                Text(LocalizedKey.goAddWords)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .dismissKeyboardOnTap()
        }
    }
    
    private var sheetOnlyScroll: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if filter == .byMonth {
                    ForEach(WordListSnapshot.makeMonthGroups(from: sortedSheets), id: \.id) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            ForEach(group.sheets) { sheet in
                                lazySheetSection(sheet)
                            }
                        }
                    }
                } else {
                    ForEach(sortedSheets) { sheet in
                        lazySheetSection(sheet)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, isSelectingWords ? 24 : 90)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
    }
    
    private func wordScroll(_ snapshot: WordListSnapshot) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if !searchText.isEmpty {
                    ForEach(snapshot.filteredWords) { word in
                        wordRow(word, showSheetName: true)
                    }
                } else if filter == .byMonth {
                    ForEach(snapshot.monthGroups, id: \.id) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                            ForEach(group.sheets) { sheet in
                                querySheetSection(sheet, snapshot: snapshot)
                            }
                        }
                    }
                } else {
                    ForEach(snapshot.visibleSheets) { sheet in
                        querySheetSection(sheet, snapshot: snapshot)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, isSelectingWords ? 24 : 90)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
    }
    
    private func lazySheetSection(_ sheet: WordSheet) -> some View {
        let isExpanded = expandedSheetIds.contains(sheet.id)
        return SheetSection(
            sheet: sheet,
            words: nil,
            wordCount: wordCounts[sheet.id],
            isExpanded: isExpanded,
            isSelecting: isSelectingWords,
            selectedWordIds: selectedWordIds,
            onToggle: {
                toggleSheet(sheet.id)
            },
            onDeleteWord: { word in
                wordToDelete = word
            },
            onWordTap: { word in
                handleWordTap(word)
            },
            onMoveWord: { word in
                wordsToMove = [word]
                showMovePicker = true
            },
            onPin: {
                sheet.isPinned.toggle()
                try? modelContext.save()
                VocabHaptics.impact(.medium)
            },
            onEdit: {
                editorSession = SheetEditorSession(sheet: sheet)
            },
            onMerge: {
                mergeSession = MergeSheetSession(sheet: sheet)
            },
            onDeleteSheet: {
                sheetToDelete = sheet
            },
            onLoadedCount: { count in
                wordCounts[sheet.id] = count
            }
        )
    }
    
    private func querySheetSection(_ sheet: WordSheet, snapshot: WordListSnapshot) -> some View {
        let isExpanded = expandedSheetIds.contains(sheet.id)
        let sectionWords = snapshot.words(for: sheet)
        return SheetSection(
            sheet: sheet,
            words: isExpanded ? sectionWords : [],
            wordCount: sectionWords.count,
            isExpanded: isExpanded,
            isSelecting: isSelectingWords,
            selectedWordIds: selectedWordIds,
            onToggle: {
                toggleSheet(sheet.id)
            },
            onDeleteWord: { word in
                wordToDelete = word
            },
            onWordTap: { word in
                handleWordTap(word)
            },
            onMoveWord: { word in
                wordsToMove = [word]
                showMovePicker = true
            },
            onPin: {
                sheet.isPinned.toggle()
                try? modelContext.save()
                VocabHaptics.impact(.medium)
            },
            onEdit: {
                editorSession = SheetEditorSession(sheet: sheet)
            },
            onMerge: {
                mergeSession = MergeSheetSession(sheet: sheet)
            },
            onDeleteSheet: {
                sheetToDelete = sheet
            }
        )
    }
    
    private func wordRow(_ word: Word, showSheetName: Bool) -> some View {
        WordRow(
            word: word,
            showSheetName: showSheetName,
            isSelecting: isSelectingWords,
            isSelected: selectedWordsById[word.id] != nil,
            onDelete: { wordToDelete = word },
            onTap: { handleWordTap(word) },
            onMove: {
                wordsToMove = [word]
                showMovePicker = true
            }
        )
    }
    
    private var addWordButton: some View {
        Button(action: {
            showAddWord = true
        }) {
            Image(systemName: "plus")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(LinearGradient.vocabBrandProgress, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(LocalizedKey.addNewWord.rawValue.localized)")
        .padding(.bottom, 20)
    }
    
    private var selectionBar: some View {
        HStack(spacing: 16) {
            Button {
                wordsToMove = Array(selectedWordsById.values)
                showMovePicker = true
            } label: {
                Label(LocalizedKey.moveWords.rawValue.localized, systemImage: "folder")
            }
            .disabled(selectedWordsById.isEmpty)
            
            Spacer()
            
            Text(String(format: LocalizedKey.selectedWordsCount.rawValue.localized, selectedWordsById.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button(role: .destructive) {
                showDeleteWordsConfirm = true
            } label: {
                Label(LocalizedKey.delete.rawValue.localized, systemImage: "trash")
            }
            .disabled(selectedWordsById.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
    
    private func wordDetailSheet(_ word: Word) -> some View {
        NavigationStack {
            FlashCardView(word: word, onResult: { _ in
                selectedWord = nil
            }, showActionButtons: false)
            .padding(.horizontal, 20)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LocalizedKey.done.rawValue.localized) {
                        selectedWord = nil
                    }
                }
            }
        }
    }
    
    private func toggleSheet(_ id: UUID) {
        if expandedSheetIds.contains(id) {
            expandedSheetIds.remove(id)
        } else {
            expandedSheetIds.insert(id)
        }
    }
    
    private func handleWordTap(_ word: Word) {
        if isSelectingWords {
            if selectedWordsById[word.id] != nil {
                selectedWordsById.removeValue(forKey: word.id)
            } else {
                selectedWordsById[word.id] = word
            }
        } else {
            selectedWord = word
        }
    }
    
    private func deleteWord(_ word: Word) {
        selectedWordsById.removeValue(forKey: word.id)
        if let sheetId = word.sheet?.id, let count = wordCounts[sheetId] {
            wordCounts[sheetId] = max(0, count - 1)
        }
        modelContext.delete(word)
        try? modelContext.save()
    }
    
    private func deleteSelectedWords() {
        for word in selectedWordsById.values {
            modelContext.delete(word)
        }
        try? modelContext.save()
        selectedWordsById.removeAll()
        isSelectingWords = false
        scheduleCountRefresh()
        VocabHaptics.notify(.warning)
    }
    
    private func wordCount(for sheetId: UUID) -> Int {
        if let cached = wordCounts[sheetId] {
            return cached
        }
        return fetchWordCount(for: sheetId)
    }
    
    private func fetchWordCount(for sheetId: UUID) -> Int {
        let target = sheetId
        let descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.sheet?.id == target
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
    
    private func scheduleCountRefresh() {
        countRefreshGeneration += 1
        let generation = countRefreshGeneration
        Task { @MainActor in
            await Task.yield()
            guard generation == countRefreshGeneration else { return }
            refreshWordCounts()
        }
    }
    
    private func refreshWordCounts() {
        var next: [UUID: Int] = [:]
        next.reserveCapacity(allSheets.count)
        for sheet in allSheets {
            next[sheet.id] = fetchWordCount(for: sheet.id)
        }
        wordCounts = next
    }
}

/// 仅在搜索 / 未学习 / 待复习时挂到视图树，避免默认词库列表拉全量单词。
private struct WordListWordsLoader<Content: View>: View {
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    private let content: ([Word]) -> Content
    
    init(@ViewBuilder content: @escaping ([Word]) -> Content) {
        self.content = content
    }
    
    var body: some View {
        content(words)
    }
}

private struct WordListSnapshot {
    let grouped: [UUID: [Word]]
    let visibleSheets: [WordSheet]
    let filteredWords: [Word]
    let monthGroups: [(id: String, title: String, sheets: [WordSheet])]
    let isEmpty: Bool
    
    init(words: [Word], sheets: [WordSheet], searchText: String, filter: WordListFilter) {
        let sorted = WordSheetService.sortedSheets(sheets)
        
        var list = words
        if !searchText.isEmpty {
            list = list.filter { word in
                word.term.localizedCaseInsensitiveContains(searchText) ||
                word.definition.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch filter {
        case .grouped, .byMonth:
            break
        case .unlearned:
            list = list.filter { !$0.learned }
        case .dueReview:
            list = SpacedRepetition.dueWords(from: list)
        }
        filteredWords = list
        
        var grouped: [UUID: [Word]] = [:]
        grouped.reserveCapacity(sorted.count)
        for word in list {
            guard let sheetId = word.sheet?.id else { continue }
            grouped[sheetId, default: []].append(word)
        }
        self.grouped = grouped
        
        let visible: [WordSheet]
        switch filter {
        case .grouped, .byMonth:
            visible = searchText.isEmpty ? sorted : sorted.filter { !(grouped[$0.id]?.isEmpty ?? true) }
        case .unlearned, .dueReview:
            visible = sorted.filter { !(grouped[$0.id]?.isEmpty ?? true) }
        }
        visibleSheets = visible
        
        if !searchText.isEmpty || filter == .unlearned || filter == .dueReview {
            isEmpty = list.isEmpty
        } else {
            isEmpty = sheets.isEmpty && words.isEmpty
        }
        
        if filter == .byMonth {
            monthGroups = Self.makeMonthGroups(from: visible)
        } else {
            monthGroups = []
        }
    }
    
    func words(for sheet: WordSheet) -> [Word] {
        grouped[sheet.id] ?? []
    }
    
    static func makeMonthGroups(from sheets: [WordSheet]) -> [(id: String, title: String, sheets: [WordSheet])] {
        let calendar = Calendar.current
        var buckets: [Date: [WordSheet]] = [:]
        for sheet in sheets {
            let comps = calendar.dateComponents([.year, .month], from: sheet.createdAt)
            let monthDate = calendar.date(from: comps) ?? sheet.createdAt
            buckets[monthDate, default: []].append(sheet)
        }
        return buckets.keys.sorted(by: >).map { date in
            let comps = calendar.dateComponents([.year, .month], from: date)
            let id = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            return (id, DateFormatter.localizedMonthString(from: date), WordSheetService.sortedSheets(buckets[date] ?? []))
        }
    }
}

private struct SheetEditorSession: Identifiable {
    let id = UUID()
    let sheet: WordSheet?
}

private struct MergeSheetSession: Identifiable {
    let id = UUID()
    let sheet: WordSheet
}

private struct SelectionHapticsModifier: ViewModifier {
    let count: Int
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.sensoryFeedback(.selection, trigger: count)
        } else {
            content
        }
    }
}

struct SheetSection: View {
    @ObservedObject private var localizedString = LocalizedString.shared
    let sheet: WordSheet
    var words: [Word]? = nil
    var wordCount: Int? = nil
    let isExpanded: Bool
    var isSelecting: Bool = false
    var selectedWordIds: Set<UUID> = []
    let onToggle: () -> Void
    let onDeleteWord: (Word) -> Void
    let onWordTap: (Word) -> Void
    var onMoveWord: (Word) -> Void = { _ in }
    var onPin: () -> Void = {}
    var onEdit: () -> Void = {}
    var onMerge: () -> Void = {}
    var onDeleteSheet: () -> Void = {}
    var onLoadedCount: (Int) -> Void = { _ in }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: sheet.displaySymbolName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(sheet.tintColor)
                        .frame(width: 36, height: 36)
                        .background(sheet.tintColor.opacity(0.12), in: Circle())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(sheet.localizedDisplayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            if sheet.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(sheet.tintColor)
                            }
                        }
                        Group {
                            if let wordCount {
                                Text(wordCount == 0 ? LocalizedKey.emptySheet.rawValue.localized : LocalizedFormat.wordCount(wordCount))
                            } else {
                                Text(" ")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityTitle)
            .contextMenu {
                Button {
                    onPin()
                } label: {
                    Label(
                        (sheet.isPinned ? LocalizedKey.unpinSheet : LocalizedKey.pinSheet).rawValue.localized,
                        systemImage: sheet.isPinned ? "pin.slash" : "pin"
                    )
                }
                Button {
                    onEdit()
                } label: {
                    Label(LocalizedKey.editSheet.rawValue.localized, systemImage: "pencil")
                }
                Button {
                    onMerge()
                } label: {
                    Label(LocalizedKey.mergeInto.rawValue.localized, systemImage: "square.stack.3d.up.fill")
                }
                Button(role: .destructive) {
                    onDeleteSheet()
                } label: {
                    Label(LocalizedKey.deleteSheet.rawValue.localized, systemImage: "trash")
                }
            }
            
            if isExpanded {
                if let words {
                    if words.isEmpty {
                        Text(LocalizedKey.emptySheet.rawValue.localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(words) { word in
                            WordRow(
                                word: word,
                                isSelecting: isSelecting,
                                isSelected: selectedWordIds.contains(word.id),
                                onDelete: { onDeleteWord(word) },
                                onTap: { onWordTap(word) },
                                onMove: { onMoveWord(word) }
                            )
                        }
                    }
                } else {
                    SheetWordsList(
                        sheet: sheet,
                        isSelecting: isSelecting,
                        selectedWordIds: selectedWordIds,
                        onDeleteWord: onDeleteWord,
                        onWordTap: onWordTap,
                        onMoveWord: onMoveWord,
                        onCount: onLoadedCount
                    )
                }
            }
        }
    }
    
    private var accessibilityTitle: String {
        if let wordCount {
            let countText = wordCount == 0
                ? LocalizedKey.emptySheet.rawValue.localized
                : LocalizedFormat.wordCount(wordCount)
            return "\(sheet.localizedDisplayName), \(countText)"
        }
        return sheet.localizedDisplayName
    }
}

private struct SheetWordsList: View {
    @ObservedObject private var localizedString = LocalizedString.shared
    let sheet: WordSheet
    var isSelecting: Bool
    var selectedWordIds: Set<UUID>
    let onDeleteWord: (Word) -> Void
    let onWordTap: (Word) -> Void
    var onMoveWord: (Word) -> Void
    var onCount: (Int) -> Void
    
    private var words: [Word] {
        (sheet.words ?? []).sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        Group {
            if words.isEmpty {
                Text(LocalizedKey.emptySheet.rawValue.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            } else {
                ForEach(words) { word in
                    WordRow(
                        word: word,
                        isSelecting: isSelecting,
                        isSelected: selectedWordIds.contains(word.id),
                        onDelete: { onDeleteWord(word) },
                        onTap: { onWordTap(word) },
                        onMove: { onMoveWord(word) }
                    )
                }
            }
        }
        .onAppear {
            onCount(words.count)
        }
        .onChange(of: words.count) { _, count in
            onCount(count)
        }
    }
}

struct WordRow: View {
    @ObservedObject private var localizedString = LocalizedString.shared
    let word: Word
    var showSheetName: Bool = false
    var isSelecting: Bool = false
    var isSelected: Bool = false
    let onDelete: () -> Void
    let onTap: () -> Void
    var onMove: () -> Void = {}
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.vocabBrand : Color.secondary)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .padding(.top, -2)
            }
            
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(word.term)
                                .font(.headline)
                            Text(word.partOfSpeech)
                                .font(.caption)
                                .fontDesign(.serif)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        
                        Text(word.definition)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        if showSheetName, let sheetName = word.sheet?.localizedDisplayName {
                            Text(sheetName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    
                    Spacer()
                    
                    if word.learned {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 16))
                            .frame(width: 16, height: 16)
                            .frame(height: 20, alignment: .center)
                            .alignmentGuide(.top) { d in
                                d[.top] + 10 - d.height / 2
                            }
                    } else {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 16, height: 16)
                            .frame(height: 20, alignment: .center)
                            .alignmentGuide(.top) { d in
                                d[.top] + 10 - d.height / 2
                            }
                    }
                }
            }
            .buttonStyle(.plain)
            
            if !isSelecting {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(LocalizedKey.delete.rawValue.localized) \(word.term)")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.term), \(word.partOfSpeech), \(word.definition)")
        .contextMenu {
            Button {
                onMove()
            } label: {
                Label(LocalizedKey.moveToSheet.rawValue.localized, systemImage: "folder")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(LocalizedKey.delete.rawValue.localized, systemImage: "trash")
            }
        }
    }
}
