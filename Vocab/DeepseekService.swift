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
    case clozeExtractionFailed
    
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
        case .clozeExtractionFailed:
            return "exercise_ai_parse_failed".localized
        }
    }
}

struct ClozeWordInput {
    let term: String
    let partOfSpeech: String
    let definition: String
    let currentExample: String
}

struct ClozeGenerationItem: Codable {
    let term: String
    let sentence: String
    let answer: String
    let translation: String
    let forms: [String]?
}

class DeepseekService {
    static let shared = DeepseekService()
    
    // Deepseek API Key：环境变量 > Config/Secrets.xcconfig（经 Info.plist 注入）
    private var apiKey: String {
        if let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty {
            return key
        }
        if let key = Bundle.main.object(forInfoDictionaryKey: "DEEPSEEK_API_KEY") as? String {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            // 未配置 xcconfig 时可能残留未展开的 $(DEEPSEEK_API_KEY)
            if !trimmed.isEmpty && !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }
        return ""
    }
    
    private let usageTracker = UsageTracker.shared
    
    /// deepseek-chat / deepseek-reasoner 已于 2026/07/24 停用，改用 v4-flash（关闭 thinking，行为接近原 chat）
    private let defaultModel = "deepseek-v4-flash"
    
    private init() {}
    
    // 验证并确保不使用已停用的模型名
    private func validateModel(_ model: String) throws -> String {
        let lowercased = model.lowercased()
        if lowercased.contains("reasoner") || lowercased == "deepseek-chat" {
            throw NSError(domain: "DeepseekService", code: 100, userInfo: [NSLocalizedDescriptionKey: "禁止使用已停用的 deepseek-chat / deepseek-reasoner，请使用 deepseek-v4-flash"])
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
        let scriptRule = chineseScriptConstraint(learningLanguage: learningLanguage, nativeLanguage: nativeLanguage)
        
        let prompt = """
        You are a vocabulary assistant.
        The learner's target (learning) language is \(learningLanguageName), and the learner's native language is \(nativeLanguageName).
        The word "\(word)" is written in \(learningLanguageName).
        \(scriptRule)
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
        
        let modelName = try validateModel(defaultModel)
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.7,
            "thinking": ["type": "disabled"]
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
        let scriptRule = chineseScriptConstraint(learningLanguage: learningLanguage, nativeLanguage: nativeLanguage)
        
        // 构建提示语
        var prompt = """
        You are a vocabulary assistant.
        The learner's target (learning) language is \(learningLanguageName), and the learner's native language is \(nativeLanguageName).
        \(scriptRule)
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
        
        let modelName = try validateModel(defaultModel)
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 1.0,  // 提高temperature值增加多样性
            "thinking": ["type": "disabled"]
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
    
    /// 一次生成整套完形填空（消耗 1 次调用），不写回词库例句
    func generateClozeSet(for words: [ClozeWordInput]) async throws -> [ClozeGenerationItem] {
        guard usageTracker.hasRemainingCalls() else {
            throw DeepseekServiceError.noRemainingCalls
        }
        guard !apiKey.isEmpty else {
            throw DeepseekServiceError.apiKeyNotSet
        }
        guard !words.isEmpty else {
            throw DeepseekServiceError.clozeExtractionFailed
        }
        
        let urlString = "https://api.deepseek.com/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw DeepseekServiceError.invalidURL
        }
        
        let settings = AppSettingsManager.shared
        let learningLanguageName = languageDisplayName(settings.targetLanguage)
        let nativeLanguageName = languageDisplayName(settings.language)
        let scriptRule = chineseScriptConstraint(learningLanguage: settings.targetLanguage, nativeLanguage: settings.language)
        
        let wordLines = words.enumerated().map { index, word in
            let example = word.currentExample.isEmpty ? "(none)" : word.currentExample
            return """
            \(index + 1). term="\(word.term)"; pos="\(word.partOfSpeech)"; meaning="\(word.definition)"; existingExample="\(example)"
            """
        }.joined(separator: "\n")
        
        let prompt = """
        You are a vocabulary quiz assistant creating a cloze (fill-in-the-blank) exercise.
        The learner's target (learning) language is \(learningLanguageName), and the learner's native language is \(nativeLanguageName).
        \(scriptRule)
        Create exactly \(words.count) cloze items, one for each word below. Each sentence must use that word (any grammatically correct inflected form).
        
        Words:
        \(wordLines)
        
        Return strictly valid JSON:
        {
          "items": [
            {
              "term": "the lemma exactly as given",
              "sentence": "A full sentence in \(learningLanguageName) that contains the inflected form",
              "answer": "the exact inflected form as it appears in sentence",
              "translation": "translation of the sentence in \(nativeLanguageName)",
              "forms": ["lemma", "other common inflected forms", "answer"]
            }
          ]
        }
        Rules:
        1. Use each word exactly once. Keep the "term" field identical to the given lemma.
        2. The sentence must be written in \(learningLanguageName), simple and suitable for learners.
        3. Do NOT copy or closely paraphrase the existing example.
        4. "answer" MUST appear in "sentence" as a whole word/token.
        5. "forms" contains 3-5 common inflected forms of the same lemma and MUST include both the lemma and "answer". If the language has little inflection, "forms" may contain only the lemma.
        6. Do not include markdown or any text outside the JSON object.
        """
        
        let modelName = try validateModel(defaultModel)
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "temperature": 0.8,
            "thinking": ["type": "disabled"]
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
        
        guard let jsonData = stripMarkdownJSON(text).data(using: .utf8) else {
            throw DeepseekServiceError.jsonParsingFailed
        }
        
        struct ClozeGenerationResponse: Codable {
            let items: [ClozeGenerationItem]
        }
        
        let decoded: ClozeGenerationResponse
        do {
            decoded = try JSONDecoder().decode(ClozeGenerationResponse.self, from: jsonData)
        } catch {
            throw DeepseekServiceError.clozeExtractionFailed
        }
        
        let items = decoded.items.filter {
            !$0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !items.isEmpty else {
            throw DeepseekServiceError.clozeExtractionFailed
        }
        
        usageTracker.useCall()
        return items
    }
    
    private func languageDisplayName(_ language: AppLanguage) -> String {
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
    
    /// 简繁不能混用：学习语言或母语为中文时，强制对应字形。
    private func chineseScriptConstraint(learningLanguage: AppLanguage, nativeLanguage: AppLanguage) -> String {
        let involvesChinese = [learningLanguage, nativeLanguage].contains {
            $0 == .chinese || $0 == .chineseTraditional
        }
        guard involvesChinese else { return "" }
        return """
        Chinese script rule: "Simplified Chinese" must use 简体字 only; "Traditional Chinese" must use 繁體字 only. Never mix the two scripts or substitute one for the other.
        """
    }
    
    private func stripMarkdownJSON(_ text: String) -> String {
        var clean = text.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = clean.firstIndex(of: "{"), let end = clean.lastIndex(of: "}") {
            clean = String(clean[start...end])
        }
        return clean
    }
}
