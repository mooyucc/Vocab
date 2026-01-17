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
    @Binding var selectedSheetId: UUID?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: {
                        selectedSheetId = nil
                        dismiss()
                    }) {
                        HStack {
                            Text(LocalizedKey.allSheets)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedSheetId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
                
                Section {
                    ForEach(sheets) { sheet in
                        Button(action: {
                            selectedSheetId = sheet.id
                            dismiss()
                        }) {
                            HStack {
                                Text(sheet.localizedDisplayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedSheetId == sheet.id {
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
        }
    }
}
