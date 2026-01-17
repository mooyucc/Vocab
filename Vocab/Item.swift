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
    var learned: Bool = false
    var reviewCount: Int = 0
    var lastReviewed: Date?
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
        learned: Bool = false,
        reviewCount: Int = 0,
        lastReviewed: Date? = nil,
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
        self.learned = learned
        self.reviewCount = reviewCount
        self.lastReviewed = lastReviewed
        self.createdAt = createdAt
        self.sheet = sheet
    }
}
