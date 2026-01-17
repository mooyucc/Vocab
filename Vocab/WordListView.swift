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
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @Query(sort: \WordSheet.createdAt, order: .reverse) private var allSheets: [WordSheet]
    @Binding var selectedTab: AppView
    
    @State private var searchText: String = ""
    @State private var showAddWord = false
    @State private var expandedSheetIds: Set<UUID> = []
    
    private var filteredWords: [Word] {
        if searchText.isEmpty {
            return words
        } else {
            return words.filter { word in
                word.term.localizedCaseInsensitiveContains(searchText) ||
                word.definition.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var sheetsWithWords: [WordSheet] {
        allSheets.filter { sheet in
            words.contains { $0.sheet?.id == sheet.id }
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // 头部
                VStack(spacing: 16) {
                    Text(LocalizedKey.myWordList)
                        .font(.largeTitle)
                        .fontWeight(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 搜索框
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
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .background(Color(.systemBackground))
                
                // 单词列表
                if filteredWords.isEmpty {
                    if #available(iOS 17.0, *) {
                        ContentUnavailableView {
                            Label(searchText.isEmpty ? LocalizedKey.noWordsYet.rawValue.localized : LocalizedKey.noResults.rawValue.localized, systemImage: searchText.isEmpty ? "book.closed" : "magnifyingglass")
                        } description: {
                            Text(searchText.isEmpty ? LocalizedKey.goAddWords.rawValue.localized : LocalizedKey.tryOtherKeywords.rawValue.localized)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: searchText.isEmpty ? "book.closed" : "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundStyle(.tertiary)
                            Text(searchText.isEmpty ? LocalizedKey.goAddWords.rawValue.localized : LocalizedKey.noResults.rawValue.localized)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if searchText.isEmpty {
                                // 按 sheet 分组显示
                                ForEach(sheetsWithWords) { sheet in
                                    SheetSection(
                                        sheet: sheet,
                                        words: words.filter { $0.sheet?.id == sheet.id },
                                        isExpanded: expandedSheetIds.contains(sheet.id),
                                        onToggle: {
                                            if expandedSheetIds.contains(sheet.id) {
                                                expandedSheetIds.remove(sheet.id)
                                            } else {
                                                expandedSheetIds.insert(sheet.id)
                                            }
                                        },
                                        onDelete: { word in
                                            deleteWord(word)
                                        }
                                    )
                                }
                            } else {
                                // 搜索模式：直接显示所有匹配的单词
                                ForEach(filteredWords) { word in
                                    WordRow(word: word, onDelete: {
                                        deleteWord(word)
                                    })
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 90) // 为"+"按钮和底部导航栏留出空间
                    }
                }
            }
            
            // 添加按钮（浮动在内容之上）
            Button(action: {
                showAddWord = true
            }) {
                Image(systemName: "plus")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.tint, in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(LocalizedKey.addNewWord.rawValue.localized)")
            .padding(.bottom, 20) // 与底部导航栏的间距
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showAddWord) {
            AddWordView()
        }
    }
    
    private func deleteWord(_ word: Word) {
        modelContext.delete(word)
    }
}

struct SheetSection: View {
    let sheet: WordSheet
    let words: [Word]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDelete: (Word) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sheet 标题
            Button(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sheet.localizedDisplayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(String(format: "%d %@", words.count, LocalizedKey.word.rawValue.localized))
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
            .accessibilityLabel("\(sheet.localizedDisplayName)，\(words.count) \(LocalizedKey.word.rawValue.localized)")
            
            // 单词列表
            if isExpanded {
                ForEach(words) { word in
                    WordRow(word: word, onDelete: {
                        onDelete(word)
                    })
                }
            }
        }
    }
}

struct WordRow: View {
    let word: Word
    let onDelete: () -> Void
    
    var body: some View {
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
            }
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(LocalizedKey.delete.rawValue.localized) \(word.term)")
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.term)，\(word.partOfSpeech)，\(word.definition)")
    }
}
