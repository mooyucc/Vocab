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
    
    @Relationship(deleteRule: .cascade, inverse: \Word.sheet)
    var words: [Word]?
    
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
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

// MARK: - 词汇能量（进度页与学习 tab 顶栏共用同一算法）
enum VocabularyEnergy {
    /// 已掌握词数 × 40 + min(全库复习次数之和, 400)
    static func totalPoints(for words: [Word]) -> Int {
        let mastered = words.filter(\.learned).count
        let reviewSum = words.reduce(0) { $0 + $1.reviewCount }
        return mastered * 40 + min(reviewSum, 400)
    }
}
