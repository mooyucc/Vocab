//
//  WordSheetService.swift
//  Vocab
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

enum WordSheetAppearance {
    static let symbols: [String] = [
        "book.closed",
        "book.fill",
        "bookmark.fill",
        "star.fill",
        "graduationcap.fill",
        "briefcase.fill",
        "globe",
        "heart.fill",
        "flag.fill",
        "folder.fill",
        "tray.full.fill",
        "text.book.closed.fill"
    ]
    
    static let colorNames: [String] = [
        "accent", "blue", "green", "orange", "red", "purple", "pink", "teal", "indigo", "gray"
    ]
    
    static func color(named name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "gray": return .gray
        default: return .vocabBrand
        }
    }
}

enum VocabHaptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

enum WordSheetDuplicatePolicy {
    case keepBetterProgress
    case keepBoth
}

enum WordListFilter: String, CaseIterable, Identifiable {
    case grouped
    case unlearned
    case dueReview
    case byMonth
    
    var id: String { rawValue }
    
    var titleKey: LocalizedKey {
        switch self {
        case .grouped: return .libraryFilterGrouped
        case .unlearned: return .libraryFilterUnlearned
        case .dueReview: return .libraryFilterDue
        case .byMonth: return .libraryFilterByMonth
        }
    }
    
    var systemImage: String {
        switch self {
        case .grouped: return "square.stack.3d.up"
        case .unlearned: return "circle"
        case .dueReview: return "clock.arrow.circlepath"
        case .byMonth: return "calendar"
        }
    }
}

enum WordSheetService {
    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private static let chineseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
    
    private static let englishDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()
    
    static func isoDateString(from date: Date) -> String {
        isoFormatter.string(from: date)
    }
    
