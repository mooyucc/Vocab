//
//  TextRecognitionService.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import Foundation
import Vision
import UIKit
import CoreGraphics

class TextRecognitionService {
    static let shared = TextRecognitionService()
    
    private init() {}
    
    /// 从图片中识别文字，返回识别到的单词列表
    /// - Parameters:
    ///   - image: 要识别的图片
    ///   - region: 可选，指定识别的区域（相对于图片的归一化坐标，0-1范围）
    /// - Returns: 识别到的单词数组（已去重和清理）
    func recognizeWords(from image: UIImage, in region: CGRect? = nil) async throws -> [String] {
        // 确保图片方向正确：如果图片有方向信息，需要先转换为正确方向的 CGImage
        // 或者直接将 UIImage.Orientation 转换为 CGImagePropertyOrientation 传递给 Vision
        guard let cgImage = image.cgImage else {
            throw TextRecognitionError.invalidImage
        }
        
        // 将 UIImage.Orientation 转换为 CGImagePropertyOrientation
        // 这对 Vision 框架正确识别文字至关重要，特别是从相机拍摄的照片
        let cgOrientation = CGImagePropertyOrientation(image.imageOrientation)
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: TextRecognitionError.recognitionFailed(error))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                // 提取所有识别到的文字
                var allWords: Set<String> = []
                
                for observation in observations {
                    // 如果指定了区域，检查观察结果是否在区域内
                    if let region = region {
                        let observationRect = observation.boundingBox
                        // Vision 框架使用归一化坐标（0-1），且原点在左下角
                        // 需要转换为左上角为原点的坐标系统
                        let normalizedRect = CGRect(
                            x: observationRect.origin.x,
                            y: 1 - observationRect.origin.y - observationRect.height,
                            width: observationRect.width,
                            height: observationRect.height
                        )
                        
                        // 检查观察结果是否与指定区域有交集
                        if !normalizedRect.intersects(region) {
                            continue
                        }
                    }
                    
                    guard let topCandidate = observation.topCandidates(1).first else {
                        continue
                    }
                    
                    let text = topCandidate.string
                    // 按单词分割（支持英文单词）
                    // 使用更灵活的单词分割方式，支持各种标点符号
                    let words = text.components(separatedBy: CharacterSet.letters.inverted)
                        .filter { !$0.isEmpty }
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .map { $0.lowercased() } // 统一转换为小写，便于去重
                        .filter { word in
                            // 过滤条件：只保留看起来像英文单词的文本
                            // 至少2个字符，只包含字母（已转换为小写）
                            word.count >= 2 && word.allSatisfy { $0.isLetter }
                        }
                    
                    allWords.formUnion(words)
                }
                
                // 转换为数组并排序
                let sortedWords = Array(allWords).sorted()
                continuation.resume(returning: sortedWords)
            }
            
            // 配置识别请求
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"] // 支持英文识别
            request.usesLanguageCorrection = true
            
            // 如果指定了区域，设置识别区域
            if let region = region {
                // Vision 框架使用归一化坐标（0-1），且原点在左下角
                // 需要将左上角为原点的坐标转换为左下角为原点的坐标
                let visionRegion = CGRect(
                    x: region.origin.x,
                    y: 1 - region.origin.y - region.height,
                    width: region.width,
                    height: region.height
                )
                request.regionOfInterest = visionRegion
            }
            
            // 执行识别 - 重要：传递正确的方向信息给 Vision 框架
            // 这确保 Vision 框架能正确解释图片的方向，特别是从相机拍摄的照片
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation, options: [:])
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: TextRecognitionError.processingFailed(error))
                }
            }
        }
    }
}

// 扩展：将 UIImage.Orientation 转换为 CGImagePropertyOrientation
extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

enum TextRecognitionError: LocalizedError {
    case invalidImage
    case recognitionFailed(Error)
    case processingFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return LocalizedKey.invalidImage.rawValue.localized
        case .recognitionFailed(let error):
            return String(format: LocalizedKey.recognitionFailed.rawValue.localized, error.localizedDescription)
        case .processingFailed(let error):
            return String(format: LocalizedKey.processingFailed.rawValue.localized, error.localizedDescription)
        }
    }
}
