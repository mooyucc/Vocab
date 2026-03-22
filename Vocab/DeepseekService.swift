//
//  DeepseekService.swift
//  Vocab
//
//  Created by 徐化军 on 2026/1/14.
//

import Foundation

struct WordDetails: Codable {
    let definition: String
    let partOfSpeech: String
    let pronunciation: String
    let example: String
    let exampleCn: String
    let root: String?
    let synonyms: String?
    let antonyms: String?
}

/// API调用错误
enum DeepseekServiceError: LocalizedError {
    case noRemainingCalls
    case apiKeyNotSet
    case invalidURL
    case apiRequestFailed(Int)
    case invalidResponse
    case jsonParsingFailed
    case exampleExtractionFailed
    
    var errorDescription: String? {
        switch self {
        case .noRemainingCalls:
            return "usage_no_calls_remaining".localized
        case .apiKeyNotSet:
            return "请先设置 API Key"
        case .invalidURL:
            return "无效的 URL"
        case .apiRequestFailed(let code):
            return "API 请求失败，状态码: \(code)"
        case .invalidResponse:
            return "无法解析 API 响应"
        case .jsonParsingFailed:
            return "无法解析 JSON"
        case .exampleExtractionFailed:
            return "无法从响应中提取例句"
        }
    }
}

class DeepseekService {
    static let shared = DeepseekService()
    
    // Deepseek API Key
    private var apiKey: String {
        // 优先从环境变量读取
        if let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty {
            return key
        }
        // 如果没有环境变量，使用直接设置的 API Key
        return "sk-f59687e9e0cf4d15941c964ed0c66414"
    }
    
    private let usageTracker = UsageTracker.shared
    
    private init() {}
    
    // 验证并确保不使用 deepseek-reasoner 模式
    private func validateModel(_ model: String) throws -> String {
        let lowercased = model.lowercased()
        if lowercased.contains("reasoner") {
            throw NSError(domain: "DeepseekService", code: 100, userInfo: [NSLocalizedDescriptionKey: "禁止使用 deepseek-reasoner 模式"])
        }
        return model
    }
    
    func generateWordDetails(for word: String) async throws -> WordDetails {
        // 检查是否有剩余调用次数
        guard usageTracker.hasRemainingCalls() else {
            throw DeepseekServiceError.noRemainingCalls
        }
        
        guard !apiKey.isEmpty else {
            throw DeepseekServiceError.apiKeyNotSet
        }
        
        let urlString = "https://api.deepseek.com/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw DeepseekServiceError.invalidURL
        }
        
        // 根据用户设置的学习语言和母语生成提示：
        // - 用户在“添加单词”页面输入（或拍照识别）的单词为「学习语言」单词
        // - AI 生成的释义与翻译应使用「母语」
        let settings = AppSettingsManager.shared
        let learningLanguage = settings.targetLanguage
        let nativeLanguage = settings.language
        
        func languageName(_ language: AppLanguage) -> String {
            switch language {
            case .chinese:
                return "Simplified Chinese"
            case .chineseTraditional:
                return "Traditional Chinese"
            case .english:
                return "English"
            case .japanese:
                return "Japanese"
            case .french:
                return "French"
            case .spanish:
                return "Spanish"
            case .korean:
                return "Korean"
            }
        }
        
        let learningLanguageName = languageName(learningLanguage)
        let nativeLanguageName = languageName(nativeLanguage)
        
