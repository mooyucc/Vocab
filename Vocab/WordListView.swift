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
    @ObservedObject private var localizedString = LocalizedString.shared
    @Query private var allSheets: [WordSheet]
    
    @State private var searchText: String = ""
    @State private var filter: WordListFilter = .grouped
    @State private var showAddWord = false
    @State private var openedSheetSession: OpenedSheetSession?
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
    
    private var needsWordQuery: Bool {
        !searchText.isEmpty
    }
    
    private var sortedSheets: [WordSheet] {
        WordSheetService.sortedSheets(allSheets)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            LibraryAtmosphereBackground()
            
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
        .background(Color.vocabLibraryCanvas)
        .toolbarBackground(Color.vocabLibraryCanvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            if isSelectingWords && openedSheetSession == nil {
                selectionBar
            }
        }
        .sheet(isPresented: $showAddWord) {
            AddWordView()
        }
        .sheet(item: $openedSheetSession) { session in
            SheetWordsBrowserView(
                sheet: session.sheet,
                prefilteredWords: session.words,
                isSelecting: $isSelectingWords,
                selectedWordsById: $selectedWordsById
            )
        }
        .sheet(item: $selectedWord) { word in
            wordDetailSheet(word)
        }
        .sheet(item: $editorSession) { session in
            WordSheetEditorView(sheet: session.sheet)
        }
        .sheet(isPresented: $showMerge) {
            MergeSheetsView(presetSourceIds: mergePresetSourceIds)
        }
        .sheet(item: $mergeSession) { session in
            MergeIntoSheetPicker(source: session.sheet)
        }
        .sheet(isPresented: $showReorder) {
            ReorderSheetsView()
        }
        .sheet(isPresented: $showMovePicker) {
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
                }
                sheetToDelete = nil
            }
            Button(LocalizedKey.cancel.rawValue.localized, role: .cancel) {
                sheetToDelete = nil
            }
        } message: {
            if let sheetToDelete {
                Text(String(format: LocalizedKey.deleteSheetMessage.rawValue.localized, sheetToDelete.localizedDisplayName, sheetToDelete.wordCount))
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
            WordSheetService.ensureCountsUpToDate(in: modelContext)
        }
    }
    
    private var header: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Text(LocalizedKey.myWordList)
                    .font(.largeTitle)
                    .fontWeight(.black)
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if isSelectingWords {
                    Button(LocalizedKey.done.rawValue.localized) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelectingWords = false
                            selectedWordsById.removeAll()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
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
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.vocabLibraryControl, in: Circle())
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(LocalizedKey.more.rawValue.localized)
                }
            }
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.leading, 12)
                
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text(LocalizedKey.searchWords.rawValue.localized)
                        .foregroundStyle(.white.opacity(0.72))
                )
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(.vertical, 12)
            }
            .background(Color.white.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: VocabTheme.Radius.card, style: .continuous))
            .accessibilityLabel(LocalizedKey.searchWords.rawValue.localized)
            
            HStack(spacing: 4) {
                ForEach(WordListFilter.allCases) { item in
                    filterChip(item)
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.18), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Color.vocabInk : Color.white.opacity(0.92))
                .background(selected ? Color.vocabSurface : Color.clear, in: Capsule())
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
            return LocalizedKey.noWordsYet.rawValue.localized
        }()
        let description: String = {
            if !searchText.isEmpty { return LocalizedKey.tryOtherKeywords.rawValue.localized }
            return LocalizedKey.goAddWords.rawValue.localized
        }()
        let icon = searchText.isEmpty ? "book.closed" : "magnifyingglass"
        
        if searchText.isEmpty && allWordsEmpty {
            ContentUnavailableView {
                Label(LocalizedKey.noWordsYet.rawValue.localized, systemImage: "book.closed")
            } description: {
                Text(LocalizedKey.goAddWords)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(title, systemImage: icon)
            } description: {
                Text(description)
            }
            .foregroundStyle(.white)
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
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 4)
                            ForEach(Array(group.sheets.enumerated()), id: \.element.id) { index, sheet in
                                lazySheetSection(sheet, accentIndex: index)
                            }
                        }
                    }
                } else {
                    ForEach(Array(sortedSheets.enumerated()), id: \.element.id) { index, sheet in
                        lazySheetSection(sheet, accentIndex: index)
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
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 4)
                            ForEach(Array(group.sheets.enumerated()), id: \.element.id) { index, sheet in
                                querySheetSection(sheet, snapshot: snapshot, accentIndex: index)
                            }
                        }
                    }
                } else {
                    ForEach(Array(snapshot.visibleSheets.enumerated()), id: \.element.id) { index, sheet in
                        querySheetSection(sheet, snapshot: snapshot, accentIndex: index)
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
    
    private func lazySheetSection(_ sheet: WordSheet, accentIndex: Int) -> some View {
        SheetSection(
            sheet: sheet,
            wordCount: sheet.wordCount,
            learnedCount: sheet.learnedCount,
            accentIndex: accentIndex,
            onOpen: {
                openedSheetSession = OpenedSheetSession(sheet: sheet)
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
    
    private func querySheetSection(_ sheet: WordSheet, snapshot: WordListSnapshot, accentIndex: Int) -> some View {
        let sectionWords = snapshot.words(for: sheet)
        return SheetSection(
            sheet: sheet,
            wordCount: sectionWords.count,
            learnedCount: sectionWords.filter(\.learned).count,
            accentIndex: accentIndex,
            onOpen: {
                openedSheetSession = OpenedSheetSession(sheet: sheet, words: sectionWords)
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
                .background(Color.vocabBrand, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
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
    
    private func toggleWordSelection(_ word: Word) {
        if selectedWordsById[word.id] != nil {
            selectedWordsById.removeValue(forKey: word.id)
        } else {
            selectedWordsById[word.id] = word
        }
    }
    
    private func handleWordTap(_ word: Word) {
        if isSelectingWords {
            toggleWordSelection(word)
        } else {
            selectedWord = word
        }
    }
    
    private func deleteWord(_ word: Word) {
        selectedWordsById.removeValue(forKey: word.id)
        WordSheetService.noteWillDelete(word)
        modelContext.delete(word)
        try? modelContext.save()
    }
    
    private func deleteSelectedWords() {
        for word in selectedWordsById.values {
            WordSheetService.noteWillDelete(word)
            modelContext.delete(word)
        }
        try? modelContext.save()
        selectedWordsById.removeAll()
        isSelectingWords = false
        VocabHaptics.notify(.warning)
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
        filteredWords = list
        
        var grouped: [UUID: [Word]] = [:]
        grouped.reserveCapacity(sorted.count)
        for word in list {
            guard let sheetId = word.sheet?.id else { continue }
            grouped[sheetId, default: []].append(word)
        }
        self.grouped = grouped
        
        visibleSheets = searchText.isEmpty
            ? sorted
            : sorted.filter { !(grouped[$0.id]?.isEmpty ?? true) }
        
        if !searchText.isEmpty {
            isEmpty = list.isEmpty
        } else {
            isEmpty = sheets.isEmpty && words.isEmpty
        }
        
        if filter == .byMonth {
            monthGroups = Self.makeMonthGroups(from: visibleSheets)
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

private struct OpenedSheetSession: Identifiable {
    let id: UUID
    let sheet: WordSheet
    /// 搜索过滤后的单词；nil 表示使用词库内全部单词
    let words: [Word]?
    
    init(sheet: WordSheet, words: [Word]? = nil) {
        self.id = sheet.id
        self.sheet = sheet
        self.words = words
    }
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
    var wordCount: Int? = nil
    var learnedCount: Int? = nil
    var accentIndex: Int = 0
    let onOpen: () -> Void
    var onPin: () -> Void = {}
    var onEdit: () -> Void = {}
    var onMerge: () -> Void = {}
    var onDeleteSheet: () -> Void = {}
    
    private var accent: (fill: Color, foreground: Color) {
        let name = sheet.colorName.isEmpty ? "accent" : sheet.colorName
        if name == "accent" {
            let palette: [(Color, Color)] = [
                (Color.vocabBrand, .white),
                (Color.vocabSurface, Color.vocabInk),
                (Color.vocabGold, Color.vocabInk)
            ]
            return palette[accentIndex % palette.count]
        }
        return (sheet.tintColor, leftForeground(for: name))
    }
    
    private func leftForeground(for colorName: String) -> Color {
        switch colorName {
        case "orange", "pink", "gray", "yellow":
            return Color.vocabInk
        default:
            return .white
        }
    }
    
    private var masteryProgress: CGFloat {
        guard let total = wordCount, total > 0, let learned = learnedCount else { return 0 }
        return min(1, max(0, CGFloat(learned) / CGFloat(total)))
    }
    
    private var masteryPercent: Int? {
        guard let total = wordCount, total > 0, let learned = learnedCount else { return nil }
        return Int((Double(learned) / Double(total) * 100).rounded())
    }
    
    var body: some View {
        Button(action: onOpen) {
            progressCard
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(masteryPercent.map { "\($0)%" } ?? "")
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
    }
    
    private var progressCard: some View {
        GeometryReader { geo in
            let fillLeading: CGFloat = 6
            let badgeSize: CGFloat = 44
            let labelMin: CGFloat = 128
            let chevronSpace: CGFloat = 48 // 36 + trailing 12
            let spacerMin: CGFloat = 8
            // Track = pink fill + badge (spacing 0 → tangent). Leave room for chevron.
            let maxTrackWidth = max(
                labelMin + badgeSize,
                geo.size.width - fillLeading - spacerMin - chevronSpace
            )
            let minTrackWidth = labelMin + badgeSize
            let progress = (wordCount ?? 0) > 0 ? masteryProgress : 0
            let trackWidth = minTrackWidth + (maxTrackWidth - minTrackWidth) * progress
            let fillWidth = max(labelMin, trackWidth - badgeSize)
            
            ZStack(alignment: .leading) {
                Color.vocabLibraryStripe
                DiagonalStripePattern()
                    .opacity(0.22)
                
                HStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: VocabTheme.Radius.sheet, style: .continuous)
                            .fill(accent.fill)
                        
                        HStack(spacing: 10) {
                            Image(systemName: sheet.displaySymbolName)
                                .font(.body.weight(.bold))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .top, spacing: 4) {
                                    Text(sheet.localizedDisplayName)
                                        .font(.subheadline.weight(.bold))
                                        .fontDesign(.rounded)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    if sheet.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.top, 2)
                                    }
                                }
                                Group {
                                    if let wordCount {
                                        Text(wordCount == 0
                                             ? LocalizedKey.emptySheet.rawValue.localized
                                             : LocalizedFormat.wordCount(wordCount))
                                    } else {
                                        Text(" ")
                                    }
                                }
                                .font(.caption2.weight(.medium))
                                .opacity(0.8)
                                .lineLimit(1)
                            }
                        }
                        .foregroundStyle(accent.foreground)
                        .padding(.leading, 12)
                        .padding(.trailing, 8)
                    }
                    .frame(width: fillWidth)
                    .padding(.vertical, 6)
                    
                    masteryBadge
                        .frame(width: badgeSize, height: badgeSize)
                    
                    Spacer(minLength: spacerMin)
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.vocabInk)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.vocabSurface))
                        .padding(.trailing, 12)
                }
                .padding(.leading, fillLeading)
            }
        }
        .frame(height: 88)
        .clipShape(RoundedRectangle(cornerRadius: VocabTheme.Radius.hero, style: .continuous))
    }
    
    @ViewBuilder
    private var masteryBadge: some View {
        ZStack {
            Circle()
                .fill(Color.vocabSurface)
                .overlay {
                    Circle()
                        .strokeBorder(Color.vocabLibraryStripe, lineWidth: 2.5)
                }
            if let masteryPercent {
                Text("\(masteryPercent)%")
                    .font(.caption2.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(Color.vocabInk)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.vocabInk.opacity(0.45))
            }
        }
    }
    
    private var accessibilityTitle: String {
        var parts = [sheet.localizedDisplayName]
        if let wordCount {
            parts.append(
                wordCount == 0
                ? LocalizedKey.emptySheet.rawValue.localized
                : LocalizedFormat.wordCount(wordCount)
            )
        }
        if let masteryPercent {
            parts.append("\(masteryPercent)%")
        }
        return parts.joined(separator: ", ")
    }
}

private struct LibraryAtmosphereBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.vocabLibraryCanvas
                
                Ellipse()
                    .fill(Color.vocabLibraryBlob.opacity(0.55))
                    .frame(width: geo.size.width * 1.15, height: geo.size.width * 0.72)
                    .blur(radius: 2)
                    .offset(x: -geo.size.width * 0.22, y: -geo.size.height * 0.08)
                
                Ellipse()
                    .fill(Color.vocabLibraryBlob.opacity(0.4))
                    .frame(width: geo.size.width * 0.95, height: geo.size.width * 0.7)
                    .blur(radius: 4)
                    .offset(x: geo.size.width * 0.35, y: geo.size.height * 0.18)
                
                Ellipse()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.55)
                    .blur(radius: 8)
                    .offset(x: geo.size.width * 0.1, y: geo.size.height * 0.55)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 词库单词列表弹窗（配色与词库页一致）
private struct SheetWordsBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var localizedString = LocalizedString.shared
    
    let sheet: WordSheet
    var prefilteredWords: [Word]? = nil
    @Binding var isSelecting: Bool
    @Binding var selectedWordsById: [UUID: Word]
    
    @State private var selectedWord: Word?
    @State private var wordsToMove: [Word] = []
    @State private var showMovePicker = false
    @State private var wordToDelete: Word?
    @State private var showDeleteWordsConfirm = false
    
    private var words: [Word] {
        let all = (sheet.words ?? []).sorted { $0.createdAt > $1.createdAt }
        guard let prefilteredWords else { return all }
        let ids = Set(prefilteredWords.map(\.id))
        return all.filter { ids.contains($0.id) }
    }
    
    private var selectedWordIds: Set<UUID> {
        Set(selectedWordsById.keys)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LibraryAtmosphereBackground()
                
                Group {
                    if words.isEmpty {
                        Text(LocalizedKey.emptySheet.rawValue.localized)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(words) { word in
                                    WordRow(
                                        word: word,
                                        isSelecting: isSelecting,
                                        isSelected: selectedWordIds.contains(word.id),
                                        onDelete: { wordToDelete = word },
                                        onTap: { handleWordTap(word) },
                                        onMove: {
                                            wordsToMove = [word]
                                            showMovePicker = true
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, isSelecting ? 24 : 16)
                        }
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .background(Color.vocabLibraryCanvas)
            .navigationTitle(sheet.localizedDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.vocabLibraryCanvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedKey.done.rawValue.localized) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    selectionBar
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.vocabLibraryCanvas)
        .sheet(item: $selectedWord) { word in
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
        .sheet(isPresented: $showMovePicker) {
            MoveWordsSheetPicker(words: wordsToMove)
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
    
    private func handleWordTap(_ word: Word) {
        if isSelecting {
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
        WordSheetService.noteWillDelete(word)
        modelContext.delete(word)
        try? modelContext.save()
    }
    
    private func deleteSelectedWords() {
        for word in selectedWordsById.values {
            WordSheetService.noteWillDelete(word)
            modelContext.delete(word)
        }
        try? modelContext.save()
        selectedWordsById.removeAll()
        isSelecting = false
        VocabHaptics.notify(.warning)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            HStack(alignment: .center, spacing: 4) {
                if word.learned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.vocabTeal)
                        .font(.system(size: 16))
                        .frame(width: 16, height: 16)
                } else {
                    Circle()
                        .fill(Color.vocabGold)
                        .frame(width: 16, height: 16)
                }
                
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
        }
        .padding(16)
        .background(Color.vocabSurface)
        .clipShape(RoundedRectangle(cornerRadius: VocabTheme.Radius.card, style: .continuous))
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
