//
//  ImageCropView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI

// 扩展：归一化图片方向（将任何方向转换为 .up）
extension UIImage {
    /// 归一化图片方向，将图片旋转/翻转为标准方向（.up）
    /// 这对于裁剪和文字识别非常重要，确保坐标系统一致
    func normalized() -> UIImage {
        // 如果已经是 .up 方向，无需处理
        if imageOrientation == .up {
            return self
        }
        
        // 创建图形上下文，尺寸使用 self.size（已考虑方向）
        // 这确保归一化后的图片尺寸与显示尺寸一致
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        // 在上下文中绘制图片，系统会自动应用 orientation 变换
        // 绘制后的像素数据就是标准方向的
        draw(in: CGRect(origin: .zero, size: size))
        
        guard let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            // 如果归一化失败，返回原图
            return self
        }
        
        return normalizedImage
    }
}

struct ImageCropView: View {
    let image: UIImage
    @Binding var isPresented: Bool
    let onCropSelected: (UIImage) -> Void
    
    private let minCropSize: CGFloat = 30  // 选框最小尺寸
    
    @State private var cropRect: CGRect = .zero
    @State private var imageSize: CGSize = .zero
    @State private var displaySize: CGSize = .zero
    @State private var isSelecting: Bool = false
    @State private var startPoint: CGPoint = .zero
    @State private var currentRect: CGRect = .zero
    @State private var showFullImageOption: Bool = true
    @State private var dragMode: DragMode = .none
    @State private var initialCropRect: CGRect = .zero
    
    enum DragMode {
        case none
        case creating  // 正在创建新选框
        case moving    // 正在移动选框
        case resizing(ResizeCorner)  // 正在调整大小
        
        enum ResizeCorner {
            case topLeft, topRight, bottomLeft, bottomRight
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                GeometryReader { geometry in
                    let size = geometry.size
                    
                    ZStack {
                        // 显示图片
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onAppear {
                                displaySize = size
                                imageSize = image.size
                                calculateInitialCropRect(in: size)
                            }
                            .onChange(of: size) { oldValue, newValue in
                                displaySize = newValue
                                calculateInitialCropRect(in: newValue)
                            }
                        
                        // 裁剪区域覆盖层
                        CropOverlayView(
                            cropRect: currentRect.isEmpty ? cropRect : currentRect,
                            imageSize: imageSize,
                            displaySize: displaySize
                        )
                        
                        // 手势识别
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let imageFrame = getImageFrame(in: size)
                                        
                                        if case .none = dragMode {
                                            // 检测触摸点位置
                                            dragMode = detectDragMode(at: value.startLocation, cropRect: cropRect, imageFrame: imageFrame)
                                            startPoint = value.startLocation
                                            initialCropRect = cropRect
                                        }
                                        
                                        switch dragMode {
                                        case .none:
                                            break
                                        case .creating:
                                            // 创建新选框
                                            let rect = CGRect(
                                                x: min(startPoint.x, value.location.x),
                                                y: min(startPoint.y, value.location.y),
                                                width: abs(value.location.x - startPoint.x),
                                                height: abs(value.location.y - startPoint.y)
                                            )
                                            currentRect = rect.intersection(imageFrame)
                                            
                                        case .moving:
                                            // 移动选框
                                            let deltaX = value.location.x - startPoint.x
                                            let deltaY = value.location.y - startPoint.y
                                            var newRect = initialCropRect
                                            newRect.origin.x += deltaX
                                            newRect.origin.y += deltaY
                                            
                                            // 限制在图片范围内
                                            newRect.origin.x = max(imageFrame.minX, min(newRect.origin.x, imageFrame.maxX - newRect.width))
                                            newRect.origin.y = max(imageFrame.minY, min(newRect.origin.y, imageFrame.maxY - newRect.height))
                                            
                                            currentRect = newRect
                                            
                                        case .resizing(let corner):
                                            // 调整大小
                                            var newRect = initialCropRect
                                            let deltaX = value.location.x - startPoint.x
                                            let deltaY = value.location.y - startPoint.y
                                            
                                            switch corner {
                                            case .topLeft:
                                                newRect.origin.x = min(initialCropRect.origin.x + deltaX, initialCropRect.maxX - minCropSize)
                                                newRect.origin.y = min(initialCropRect.origin.y + deltaY, initialCropRect.maxY - minCropSize)
                                                newRect.size.width = initialCropRect.maxX - newRect.origin.x
                                                newRect.size.height = initialCropRect.maxY - newRect.origin.y
                                                
                                            case .topRight:
                                                newRect.origin.y = min(initialCropRect.origin.y + deltaY, initialCropRect.maxY - minCropSize)
                                                newRect.size.width = max(minCropSize, initialCropRect.width + deltaX)
                                                newRect.size.height = initialCropRect.maxY - newRect.origin.y
                                                
                                            case .bottomLeft:
                                                newRect.origin.x = min(initialCropRect.origin.x + deltaX, initialCropRect.maxX - minCropSize)
                                                newRect.size.width = initialCropRect.maxX - newRect.origin.x
                                                newRect.size.height = max(minCropSize, initialCropRect.height + deltaY)
                                                
                                            case .bottomRight:
                                                newRect.size.width = max(minCropSize, initialCropRect.width + deltaX)
                                                newRect.size.height = max(minCropSize, initialCropRect.height + deltaY)
                                            }
                                            
                                            // 限制在图片范围内
                                            if newRect.minX < imageFrame.minX {
                                                newRect.size.width -= (imageFrame.minX - newRect.minX)
                                                newRect.origin.x = imageFrame.minX
                                            }
                                            if newRect.minY < imageFrame.minY {
                                                newRect.size.height -= (imageFrame.minY - newRect.minY)
                                                newRect.origin.y = imageFrame.minY
                                            }
                                            if newRect.maxX > imageFrame.maxX {
                                                newRect.size.width = imageFrame.maxX - newRect.minX
                                            }
                                            if newRect.maxY > imageFrame.maxY {
                                                newRect.size.height = imageFrame.maxY - newRect.minY
                                            }
                                            
                                            currentRect = newRect
                                        }
                                    }
                                    .onEnded { _ in
                                        if !currentRect.isEmpty {
                                            cropRect = currentRect
                                        }
                                        dragMode = .none
                                        currentRect = .zero
                                    }
                            )
                    }
                }
                
