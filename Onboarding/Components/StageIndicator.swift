// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  StageIndicator.swift
//  Nook
//
//  Created by Maciek Bagiński on 17/02/2026.
//

import SwiftUI

struct StageIndicator: View {

    var stages: Int
    var activeStage: Int

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(0..<stages, id: \.self) { stage in
                Circle()
                    .fill(activeStage == stage ? .white : .white.opacity(0.4))
                    .frame(width: 10, height: 10)
            }

        }
    }
}
