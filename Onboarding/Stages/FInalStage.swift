//
//  FInalStage.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import SwiftUI

struct FinalStage: View {

    var body: some View {
        VStack(spacing: 24){
            Text("All done")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("Welcome onboard")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
