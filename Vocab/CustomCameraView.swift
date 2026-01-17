//
//  CustomCameraView.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import SwiftUI
import AVFoundation
import UIKit

struct CustomCameraView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> CustomCameraViewController {
        let controller = CustomCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CustomCameraViewController, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CustomCameraViewControllerDelegate {
        let parent: CustomCameraView
        
        init(_ parent: CustomCameraView) {
            self.parent = parent
        }
        
        func didCaptureImage(_ image: UIImage) {
            parent.selectedImage = image
            parent.isPresented = false
        }
        
        func didSelectImageFromAlbum(_ image: UIImage) {
            parent.selectedImage = image
            parent.isPresented = false
        }
        
        func didCancel() {
            parent.isPresented = false
        }
    }
}

protocol CustomCameraViewControllerDelegate: AnyObject {
    func didCaptureImage(_ image: UIImage)
    func didSelectImageFromAlbum(_ image: UIImage)
    func didCancel()
}

class CustomCameraViewController: UIViewController {
    weak var delegate: CustomCameraViewControllerDelegate?
    
    private var captureSession: AVCaptureSession!
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private var photoOutput: AVCapturePhotoOutput!
    private var innerCircle: UIView?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.stopRunning()
            }
        }
    }
    
    private func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                return
            }
            
            photoOutput = AVCapturePhotoOutput()
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
            
            setupUI()
            
        } catch {
            print("相机设置失败: \(error)")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        // 底部控制栏
        let bottomBar = UIView()
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        
        // 拍照按钮 - iPhone 相机样式
        let captureButton = UIButton(type: .custom)
        captureButton.backgroundColor = .clear
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        
        // 创建外环（深灰色，类似 iPhone 原生相机）
        let outerCircle = UIView()
        outerCircle.backgroundColor = .clear
        outerCircle.layer.borderWidth = 6
        outerCircle.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        outerCircle.layer.cornerRadius = 38
        outerCircle.translatesAutoresizingMaskIntoConstraints = false
        outerCircle.isUserInteractionEnabled = false  // 不拦截触摸事件
        captureButton.addSubview(outerCircle)
        
        // 创建内部白色圆圈
        let innerCircle = UIView()
        innerCircle.backgroundColor = .white
        innerCircle.layer.cornerRadius = 32
        innerCircle.translatesAutoresizingMaskIntoConstraints = false
        innerCircle.isUserInteractionEnabled = false  // 不拦截触摸事件
        captureButton.addSubview(innerCircle)
        self.innerCircle = innerCircle
        
        bottomBar.addSubview(captureButton)
        
        // 取消按钮
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 18)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(cancelButton)
        
        // 相册按钮
        let albumButton = UIButton(type: .system)
        let albumImage = UIImage(systemName: "photo.on.rectangle")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        )
        albumButton.setImage(albumImage, for: .normal)
        albumButton.tintColor = .white
        albumButton.addTarget(self, action: #selector(showPhotoLibrary), for: .touchUpInside)
        albumButton.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(albumButton)
        
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 100),
            
            captureButton.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            captureButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: 76),
            captureButton.heightAnchor.constraint(equalToConstant: 76),
            
            outerCircle.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            outerCircle.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            outerCircle.widthAnchor.constraint(equalToConstant: 76),
            outerCircle.heightAnchor.constraint(equalToConstant: 76),
            
            innerCircle.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            innerCircle.widthAnchor.constraint(equalToConstant: 64),
            innerCircle.heightAnchor.constraint(equalToConstant: 64),
            
            cancelButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            
            albumButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            albumButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            albumButton.widthAnchor.constraint(equalToConstant: 44),
            albumButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    @objc private func capturePhoto() {
        // 检查 photoOutput 是否可用
        guard let photoOutput = self.photoOutput, captureSession.isRunning else {
            print("相机未就绪，无法拍照")
            return
        }
        
        // 添加点击动画效果 - iPhone 相机按钮样式
        UIView.animate(withDuration: 0.1, animations: {
            self.innerCircle?.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        }) { _ in
            UIView.animate(withDuration: 0.1, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
                self.innerCircle?.transform = .identity
            }
        }
        
        // 在主线程上执行拍照（AVCapturePhotoOutput 需要在主线程调用）
        let settings: AVCapturePhotoSettings
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        
        // 启用高分辨率照片以提高 OCR 识别质量
        if photoOutput.isHighResolutionCaptureEnabled {
            settings.isHighResolutionPhotoEnabled = true
        }
        
        // 启用嵌入式缩略图（可选，不影响主图质量）
        settings.embeddedThumbnailPhotoFormat = nil
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    @objc private func cancel() {
        delegate?.didCancel()
    }
    
    @objc private func showPhotoLibrary() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }
}

extension CustomCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("拍照处理错误: \(error.localizedDescription)")
            return
        }
        
        // 优先使用 fileDataRepresentation() 获取完整图片数据（包含正确的方向信息）
        // fileDataRepresentation() 返回的 JPEG/HEIF 数据已经包含了正确的 EXIF 方向信息
        // UIImage(data:) 会自动根据 EXIF 信息设置 imageOrientation，确保方向正确
        if let imageData = photo.fileDataRepresentation(),
           let image = UIImage(data: imageData) {
            // fileDataRepresentation() 已经包含了完整的图片数据和元数据（包括方向）
            // UIImage(data:) 会自动处理 EXIF 方向，确保图片显示和识别时的方向正确
            delegate?.didCaptureImage(image)
        } else if let cgImage = photo.cgImageRepresentation() {
            // 备选方案：使用 cgImageRepresentation() + 正确的方向信息
            // 从 metadata 中正确获取方向信息
            var cgOrientation: CGImagePropertyOrientation = .up
            if let orientationValue = photo.metadata[kCGImagePropertyOrientation as String] as? UInt32 {
                cgOrientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
            } else if let tiffOrientation = photo.metadata[kCGImagePropertyTIFFOrientation as String] as? UInt16 {
                // 有些情况下方向信息在 TIFF 标签中
                cgOrientation = CGImagePropertyOrientation(rawValue: UInt32(tiffOrientation)) ?? .up
            }
            
            // 将 CGImagePropertyOrientation 转换为 UIImage.Orientation
            let uiOrientation = UIImage.Orientation(cgOrientation)
            let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: uiOrientation)
            delegate?.didCaptureImage(image)
        } else {
            print("无法从照片中获取图片数据")
        }
    }
}

// 扩展：将 CGImagePropertyOrientation 转换为 UIImage.Orientation
extension UIImage.Orientation {
    init(_ cgOrientation: CGImagePropertyOrientation) {
        switch cgOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}

extension CustomCameraViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) {
            if let image = info[.originalImage] as? UIImage {
                self.delegate?.didSelectImageFromAlbum(image)
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
