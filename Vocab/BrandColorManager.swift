//
//  BrandColorManager.swift
//  Vocab
//
//  品牌颜色管理器，用于管理品牌颜色
//

import SwiftUI
import Combine

/// 品牌颜色管理器
class BrandColorManager: ObservableObject {
    static let shared = BrandColorManager()
    
    /// 默认品牌颜色（蓝色，适合学习应用）
    let defaultBrandColor = Color.blue
    
    /// 当前品牌颜色（可观察属性，变化时自动通知所有视图）
    @Published var currentBrandColor: Color
    
    private init() {
        self.currentBrandColor = defaultBrandColor
    }
}