        let prompt = """
        You are a vocabulary assistant.
        The learner's target (learning) language is \(learningLanguageName), and the learner's native language is \(nativeLanguageName).
        The word "\(word)" is written in \(learningLanguageName).
        Provide the following details in strictly valid JSON format:
        {
          "definition": "Concise explanation of the word in \(nativeLanguageName), suitable for learners",
          "partOfSpeech": "Part of speech for the word, using common abbreviations (e.g., n., v., adj.) in \(learningLanguageName) or English",
          "example": "A simple, common example sentence in \(learningLanguageName) that correctly uses the word",
          "exampleCn": "Translation of the example sentence written in \(nativeLanguageName)",
          "pronunciation": "IPA phonetic transcription for the word's pronunciation (e.g., /wɜːrd/)",
          "root": "Main word root or etymology described in \(learningLanguageName) or English (or empty string if not applicable)",
          "synonyms": "Common synonyms written in \(learningLanguageName), comma-separated (or empty string if none)",
          "antonyms": "Common antonyms written in \(learningLanguageName), comma-separated (or empty string if none)"
        }
        Do not include any explanation outside the JSON.
        Do not include markdown formatting (like ```json). Just return the raw JSON object.
        """
        
        let modelName = try validateModel("deepseek-chat")
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.7
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DeepseekServiceError.apiRequestFailed(statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw DeepseekServiceError.invalidResponse
        }
        
        // 清理可能的 markdown 格式
        let cleanText = text.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanText.data(using: .utf8) else {
            throw DeepseekServiceError.jsonParsingFailed
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(WordDetails.self, from: jsonData)
        
        // API调用成功，记录使用次数
        usageTracker.useCall()
        
        return result
    }
    
    // 生成每日激励语
    func generateDailyMotivation() async throws -> String {
        // 检查是否有剩余调用次数
        guard usageTracker.hasRemainingCalls() else {
            throw DeepseekServiceError.noRemainingCalls
        }
        
        guard !apiKey.isEmpty else {
            throw DeepseekServiceError.apiKeyNotSet
        }
        
        let urlString = "https://api.deepseek.com/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw DeepseekServiceError.invalidURL
        }
        
        // 根据当前语言设置生成对应的 prompt
        let currentLanguage = AppSettingsManager.shared.language
        let prompt: String
        
        if currentLanguage == .chinese {
            prompt = """
            请生成一句简短的中文激励语，用于鼓励用户学习英语单词。要求：
            1. 长度控制在15-20字以内
            2. 积极正面，充满正能量
            3. 与学习、成长、坚持相关
            4. 语言生动有趣
            5. 直接输出文字，不要加引号或其他格式
            
            例如："今天也要元气满满背单词 💪"、"坚持就是胜利，继续加油！"、"每一次努力，都是未来的自己 ✨"
            
            请生成一句新的激励语：
            """
        } else {
            prompt = """
            Please generate a short motivational sentence in English to encourage users to learn English vocabulary. Requirements:
            1. Keep it within 15-20 words
            2. Positive and uplifting
            3. Related to learning, growth, and persistence
            4. Vivid and interesting language
            5. Output text directly without quotes or other formatting
            
            Examples: "Stay motivated and learn vocabulary today 💪", "Keep going, you're doing great!", "Every effort counts for your future ✨"
            
            Please generate a new motivational sentence:
            """
        }
        
        let modelName = try validateModel("deepseek-chat")
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.9,
            "max_tokens": 100
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DeepseekServiceError.apiRequestFailed(statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              var text = message["content"] as? String else {
            throw DeepseekServiceError.invalidResponse
        }
        
        // 清理可能的格式
        text = text.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 如果为空，返回默认值
        if text.isEmpty {
            let currentLanguage = AppSettingsManager.shared.language
            if currentLanguage == .chinese {
                return LocalizedKey.dailyMotivation.rawValue.localized
            } else {
                return LocalizedKey.dailyMotivation.rawValue.localized
            }
        }
        
        // API调用成功，记录使用次数
        usageTracker.useCall()
        
        return text
    }
    
    // 生成新的例句
    func generateNewExample(for word: String, partOfSpeech: String, definition: String, currentExample: String? = nil) async throws -> (example: String, exampleCn: String) {
        // 检查是否有剩余调用次数
        guard usageTracker.hasRemainingCalls() else {
            throw DeepseekServiceError.noRemainingCalls
        }
        
        guard !apiKey.isEmpty else {
            throw DeepseekServiceError.apiKeyNotSet
        }
        
        let urlString = "https://api.deepseek.com/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw DeepseekServiceError.invalidURL
        }
        