                // 底部操作栏
                VStack {
                    Spacer()
                    
                    HStack(spacing: 20) {
                        // 识别整张图片按钮
                        Button(action: {
                            recognizeFullImage()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.fill")
                                    .font(.title2)
                                Text(LocalizedKey.recognizeFullImage.rawValue.localized)
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(12)
                        }
                        
                        // 识别选中区域按钮
                        Button(action: {
                            recognizeSelectedRegion()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "crop")
                                    .font(.title2)
                                Text(LocalizedKey.recognizeSelectedRegion.rawValue.localized)
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(cropRect.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                            .cornerRadius(12)
                        }
                        .disabled(cropRect.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(LocalizedKey.selectRecognitionRegion.rawValue.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(LocalizedKey.cancel.rawValue.localized) {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    private func calculateInitialCropRect(in size: CGSize) {
        // 初始不选择任何区域，让用户手动选择
        cropRect = .zero
    }
    
    // 检测拖动模式：创建、移动或调整大小
    private func detectDragMode(at point: CGPoint, cropRect: CGRect, imageFrame: CGRect) -> DragMode {
        guard !cropRect.isEmpty else {
            // 如果没有选框，检查是否在图片范围内
            if imageFrame.contains(point) {
                return .creating
            }
            return .none
        }
        
        let cornerSize: CGFloat = 30  // 角部触摸区域大小
        
        // 检查是否在四个角上
        let corners = [
            (CGPoint(x: cropRect.minX, y: cropRect.minY), DragMode.ResizeCorner.topLeft),
            (CGPoint(x: cropRect.maxX, y: cropRect.minY), DragMode.ResizeCorner.topRight),
            (CGPoint(x: cropRect.minX, y: cropRect.maxY), DragMode.ResizeCorner.bottomLeft),
            (CGPoint(x: cropRect.maxX, y: cropRect.maxY), DragMode.ResizeCorner.bottomRight)
        ]
        
        for (corner, resizeCorner) in corners {
            let cornerRect = CGRect(
                x: corner.x - cornerSize / 2,
                y: corner.y - cornerSize / 2,
                width: cornerSize,
                height: cornerSize
            )
            if cornerRect.contains(point) {
                return .resizing(resizeCorner)
            }
        }
        
        // 检查是否在选框内部（移动）
        if cropRect.contains(point) {
            return .moving
        }
        
        // 在选框外部，创建新选框
        if imageFrame.contains(point) {
            return .creating
        }
        
        return .none
    }
    
    private func getImageFrame(in containerSize: CGSize) -> CGRect {
        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height
        
        var frame: CGRect
        
        if imageAspectRatio > containerAspectRatio {
            // 图片更宽，以宽度为准
            let height = containerSize.width / imageAspectRatio
            let y = (containerSize.height - height) / 2
            frame = CGRect(x: 0, y: y, width: containerSize.width, height: height)
        } else {
            // 图片更高，以高度为准
            let width = containerSize.height * imageAspectRatio
            let x = (containerSize.width - width) / 2
            frame = CGRect(x: x, y: 0, width: width, height: containerSize.height)
        }
        
        return frame
    }
    
    private func recognizeFullImage() {
        // 归一化图片方向，确保与裁剪场景一致
        // 这样可以保证所有识别场景都使用相同的处理方式，提高识别准确性
        let normalizedImage = image.normalized()
        onCropSelected(normalizedImage)
        isPresented = false
    }
    
    private func recognizeSelectedRegion() {
        guard !cropRect.isEmpty else { return }
        
        // 将显示坐标转换为图片坐标
        let imageFrame = getImageFrame(in: displaySize)
        let normalizedRect = CGRect(
            x: (cropRect.origin.x - imageFrame.origin.x) / imageFrame.width,
            y: (cropRect.origin.y - imageFrame.origin.y) / imageFrame.height,
            width: cropRect.width / imageFrame.width,
            height: cropRect.height / imageFrame.height
        )
        
        // 裁剪图片
        if let croppedImage = cropImage(image, to: normalizedRect) {
            onCropSelected(croppedImage)
        } else {
            // 如果裁剪失败，使用整张图片
            onCropSelected(image)
        }
        
        isPresented = false
    }
    
    private func cropImage(_ image: UIImage, to normalizedRect: CGRect) -> UIImage? {
        // 关键问题：当图片有方向信息（如 .right, .left）时，
        // image.size 会根据方向自动调整宽高（交换），但 cgImage.width/height 是原始像素尺寸
        // 用户选择的区域是基于 image.size（显示尺寸），但裁剪使用的是 cgImage 尺寸
        // 解决方案：先将图片归一化为 .up 方向，确保显示尺寸和像素尺寸一致
        
        // 归一化图片方向（确保 orientation = .up）
        let normalizedImage = image.normalized()
        guard let normalizedCGImage = normalizedImage.cgImage else { return nil }
        
        // 使用归一化后的图片尺寸计算裁剪区域
        // 这样 normalizedRect 的坐标就与像素坐标一致了
        let x = normalizedRect.origin.x * CGFloat(normalizedCGImage.width)
        let y = normalizedRect.origin.y * CGFloat(normalizedCGImage.height)
        let width = normalizedRect.width * CGFloat(normalizedCGImage.width)
        let height = normalizedRect.height * CGFloat(normalizedCGImage.height)
        
        let rect = CGRect(x: x, y: y, width: width, height: height)
        
        guard let croppedCGImage = normalizedCGImage.cropping(to: rect) else { return nil }
        
        // 裁剪后的图片已经是 .up 方向，不需要保留原始方向信息
        return UIImage(cgImage: croppedCGImage, scale: normalizedImage.scale, orientation: .up)
    }
}

struct CropOverlayView: View {
    let cropRect: CGRect
    let imageSize: CGSize
    let displaySize: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 半透明遮罩
                Color.black.opacity(0.5)
                    .mask(
                        Rectangle()
                            .fill(Color.white)
                            .overlay(
                                Rectangle()
                                    .fill(Color.black)
                                    .frame(width: cropRect.width, height: cropRect.height)
                                    .position(x: cropRect.midX, y: cropRect.midY)
                                    .blendMode(.destinationOut)
                            )
                    )
                
                // 选择框边框
                if !cropRect.isEmpty {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: cropRect.width, height: cropRect.height)
                        .position(x: cropRect.midX, y: cropRect.midY)
                    
                    // 四个角的调节手柄（更大，更容易拖动）
                    ForEach(0..<4) { index in
                        let corner = getCornerPoint(for: index)
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 20, height: 20)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 12, height: 12)
                        }
                        .position(corner)
                    }
                }
            }
        }
    }
    
    private func getCornerPoint(for index: Int) -> CGPoint {
        switch index {
        case 0: return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case 1: return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case 2: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        case 3: return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        default: return .zero
        }
    }
}
