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
        let progress = extensionManager.listInstallProgress
        let isInstalling = progress.map { !$0.isDone } ?? false
        VStack(spacing: 24){
            Text(isInstalling ? "Almost done" : "All done")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            if !isInstalling {
                Text("Welcome onboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let progress {
                HStack(spacing: 8) {
                    Group {
                        if progress.isDone {
                            RoundedCheckmark()
                        } else {
                            RoundedSpinner(color: .white.opacity(0.6))
                        }
                    }
                    .frame(width: 16, height: 16)
                    Text(status(of: progress))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isInstalling)
    }

    private func status(of progress: ExtensionManager.ListInstallProgress) -> String {
        guard progress.isDone else {
            return "Installing \(progress.finished + 1) of \(progress.total) extensions"
        }
        let installed = progress.total - progress.failed
        if progress.failed > 0 {
            return "\(installed) of \(progress.total) extensions installed"
        }
        return installed == 1 ? "1 extension installed" : "\(installed) extensions installed"
    }
}
