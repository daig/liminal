//
//  File.swift
//  liminal
//
//  Created by David Girardo on 2/22/25.
//

import Foundation

struct NoteData: Codable, Hashable {
    var title: String
    var content: String
    
    init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}
