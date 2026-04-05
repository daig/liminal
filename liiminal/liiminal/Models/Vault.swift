import Foundation

struct Note: Identifiable, Hashable {
    let id: URL
    let relativePath: String
    var title: String
    var content: String
    var lastModified: Date

    var filename: String { id.lastPathComponent }
    var relativePathWithoutExtension: String {
        (relativePath as NSString).deletingPathExtension
    }

    init(url: URL, relativePath: String, content: String = "", lastModified: Date = .now) {
        self.id = url
        self.relativePath = relativePath
        self.title = url.deletingPathExtension().lastPathComponent
        self.content = content
        self.lastModified = lastModified
    }
}

struct Vault: Identifiable {
    let id: URL
    var name: String
    var notes: [Note]

    var url: URL { id }

    init(url: URL, notes: [Note] = []) {
        self.id = url
        self.name = url.lastPathComponent
        self.notes = notes
    }
}