    static func parsedDate(fromName name: String) -> Date? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return isoFormatter.date(from: trimmed)
            ?? chineseDateFormatter.date(from: trimmed)
            ?? englishDateFormatter.date(from: trimmed)
    }
    
    static func looksLikeDateName(_ name: String) -> Bool {
        name.contains("年") || name.contains("月") || name.contains("日") ||
        name.contains("January") || name.contains("February") || name.contains("March") ||
        name.contains("April") || name.contains("May") || name.contains("June") ||
        name.contains("July") || name.contains("August") || name.contains("September") ||
        name.contains("October") || name.contains("November") || name.contains("December") ||
        name.contains("一月") || name.contains("二月") || name.contains("三月") ||
        name.contains("四月") || name.contains("五月") || name.contains("六月") ||
        name.contains("七月") || name.contains("八月") || name.contains("九月") ||
        name.contains("十月") || name.contains("十一月") || name.contains("十二月")
    }
    
    static func canonicalKey(forName name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = parsedDate(fromName: trimmed) {
            return isoDateString(from: date)
        }
        return trimmed
    }
    
    static func normalizedTerm(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    
    static func progressScore(for word: Word) -> Int {
        (word.learned ? 1000 : 0) + word.spacedReviewCount * 10 + word.reviewCount
    }
    
    static func sortedSheets(_ sheets: [WordSheet]) -> [WordSheet] {
        sheets.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.createdAt > b.createdAt
        }
    }
    
    static func findTodaySheet(in sheets: [WordSheet]) -> WordSheet? {
        let todayKey = isoDateString(from: Date())
        return sheets.first(where: { canonicalKey(forName: $0.name) == todayKey })
    }
    
    static func findOrCreateTodaySheet(in sheets: [WordSheet], context: ModelContext) -> WordSheet {
        if let existing = findTodaySheet(in: sheets) {
            return existing
        }
        let newSheet = WordSheet(name: isoDateString(from: Date()))
        context.insert(newSheet)
        try? context.save()
        return newSheet
    }
    
    static func existingSheet(named name: String, in sheets: [WordSheet], excluding id: UUID? = nil) -> WordSheet? {
        let key = canonicalKey(forName: name)
        guard !key.isEmpty else { return nil }
        return sheets.first { sheet in
            sheet.id != id && canonicalKey(forName: sheet.name) == key
        }
    }
    
    static func nextSortOrder(for sheets: [WordSheet]) -> Int {
        (sheets.map(\.sortOrder).min() ?? 0) - 1
    }
    
    @discardableResult
    static func createSheet(
        name: String,
        symbolName: String,
        colorName: String,
        isPinned: Bool,
        in sheets: [WordSheet],
        context: ModelContext
    ) -> WordSheet {
        let sheet = WordSheet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sortOrder: nextSortOrder(for: sheets),
            isPinned: isPinned,
            symbolName: symbolName,
            colorName: colorName
        )
        context.insert(sheet)
        try? context.save()
        return sheet
    }
    
    static func duplicateCount(merging sources: [WordSheet], into target: WordSheet) -> Int {
        var terms = Set((target.words ?? []).map { normalizedTerm($0.term) })
        var count = 0
        for source in sources where source.id != target.id {
            for word in source.words ?? [] {
                let key = normalizedTerm(word.term)
                if terms.contains(key) {
                    count += 1
                } else {
                    terms.insert(key)
                }
            }
        }
        return count
    }
    
    static func duplicateCount(moving words: [Word], to target: WordSheet) -> Int {
        let incoming = words.filter { $0.sheet?.id != target.id }
        let targetTerms = Set((target.words ?? []).map { normalizedTerm($0.term) })
        return incoming.filter { targetTerms.contains(normalizedTerm($0.term)) }.count
    }
    
    static func merge(
        sources: [WordSheet],
        into target: WordSheet,
        policy: WordSheetDuplicatePolicy,
        context: ModelContext
    ) {
        for source in sources where source.id != target.id {
            let toMove = Array(source.words ?? [])
            for word in toMove {
                word.sheet = target
            }
            context.delete(source)
        }
        if policy == .keepBetterProgress {
            resolveDuplicates(in: target, context: context)
        }
        try? context.save()
    }
    
    static func merge(
        source: WordSheet,
        into target: WordSheet,
        policy: WordSheetDuplicatePolicy,
        context: ModelContext
    ) {
        merge(sources: [source], into: target, policy: policy, context: context)
    }
    
    static func move(
        words: [Word],
        to target: WordSheet,
        policy: WordSheetDuplicatePolicy,
        context: ModelContext
    ) {
        let incoming = words.filter { $0.sheet?.id != target.id }
        let targetTerms = Set((target.words ?? []).map { normalizedTerm($0.term) })
        
        for word in incoming {
            let key = normalizedTerm(word.term)
            if targetTerms.contains(key) {
                switch policy {
                case .keepBoth:
                    word.sheet = target
                case .keepBetterProgress:
                    if let existing = (target.words ?? []).first(where: { normalizedTerm($0.term) == key }) {
                        if progressScore(for: word) > progressScore(for: existing) {
                            word.sheet = target
                            context.delete(existing)
                        } else {
                            context.delete(word)
                        }
                    } else {
                        word.sheet = target
                    }
                }
            } else {
                word.sheet = target
            }
        }
        try? context.save()
    }
    
    static func resolveDuplicates(in target: WordSheet, context: ModelContext) {
        var grouped: [String: [Word]] = [:]
        for word in Array(target.words ?? []) {
            grouped[normalizedTerm(word.term), default: []].append(word)
        }
        for group in grouped.values where group.count > 1 {
            let ranked = group.sorted { lhs, rhs in
                let ls = progressScore(for: lhs)
                let rs = progressScore(for: rhs)
                if ls != rs { return ls > rs }
                return lhs.createdAt < rhs.createdAt
            }
            for extra in ranked.dropFirst() {
                context.delete(extra)
            }
        }
    }
    
    static func applySortOrder(pinned: [WordSheet], unpinned: [WordSheet]) {
        for (index, sheet) in pinned.enumerated() {
            sheet.isPinned = true
            sheet.sortOrder = index
        }
        for (index, sheet) in unpinned.enumerated() {
            sheet.isPinned = false
            sheet.sortOrder = index
        }
    }
}

extension WordSheet {
    var localizedDisplayName: String {
        if let date = WordSheetService.parsedDate(fromName: name) {
            return DateFormatter.localizedDateString(from: date)
        }
        if WordSheetService.looksLikeDateName(name) {
            return DateFormatter.localizedDateString(from: createdAt)
        }
        return name
    }
    
    var displaySymbolName: String {
        symbolName.isEmpty ? "book.closed" : symbolName
    }
    
    var tintColor: Color {
        WordSheetAppearance.color(named: colorName.isEmpty ? "accent" : colorName)
    }
}
