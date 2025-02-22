import SwiftUI

struct SettingsView: View {
    @AppStorage("openAIKey") private var apiKey = ""
    @Environment(\.dismiss) private var dismiss
    @State private var temporaryKey: String = ""
    @State private var showAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("OpenAI API Key")) {
                    SecureField("Enter API Key", text: $temporaryKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    Button("Save API Key") {
                        apiKey = temporaryKey
                        showAlert = true
                    }
                    .disabled(temporaryKey.isEmpty)
                }
                
                Section {
                    Text("Your API key is stored securely in the system's keychain. You can get an API key from [OpenAI's website](https://platform.openai.com/api-keys).")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("API Key Saved", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text("Your OpenAI API key has been saved successfully.")
            }
            .onAppear {
                temporaryKey = apiKey
            }
        }
    }
} 