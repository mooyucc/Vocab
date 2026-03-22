//
//  SheetPickerView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import SwiftData

struct SheetPickerView: View {
    let sheets: [WordSheet]
    @Binding var selectedSheetIds: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: {
                        selectedSheetIds.removeAll()
                        dismiss()
                    }) {
                        HStack {
                            Text(LocalizedKey.allSheets)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedSheetIds.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                
                Section {
                    ForEach(sheets) { sheet in
                        Button(action: {
                            if selectedSheetIds.contains(sheet.id) {
                                selectedSheetIds.remove(sheet.id)
                            } else {
                                selectedSheetIds.insert(sheet.id)
                            }
                        }) {
                            HStack {
                                Text(sheet.localizedDisplayName)
                                    .foregroundStyle(.primary)
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
            .navigationTitle(LocalizedKey.selectWordSheet.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(LocalizedKey.done.rawValue.localized) {
                        dismiss()
                    }
                }
            }
        }
    }
}
