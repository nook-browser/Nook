// Licensed under GPL-3.0. See LICENSE.
//
//  OnboardingView.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import NookDesign
import SwiftUI

struct OnboardingView: View {
    @Environment(\.nookSettings) var nookSettings
    @EnvironmentObject var browserManager: BrowserManager

    @State private var currentStage: Int = 0
    @State private var selectedBrowser: Browsers = .arc
    @State private var isLoading: Bool = false
    @State private var showSafariImportFlow: Bool = false
    @State private var extensionOffers: [ExtensionOffer] = []

    var body: some View {
        ZStack {
            // A fixed dark backdrop: the stages draw white text. The old blur showed glass while
            // the window was key and plain white once it was not.
            NookDesign.Surface.onboardingBackdrop
                .overlay {
                    Image("noise_texture")
                        .resizable(resizingMode: .tile)
                        .opacity(NookDesign.Surface.grainOpacity)
                        .blendMode(.overlay)
                }
                .ignoresSafeArea()

            VStack {
                StageIndicator(stages: 3, activeStage: currentStage)
                Spacer()
                stageView
                    .transition(.slideAndBlur)
                Spacer()
                if !showsOwnButtons {
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
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) {
            if !isLoading && !showsOwnButtons {
                advance()
                return .handled
            }
            return .ignored
        }
    }

    private var showsOwnButtons: Bool {
        showSafariImportFlow || !extensionOffers.isEmpty
    }

    @ViewBuilder
    private var stageView: some View {
        if !extensionOffers.isEmpty {
            ExtensionsStage(offers: extensionOffers, onDone: finishExtensions)
        } else if showSafariImportFlow {
            SafariImportFlow(
                isLoading: $isLoading,
                onBack: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSafariImportFlow = false
                    }
                },
                onComplete: {
                    guard !isLoading else { return }
                    isLoading = true
                    Task { offerExtensions(await browserManager.safariExtensionOffers()) }
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
                offerExtensions(selectedBrowser == .arc ? browserManager.arcExtensionOffers() : [])
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

    private func offerExtensions(_ offers: [ExtensionOffer]) {
        withAnimation(.easeInOut(duration: 0.25)) {
            showSafariImportFlow = false
            isLoading = false
            if offers.isEmpty {
                currentStage += 1
            } else {
                extensionOffers = offers
            }
        }
    }

    private func finishExtensions(_ chosen: [ExtensionOffer]) {
        Task { await browserManager.extensionManager?.install(chosen) }
        withAnimation(.easeInOut(duration: 0.25)) {
            extensionOffers = []
            currentStage += 1
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
