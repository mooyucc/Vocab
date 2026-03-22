//
//  SheetSelectionView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

struct SheetSelectionView: View {
    @Query(sort: \WordSheet.createdAt, order: .reverse) private var allSheets: [WordSheet]
    @Query private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedSheetIds: Set<UUID> = []
    let onConfirm: (Set<UUID>) -> Void
    
    private var sheetsWithWords: [WordSheet] {
        allSheets.filter { sheet in
            words.contains { $0.sheet?.id == sheet.id }
        }
    }
    
    private var allSelected: Bool {
        !sheetsWithWords.isEmpty && selectedSheetIds.count == sheetsWithWords.count
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: {
                        if allSelected {
                            selectedSheetIds.removeAll()
                        } else {
                            selectedSheetIds = Set(sheetsWithWords.map { $0.id })
                        }
                    }) {
                        HStack {
                            Text(allSelected ? LocalizedKey.deselectAll.rawValue.localized : LocalizedKey.selectAll.rawValue.localized)
                                .foregroundStyle(.primary)
                            Spacer()
                            if allSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                
                Section {
                    ForEach(sheetsWithWords) { sheet in
                        Button(action: {
                            if selectedSheetIds.contains(sheet.id) {
                                selectedSheetIds.remove(sheet.id)
                            } else {
                                selectedSheetIds.insert(sheet.id)
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sheet.localizedDisplayName)
                                        .foregroundStyle(.primary)
                                    Text(String(format: "%d %@", words.filter { $0.sheet?.id == sheet.id }.count, LocalizedKey.word.rawValue.localized))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedSheetIds.contains(sheet.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(LocalizedKey.selectSheetsToExport.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(LocalizedKey.cancel.rawValue.localized) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LocalizedKey.confirm.rawValue.localized) {
                        onConfirm(selectedSheetIds)
                        dismiss()
                    }
                    .disabled(selectedSheetIds.isEmpty)
                }
            }
        }
    }
}
