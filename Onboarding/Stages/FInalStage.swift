// Licensed under GPL-3.0. See LICENSE.
//
//  FInalStage.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import SwiftUI

struct FinalStage: View {
    @ObservedObject var extensionManager: ExtensionManager

    var body: some View {
        VStack(spacing: 24){
            Text(extensionManager.listInstallProgress == nil ? "All done" : "Almost done")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("Welcome onboard")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            if let progress = extensionManager.listInstallProgress {
                HStack(spacing: 8) {
                    RoundedSpinner()
                        .frame(width: 14, height: 14)
                    Text("Installing \(min(progress.finished + 1, progress.total)) of \(progress.total) extensions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}
