//
//  StageFooter.swift
//  Nook
//
//  Created by Maciek Bagiński on 17/02/2026.
//

import SwiftUI

struct StageFooter: View {
    var currentStage: Int
    var isLoading: Bool = false
    var onContinue: () -> Void
    var onBack: () -> Void

    var secondaryText: String {
        switch currentStage {
        case 0: return ""
        case 1: return "Skip"
        default: return "Back"
        }
    }

    var primaryText: String {
        if(isLoading) {
            return "Importing data..."
        } else {
            switch currentStage {
            case 0: return "Get Started"
            case 1: return "Move your data"
            case 7: return "Start browsing"
            default: return "Continue"
            }
        }

    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                onContinue()
            } label: {
                HStack {
                    Text(primaryText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .contentTransition(.numericText(value: Double(primaryText.count)))
                    if(isLoading) {
                        RoundedSpinner()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "return")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.8))
                        
                    }

                }
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isLoading)
            if !(currentStage == 0) {
                Button {
                    if currentStage > 0 { onBack() }
                } label: {
                    Text(secondaryText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(12)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }

        }
    }
}
