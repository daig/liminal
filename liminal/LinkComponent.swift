//
//  LinkComponent.swift
//  liminal
//
//  Created by David Girardo on 2/19/25.
//

/*
import RealityKit


struct ForceDirectedGraphComponent : Component {
    var links: [EdgeID]! = nil
    var linkLookup: LinkLookup = .init(links: [])
}

struct LinkForce: ForceEffectProtocol {
    var parameterTypes: PhysicsBodyParameterTypes { [.position] }
    var forceMode: ForceMode { .force }
    
    //MARK: - Custom properties
    let linkStiffness: Float = 0.5
    let linkLength: Float = 30.0
    let iterationsPerTick: UInt = 1
    

    func update(parameters: inout ForceEffectParameters) {
        guard let positions = parameters.positions else { return }

        for _ in 0..<iterationsPerTick {
            for i in links.indices {

                let s = links[i].source
                let t = links[i].target

                let b = self.calculatedBias[i]

                assert(b != 0)

                var vec =
                    (positionBufferPointer[t] - positionBufferPointer[s])
                    .jiggled(by: &kinetics.randomGenerator)

                var l = vec.length()

                l = (l - self.calculatedLength[i]) / l * self.calculatedStiffness[i] * kinetics.velocityDecay * kinetics.alpha

                vec *= l // * kinetics.velocityDecay

                // same as d3
                velocityBufferPointer[t] -= vec * b
                velocityBufferPointer[s] += vec * (1 - b)
            }
        }

    }
}

*/