        // 解析词性，支持多个词性（用空格、逗号或分号分隔）
        let partsOfSpeech = partOfSpeech
            .components(separatedBy: CharacterSet(charactersIn: " ,;，；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // 如果有多个词性，随机选择一个（或轮换）
        let selectedPartOfSpeech: String
        if partsOfSpeech.count > 1 {
            // 随机选择一个词性，增加多样性
            selectedPartOfSpeech = partsOfSpeech.randomElement() ?? partOfSpeech
        } else {
            selectedPartOfSpeech = partOfSpeech
        }
        
        // 根据当前设置获取学习语言和母语
        let settings = AppSettingsManager.shared
        let learningLanguage = settings.targetLanguage
        let nativeLanguage = settings.language
        
        func languageName(_ language: AppLanguage) -> String {
            switch language {
            case .chinese:
                return "Simplified Chinese"
            case .chineseTraditional:
                return "Traditional Chinese"
            case .english:
                return "English"
            case .japanese:
                return "Japanese"
            case .french:
                return "French"
            case .spanish:
                return "Spanish"
            case .korean:
                return "Korean"
            }
        }
        
        let learningLanguageName = languageName(learningLanguage)
        let nativeLanguageName = languageName(nativeLanguage)
        
        // 构建提示语
        var prompt = """
        You are a vocabulary assistant.
        The learner's target (learning) language is \(learningLanguageName), and the learner's native language is \(nativeLanguageName).
        Please generate a completely new example sentence for the word "\(word)" written in \(learningLanguageName).
        Requirements:
        1. Part of speech: \(selectedPartOfSpeech) (if the word has multiple parts of speech, use this specified one)
        2. Word meaning (in native language): \(definition)
        3. The example sentence must be written in \(learningLanguageName), simple and easy to understand, suitable for learners.
        4. The sentence should clearly demonstrate the correct usage of the word.
        5. IMPORTANT: The sentence structure must be completely different from the existing example.
        """
        
        // 如果有当前例句，要求避免相似
        if let currentExample = currentExample, !currentExample.isEmpty {
            prompt += """
            
            The current example sentence is:
            "\(currentExample)"
            Please generate a new sentence whose structure is clearly different.
            Avoid using similar sentence patterns, word order, or expressions.
            For example, if the current one is a simple declarative sentence, you can try a question, exclamation, conditional sentence, passive voice, etc.
            """
        } else {
            prompt += """
            
            Please use diverse sentence patterns, such as:
            - Declarative, interrogative, exclamatory, or imperative sentences
            - Simple, compound, or complex sentences
            - Active or passive voice
            - Different tenses and aspects where appropriate
            """
        }
        
        prompt += """
        
        6. Return the result in strictly valid JSON format:
        {
          "example": "Example sentence written in \(learningLanguageName)",
          "exampleCn": "Translation of the example sentence written in \(nativeLanguageName)"
        }
        Do not include markdown formatting (like ```json). Just return the raw JSON object.
        """
        
        let modelName = try validateModel("deepseek-chat")
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 1.0  // 提高temperature值增加多样性
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw DeepseekServiceError.apiRequestFailed(statusCode)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw DeepseekServiceError.invalidResponse
        }
        
        // 清理可能的 markdown 格式
        let cleanText = text.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanText.data(using: .utf8) else {
            throw DeepseekServiceError.jsonParsingFailed
        }
        
        let decoder = JSONDecoder()
        let exampleData = try decoder.decode([String: String].self, from: jsonData)
        
        guard let example = exampleData["example"],
              let exampleCn = exampleData["exampleCn"] else {
            throw DeepseekServiceError.exampleExtractionFailed
        }
        
        // API调用成功，记录使用次数
        usageTracker.useCall()
        
        return (example: example, exampleCn: exampleCn)
    }
}
