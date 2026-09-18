// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  OnboardingView.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.nookSettings) var nookSettings
    @EnvironmentObject var browserManager: BrowserManager

    @State private var currentStage: Int = 0
    @State private var selectedBrowser: Browsers = .arc
    @State private var isLoading: Bool = false
    @State private var showSafariImportFlow: Bool = false

    var body: some View {
        ZStack {
            BlurEffectView(material: .hudWindow, state: .active)
                .ignoresSafeArea()
            Color.white.opacity(0.2)

            VStack {
                StageIndicator(stages: 3, activeStage: currentStage)
                Spacer()
                stageView
                    .transition(.slideAndBlur)
                Spacer()
                if !showSafariImportFlow {
                    StageFooter(
                        currentStage: currentStage,
                        totalStages: 3,
                        isLoading: isLoading,
                        onContinue: advance,
                        onBack: goBack,
                        onSkip: skipImport
                    )
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) {
            if !isLoading && !showSafariImportFlow {
                advance()
                return .handled
            }
            return .ignored
        }
    }

    @ViewBuilder
    private var stageView: some View {
        if showSafariImportFlow {
            SafariImportFlow(
                isLoading: $isLoading,
                onBack: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSafariImportFlow = false
                    }
                },
                onComplete: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSafariImportFlow = false
                        currentStage += 1
                    }
                }
            )
        } else {
            switch currentStage {
            case 0: HelloStage()
            case 1: ImportStage(selectedBrowser: $selectedBrowser)
            case 2: FinalStage()
            default: EmptyView()
            }
        }
    }

    private func advance() {
        guard currentStage < 3 else { return }
        if currentStage == 2 {
            nookSettings.didFinishOnboarding = true
            return
        }

        if currentStage == 1 && selectedBrowser == .safari {
            withAnimation(.easeInOut(duration: 0.25)) {
                showSafariImportFlow = true
            }
        } else if currentStage == 1 {
            withAnimation(.easeInOut(duration: 0.25)) {
                isLoading = true
            }
            performImport {
                withAnimation(.easeInOut(duration: 0.25)) {
                    currentStage += 1
                    isLoading = false
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentStage += 1
            }
        }
    }

    private func performImport(completion: @escaping () -> Void) {
        Task {
            switch selectedBrowser {
            case .arc:
                await browserManager.importArcData()
            case .dia:
                await browserManager.importDiaData()
            default:
                break
            }
            await MainActor.run {
                completion()
            }
        }
    }

    private func skipImport() {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStage = 2
        }
    }

    private func goBack() {
        guard currentStage > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStage -= 1
        }
    }

}
