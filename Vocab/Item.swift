//
//  Item.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import Foundation
import SwiftData

@Model
final class WordSheet: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var sortOrder: Int = 0
    var isPinned: Bool = false
    var symbolName: String = "book.closed"
    var colorName: String = "accent"
    
    @Relationship(deleteRule: .cascade, inverse: \Word.sheet)
    var words: [Word]?
    
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sortOrder: Int = 0,
        isPinned: Bool = false,
        symbolName: String = "book.closed",
        colorName: String = "accent"
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isPinned = isPinned
        self.symbolName = symbolName
        self.colorName = colorName
    }
}

@Model
final class Word: Identifiable {
    var id: UUID = UUID()
    var term: String = ""
    var definition: String = ""
    var partOfSpeech: String = ""
    var pronunciation: String = ""
    var example: String = ""
    var exampleCn: String = ""
    var root: String = ""
    var synonyms: String = ""
    var antonyms: String = ""
    var learned: Bool = false
    var reviewCount: Int = 0
    var lastReviewed: Date?
    /// 仅在「推荐复习」中点「记住了」时累加；用于艾宾浩斯间隔，与复习全部/接着上次无关
    var spacedReviewCount: Int = 0
    /// 仅在「推荐复习」中点「记住了」时更新；遗忘曲线以该时间为起点
    var spacedLastReviewed: Date?
    var createdAt: Date = Date()
    
    var sheet: WordSheet?
    
    init(
        id: UUID = UUID(),
        term: String,
        definition: String,
        partOfSpeech: String,
        pronunciation: String,
        example: String,
        exampleCn: String,
        root: String = "",
        synonyms: String = "",
        antonyms: String = "",
        learned: Bool = false,
        reviewCount: Int = 0,
        lastReviewed: Date? = nil,
        spacedReviewCount: Int = 0,
        spacedLastReviewed: Date? = nil,
        createdAt: Date = Date(),
        sheet: WordSheet? = nil
    ) {
        self.id = id
        self.term = term
        self.definition = definition
        self.partOfSpeech = partOfSpeech
        self.pronunciation = pronunciation
        self.example = example
        self.exampleCn = exampleCn
        self.root = root
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.learned = learned
        self.reviewCount = reviewCount
        self.lastReviewed = lastReviewed
        self.spacedReviewCount = spacedReviewCount
        self.spacedLastReviewed = spacedLastReviewed
        self.createdAt = createdAt
        self.sheet = sheet
    }
}

// MARK: - 推荐复习（艾宾浩斯间隔，学习 Tab 与习题 Tab 共用）
enum SpacedRepetition {
    /// 仅对已「记住了」的词；间隔只看「推荐复习」内累计（spacedLastReviewed / spacedReviewCount）
    static func dueWords(from words: [Word], now: Date = Date()) -> [Word] {
        let calendar = Calendar.current
        return words.filter { word in
            guard word.learned else { return false }
            guard let spacedLast = word.spacedLastReviewed else {
                return true
            }
            let daysSinceSpaced = calendar.dateComponents([.day], from: spacedLast, to: now).day ?? 0
            return daysSinceSpaced >= intervalDays(forSpacedCount: word.spacedReviewCount)
        }
    }
    
    /// `count` 为在推荐复习中累计「记住了」的次数
    static func intervalDays(forSpacedCount count: Int) -> Int {
        switch count {
        case 0: return 0
        case 1: return 1
        case 2: return 3
        case 3: return 7
        case 4: return 15
        case 5: return 30
        default: return 30
        }
    }
    
    static func emptyHintKey(for words: [Word]) -> LocalizedKey {
        if words.isEmpty { return .recommendedReviewEmptyNoWords }
        if !words.contains(where: \.learned) { return .recommendedReviewEmptyAllUnlearned }
        return .recommendedReviewEmptyNoDue
    }
}
