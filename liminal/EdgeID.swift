//
//  Edge.swift
//  liminal
//
//  Created by David Girardo on 2/19/25.
//

import Foundation

public struct NodeID : Hashable, Identifiable {public let id: Int}
public struct EdgeID: Hashable { public let source: NodeID; public let target: NodeID }
