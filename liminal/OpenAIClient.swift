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
    
    struct TermMatchesResponse: Codable {
        struct Match: Codable {
            let term: String
            let filename: String?
        }
        let matches: [Match]
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
        Analyze the following text and extract ONLY terms that represent core concepts, fundamental ideas, or key definitions. Include:
        - Technical terms that are being defined or explained
        - Core concepts that form the basis of discussion
        - Names of fundamental theories, methods, or approaches
        - Key people or places that are central to the topic
        
        DO NOT include:
        - Specific implementations or examples
        - Tutorial-style concepts
        - Peripheral or secondary terms
        - Implementation details
        
        For example:
        - Include "Machine Learning" if it's being defined/explained
        - Don't include "TensorFlow" if it's just being used as an example
        - Include "Gradient Descent" if the text explains what it is
        - Don't include "learning_rate=0.01" as it's an implementation detail
        
        Return ONLY a JSON object with a 'terms' array containing these fundamental terms.
        
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
    
    func matchTermsToFiles(terms: [String], filenames: [String]) async throws -> [(term: String, match: String?, reason: String?)] {
        print("\nDebug - Filenames being passed to LLM:")
        for (index, filename) in filenames.enumerated() {
            print("[\(index)]: '\(filename)'")
        }
        print("Total filenames:", filenames.count)
        print()
        
        let prompt = """
        Given a list of key terms that represent core concepts and a list of filenames, find the best definitional match for each term.
        A definitional match is a file that likely contains the primary definition or explanation of that term.
        
        Only match a term to a file if you're confident the file is meant to define or explain that term.
        Do not match to files that seem like tutorials, examples, or implementations.
        Ignore file extensions when matching.
        Match even if the cases don't match exactly.
        
        Key Terms:
        \(terms.joined(separator: "\n"))
        
        Available Files:
        \(filenames.joined(separator: "\n"))
        
        Return a JSON object with a 'matches' array containing objects with:
        - term: the original term
        - filename: the best matching filename (or null if no good match)
        """
        
        print("Debug - Full prompt being sent to LLM:")
        print(prompt)
        print()
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that matches terms to their definitional files. Return only a JSON object with a 'matches' array."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2,
            "max_tokens": 2000,
            "response_format": ["type": "json_object"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for API error response
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            print("\nDebug - API Error Response:")
            print("Status Code:", httpResponse.statusCode)
            if let errorString = String(data: data, encoding: .utf8) {
                print("Error Response:", errorString)
            }
            let apiError = try JSONDecoder().decode(APIError.self, from: data)
            throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: apiError.error.message
            ])
        }
        
        print("\nDebug - API Success Response:")
        if let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
        
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        guard let content = completion.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            print("\nDebug - No content in response or invalid JSON")
            throw NSError(domain: "OpenAIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content generated"])
        }
        
        print("\nDebug - LLM Response Content:")
        print(content)
        
        let matchResponse = try {
            print("\nDebug - Attempting to decode response as TermMatchesResponse")
            do {
                return try JSONDecoder().decode(TermMatchesResponse.self, from: jsonData)
            } catch {
                print("Initial decode failed:", error)
                // If the JSON is incomplete, try to fix it
                let fixedContent = content.replacingOccurrences(of: ",\\s*$", with: "", options: .regularExpression)
                    .appending("\n  ]\n}")
                if let fixedData = fixedContent.data(using: .utf8) {
                    print("\nAttempting to decode with fixed JSON:")
                    print(fixedContent)
                    return try JSONDecoder().decode(TermMatchesResponse.self, from: fixedData)
                }
                throw error
            }
        }()
        
        let result = matchResponse.matches.map { ($0.term, $0.filename, nil as String?) }
        print("\nDebug - Final matches:")
        for match in result {
            print("Term: \(match.0)")
            print("  → Match: \(match.1 ?? "no match")")
        }
        
        return result
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
