//
//  SpeechManager.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import Foundation
import AVFoundation
import Combine

/// 语音播放管理器
/// 使用 AVSpeechSynthesizer 播放单词读音
class SpeechManager: ObservableObject {
    static let shared = SpeechManager()
    
    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking = false
    private var currentUtterance: AVSpeechUtterance?
    private var delegate: SpeechSynthesizerDelegate?
    
    private init() {
        // 配置合成器代理
        let delegate = SpeechSynthesizerDelegate { [weak self] in
            Task { @MainActor in
                self?.didStartSpeaking()
            }
        } onFinish: { [weak self] in
            Task { @MainActor in
                self?.didFinishSpeaking()
            }
        }
        synthesizer.delegate = delegate
        self.delegate = delegate
    }
    
    /// 播放单词读音
    /// - Parameters:
    ///   - text: 要播放的文本（通常是单词）
    ///   - language: 语言代码，默认为 "en-US"（英语）
    @MainActor
    func speak(_ text: String, language: String = "en-US") {
        // 如果正在播放，先停止
        if isSpeaking {
            stopSpeaking()
        }
        
        // 创建语音合成话语
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // 保存当前话语引用
        currentUtterance = utterance
        
        // 开始播放
        synthesizer.speak(utterance)
        isSpeaking = true
    }
    
    /// 停止播放
    @MainActor
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        currentUtterance = nil
    }
    
    /// 暂停播放
    @MainActor
    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .immediate)
    }
    
    /// 继续播放
    @MainActor
    func continueSpeaking() {
        synthesizer.continueSpeaking()
    }
    
    /// 当播放开始时的回调
    @MainActor
    private func didStartSpeaking() {
        isSpeaking = true
    }
    
    /// 当播放完成或取消时的回调
    @MainActor
    private func didFinishSpeaking() {
        isSpeaking = false
        currentUtterance = nil
    }
}

/// AVSpeechSynthesizer 代理实现
private class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let onStart: () -> Void
    private let onFinish: () -> Void
    
    init(onStart: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.onStart = onStart
        self.onFinish = onFinish
        super.init()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStart()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}
