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
    @State private var selectedMaterial: NSVisualEffectView.Material = .hudWindow
    @State private var selectedBrowser: Browsers = .arc
    @State private var aiChatEnabled: Bool = true
    @State private var adBlockerEnabled: Bool = true
    @State private var topBarAddressView: Bool = false
    @State private var isLoading: Bool = false
    @State private var showSafariImportFlow: Bool = false

    var body: some View {
        ZStack {
            BlurEffectView(material: selectedMaterial, state: .active)
                .ignoresSafeArea()
            Color.white.opacity(0.2)

            VStack {
                StageIndicator(stages: 7, activeStage: currentStage)
                Spacer()
                stageView
                    .transition(.slideAndBlur)
                Spacer()
                if !showSafariImportFlow {
                    StageFooter(
                        currentStage: currentStage,
                        isLoading: isLoading,
                        onContinue: advance,
                        onBack: goBack
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
            case 2: AiChatStage(aiChatEnabled: $aiChatEnabled)
            case 3: AdBlockerStage(adBlockerEnabled: $adBlockerEnabled)
            case 4: URLBarStage(topBarAddressView: $topBarAddressView)
            case 5: BackgroundStage(selectedMaterial: $selectedMaterial)
            case 6: FinalStage()
            default: EmptyView()
            }
        }
    }

    private func applySettings() {
        nookSettings.showAIAssistant = aiChatEnabled
        nookSettings.blockCrossSiteTracking = adBlockerEnabled
        nookSettings.currentMaterial = selectedMaterial
        nookSettings.topBarAddressView = topBarAddressView

        nookSettings.didFinishOnboarding = true
    }

    private func advance() {
        guard currentStage < 7 else { return }
        if currentStage == 6 {
            applySettings()
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

    private func goBack() {
        guard currentStage > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStage -= 1
        }
    }

}
