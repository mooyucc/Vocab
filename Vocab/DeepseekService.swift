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
        return "sk-83e8676babc541e5841e7c33a49093c0"
    }
    
    private init() {}
    
    func generateWordDetails(for word: String) async throws -> WordDetails {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "DeepseekService", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先设置 API Key"])
        }
        
        let urlString = "https://api.deepseek.com/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "DeepseekService", code: 2, userInfo: [NSLocalizedDescriptionKey: "无效的 URL"])
        }
        
        let prompt = """
        You are a vocabulary assistant. For the English word "\(word)", provide the following details in strictly valid JSON format:
        {
          "definition": "Concise Chinese definition",
          "partOfSpeech": "Part of speech (e.g., n., v., adj.)",
          "example": "A simple, common English example sentence",
          "exampleCn": "Chinese translation of the example sentence",
          "pronunciation": "IPA phonetic transcription (e.g., /wɜːrd/)"
        }
        Do not include markdown formatting (like ```json). Just the raw JSON object.
        """
        
        let requestBody: [String: Any] = [
            "model": "deepseek-chat",
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
            throw NSError(domain: "DeepseekService", code: 3, userInfo: [NSLocalizedDescriptionKey: "API 请求失败，状态码: \(statusCode)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw NSError(domain: "DeepseekService", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法解析 API 响应"])
        }
        
        // 清理可能的 markdown 格式
        let cleanText = text.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanText.data(using: .utf8) else {
            throw NSError(domain: "DeepseekService", code: 5, userInfo: [NSLocalizedDescriptionKey: "无法解析 JSON"])
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(WordDetails.self, from: jsonData)
    }
    
    // 生成每日激励语
    func generateDailyMotivation() async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "DeepseekService", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先设置 API Key"])
        }
        
        let urlString = "https://api.deepseek.com/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "DeepseekService", code: 2, userInfo: [NSLocalizedDescriptionKey: "无效的 URL"])
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
        
        let requestBody: [String: Any] = [
            "model": "deepseek-chat",
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
            throw NSError(domain: "DeepseekService", code: 3, userInfo: [NSLocalizedDescriptionKey: "API 请求失败，状态码: \(statusCode)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              var text = message["content"] as? String else {
            throw NSError(domain: "DeepseekService", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法解析 API 响应"])
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
        
        return text
    }
    
    // 生成新的例句
    func generateNewExample(for word: String, partOfSpeech: String, definition: String, currentExample: String? = nil) async throws -> (example: String, exampleCn: String) {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "DeepseekService", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先设置 API Key"])
        }
        
        let urlString = "https://api.deepseek.com/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "DeepseekService", code: 2, userInfo: [NSLocalizedDescriptionKey: "无效的 URL"])
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
        
        // 构建提示语
        var prompt = """
        请为英文单词 "\(word)" 生成一个全新的例句。要求：
        1. 单词词性：\(selectedPartOfSpeech)（如果该单词有多种词性，请使用这个指定的词性）
        2. 单词释义：\(definition)
        3. 例句要简单易懂，适合英语学习者
        4. 例句要能很好地展示这个单词的用法
        5. **重要：例句的句式必须与现有例句完全不同**
        """
        
        // 如果有当前例句，要求避免相似
        if let currentExample = currentExample, !currentExample.isEmpty {
            prompt += """
            
            当前例句是："\(currentExample)"
            请生成一个句式结构完全不同的新例句，避免使用相似的句型、语序或表达方式。
            例如：如果当前是陈述句，可以尝试疑问句、感叹句、条件句、被动语态等不同句式。
            """
        } else {
            prompt += """
            
            请使用多样化的句式，可以尝试：
            - 陈述句、疑问句、感叹句、祈使句
            - 简单句、复合句、复杂句
            - 主动语态、被动语态
            - 不同的时态和语态
            """
        }
        
        prompt += """
        
        6. 请以严格有效的 JSON 格式返回：
        {
          "example": "英文例句",
          "exampleCn": "中文翻译"
        }
        不要包含 markdown 格式（如 ```json），只返回原始 JSON 对象。
        """
        
        let requestBody: [String: Any] = [
            "model": "deepseek-chat",
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
            throw NSError(domain: "DeepseekService", code: 3, userInfo: [NSLocalizedDescriptionKey: "API 请求失败，状态码: \(statusCode)"])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw NSError(domain: "DeepseekService", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法解析 API 响应"])
        }
        
        // 清理可能的 markdown 格式
        let cleanText = text.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let jsonData = cleanText.data(using: .utf8) else {
            throw NSError(domain: "DeepseekService", code: 5, userInfo: [NSLocalizedDescriptionKey: "无法解析 JSON"])
        }
        
        let decoder = JSONDecoder()
        let exampleData = try decoder.decode([String: String].self, from: jsonData)
        
        guard let example = exampleData["example"],
              let exampleCn = exampleData["exampleCn"] else {
            throw NSError(domain: "DeepseekService", code: 6, userInfo: [NSLocalizedDescriptionKey: "无法从响应中提取例句"])
        }
        
        return (example: example, exampleCn: exampleCn)
    }
}
