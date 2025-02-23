import Foundation

class OpenAIClient {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    private let maxTokens = 8192
    private let maxCompletionTokens = 500
    private let averageCharsPerToken = 4  // Rough estimate
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let role: String
                let content: String
            }
            let message: Message
            let index: Int
            let finish_reason: String?
        }
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [Choice]
        let usage: Usage
    }
    
    struct Usage: Codable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
    
    struct FileResponse: Codable {
        let relevantFiles: [String]
    }
    
    struct SignificantTermsResponse: Codable {
        let terms: [String]
    }
    
    struct APIError: Codable {
        struct ErrorDetail: Codable {
            let message: String
            let type: String
            let param: String?
            let code: String?
        }
        let error: ErrorDetail
    }
    
    func generateSummary(text: String) async throws -> String {
        let prompt = """
        Please provide a concise summary of the following text:
        
        \(text)
        """
        
        return try await sendChatCompletion(prompt: prompt)
    }
    
    func analyzeCommand(command: String, availableFiles: [String]) async throws -> [String] {
        let prompt = """
        Given the following query and list of available files, identify which files need to be examined to fully understand and execute the query.
        Consider files that might contain relevant context.
        
        Command: \(command)
        
        Available files:
        \(availableFiles.joined(separator: "\n"))
        
        Return the relevant filenames as a JSON object with a 'relevantFiles' array.
        """
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that provides structured output. Return only the list of relevant filenames."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": maxCompletionTokens,
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Debug: Print the raw response
        if let httpResponse = response as? HTTPURLResponse {
            print("API Response Status:", httpResponse.statusCode)
        }
        if let jsonString = String(data: data, encoding: .utf8) {
            print("API Response:", jsonString)
        }
        
        // Check for API error response
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let apiError = try JSONDecoder().decode(APIError.self, from: data)
            throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: apiError.error.message
            ])
        }
        
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        guard let content = completion.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw NSError(domain: "OpenAIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content generated"])
        }
        
        let fileResponse = try JSONDecoder().decode(FileResponse.self, from: jsonData)
        return fileResponse.relevantFiles
    }
    
    func executeCommand(command: String, fileContexts: [String: String]) async throws -> String {
        // Calculate available tokens for content
        let systemPrompt = "You are a helpful assistant that provides concise responses."
        let basePrompt = """
        Given the following query knowledgebase context, answer the query helpfully and concisely.
        
        <Query>
        \(command)
        </Query>
        
        
        """
        
        // Rough token count estimation
        let systemTokens = systemPrompt.count / averageCharsPerToken
        let baseTokens = basePrompt.count / averageCharsPerToken
        let availableTokens = maxTokens - maxCompletionTokens - systemTokens - baseTokens
        
        // Truncate each file's content to fit within token limit
        var truncatedContexts: [String: String] = [:]
        let maxTokensPerFile = availableTokens / fileContexts.count
        let maxCharsPerFile = maxTokensPerFile * averageCharsPerToken
        
        for (filename, content) in fileContexts {
            var truncatedContent = content
            if content.count > maxCharsPerFile {
                let startIndex = content.startIndex
                let endIndex = content.index(startIndex, offsetBy: maxCharsPerFile, limitedBy: content.endIndex) ?? content.endIndex
                truncatedContent = String(content[startIndex..<endIndex]) + "\n... (content truncated)"
            }
            truncatedContexts[filename] = truncatedContent
        }
        
        let contextString = truncatedContexts.map { filename, content in
            """
            File: \(filename)
            Content:
            \(content)
            """
        }.joined(separator: "\n\n")
        
        let prompt = basePrompt + "\n" + contextString + "\n\nProvide a clear explanation of what should be implemented and any specific code changes needed."
        
        return try await sendChatCompletion(prompt: prompt)
    }
    
    func extractSignificantTerms(text: String) async throws -> [String] {
        let prompt = """
        Analyze the following text and extract a list of significant terms, including:
        - Technical terms and concepts
        - Place names
        - People names
        - Important phrases or keywords
        - Domain-specific terminology
        
        Return ONLY a JSON object with a 'terms' array containing these terms.
        
        Text to analyze:
        \(text)
        """
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that extracts significant terms from text. Return only a JSON object with a 'terms' array."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": maxCompletionTokens,
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for API error response
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let apiError = try JSONDecoder().decode(APIError.self, from: data)
            throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: apiError.error.message
            ])
        }
        
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        guard let content = completion.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            throw NSError(domain: "OpenAIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content generated"])
        }
        
        let termsResponse = try JSONDecoder().decode(SignificantTermsResponse.self, from: jsonData)
        return termsResponse.terms
    }
    
    private func sendChatCompletion(prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that provides concise responses."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": maxCompletionTokens
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Debug: Print the raw response
        if let httpResponse = response as? HTTPURLResponse {
            print("API Response Status:", httpResponse.statusCode)
        }
        if let jsonString = String(data: data, encoding: .utf8) {
            print("API Response:", jsonString)
        }
        
        // Check for API error response
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let apiError = try JSONDecoder().decode(APIError.self, from: data)
            throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: apiError.error.message
            ])
        }
        
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        guard let content = completion.choices.first?.message.content else {
            throw NSError(domain: "OpenAIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content generated"])
        }
        
        return content
    }
} 
