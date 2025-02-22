import Foundation

class OpenAIClient {
    private let apiKey: String
    private let endpoint = "https://api.openai.com/v1/chat/completions"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
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
        Given the following voice command and list of available files, identify which files need to be examined to fully understand and execute the command.
        Consider files that might contain relevant context, implementation details, or affected functionality.
        
        Command: \(command)
        
        Available files:
        \(availableFiles.joined(separator: "\n"))
        
        Return only the list of relevant filenames, one per line.
        """
        
        let response = try await sendChatCompletion(prompt: prompt)
        return response.split(separator: "\n").map(String.init)
    }
    
    func executeCommand(command: String, fileContexts: [String: String]) async throws -> String {
        let contextString = fileContexts.map { filename, content in
            """
            File: \(filename)
            Content:
            \(content)
            """
        }.joined(separator: "\n\n")
        
        let prompt = """
        Given the following command and codebase context, explain what needs to be done and provide specific implementation guidance:
        
        Command: \(command)
        
        Codebase Context:
        \(contextString)
        
        Provide a clear explanation of what should be implemented and any specific code changes needed.
        """
        
        return try await sendChatCompletion(prompt: prompt)
    }
    
    private func sendChatCompletion(prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that provides concise responses."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        
        guard let content = response.choices.first?.message.content else {
            throw NSError(domain: "OpenAIError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content generated"])
        }
        
        return content
    }
} 