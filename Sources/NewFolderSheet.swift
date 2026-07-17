import SwiftUI

struct NewFolderSheet: View {
    let parentURL: URL?
    let parentPath: String? // For future Android use
    let platform: Platform // .mac or .android
    let onCancel: () -> Void
    let onCreate: (String) -> Void
    
    enum Platform {
        case mac
        case android
    }
    
    @State private var folderName: String = ""
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            Text("New Folder")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                TextField("Folder Name", text: $folderName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 300)
                    .onSubmit {
                        validateAndCreate()
                    }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Create") {
                    validateAndCreate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }
    
    private func validateAndCreate() {
        let trimmedName = folderName.trimmingCharacters(in: .whitespaces)
        
        if trimmedName.isEmpty {
            errorMessage = "Folder name cannot be empty."
            return
        }
        
        let invalidCharacters = CharacterSet(charactersIn: ":/")
        if trimmedName.rangeOfCharacter(from: invalidCharacters) != nil {
            errorMessage = "Folder name cannot contain ':' or '/'."
            return
        }
        
        if platform == .mac, let parent = parentURL {
            let newURL = parent.appendingPathComponent(trimmedName)
            if FileManager.default.fileExists(atPath: newURL.path) {
                errorMessage = "A file or folder with this name already exists."
                return
            }
        }
        // Future Android validation could go here
        
        errorMessage = nil
        onCreate(trimmedName)
    }
}
