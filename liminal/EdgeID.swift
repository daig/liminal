//
//  Edge.swift
//  liminal
//
//  Created by David Girardo on 2/19/25.
//

import Foundation

struct NodeID : Hashable, Identifiable {let id: Int}
struct EdgeID: Hashable { let source: NodeID; let target: NodeID }
