//
//  LinkLookup.swift
//  liminal
//
//  Created by David Girardo on 2/19/25.
//

import Foundation

struct LinkLookup {
    let sourceToTarget: [NodeID: [NodeID]]
    let targetToSource: [NodeID: [NodeID]]
    let count: [NodeID: Int]

    @inlinable
    init(links: [EdgeID]) {
        var sourceToTarget: [NodeID: [NodeID]] = [:]
        var targetToSource: [NodeID: [NodeID]] = [:]
        var count: [NodeID: Int] = [:]
        for link in links {
            sourceToTarget[link.source, default: []].append(link.target)
            targetToSource[link.target, default: []].append(link.source)
            count[link.source, default: 0] += 1
            count[link.target, default: 0] += 1
        }
        self.sourceToTarget = sourceToTarget
        self.targetToSource = targetToSource
        self.count = count
    }

}
