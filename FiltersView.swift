//
//  FiltersView.swift
//  liminal
//
//  Created by David Girardo on 2/21/25.
//

import SwiftUI

struct FiltersView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Filters")
                .font(.headline)
            Button("Filter 1") {
                // Apply filter 1 (stubbed)
            }
            Button("Filter 2") {
                // Apply filter 2 (stubbed)
            }
            // Add more filters as needed
        }
        .padding()
        .background(Color.gray.opacity(0.5))
        .cornerRadius(8)
    }
}
