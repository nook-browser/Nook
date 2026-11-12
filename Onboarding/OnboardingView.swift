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
    @ObservedObject private var extensionManager = ExtensionManager.shared

    @State private var currentStage: Int = 0
    @State private var selectedBrowser: Browsers = .arc
    @State private var isLoading: Bool = false
    @State private var showSafariImportFlow: Bool = false
    @State private var extensionChoices: [ExtensionChoice] = []
    @State private var isFindingExtensions = false

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
                StageIndicator(stages: 4, activeStage: currentStage)
                Spacer()
                stageView
                    .transition(.slideAndBlur)
                Spacer()
                if !showsOwnButtons {
                    StageFooter(
                        currentStage: currentStage,
                        totalStages: 4,
                        isLoading: isLoading,
                        canGoBack: !isInstallingExtensions,
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
        showSafariImportFlow || currentStage == 2
    }

    private var isInstallingExtensions: Bool {
        extensionManager.listInstallProgress.map { !$0.isDone } ?? false
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
                    showExtensions(includingArc: false)
                }
            )
        } else {
            switch currentStage {
            case 0: HelloStage()
            case 1: ImportStage(selectedBrowser: $selectedBrowser)
            case 2: ExtensionsStage(choices: extensionChoices, onDone: finishExtensions)
            case 3: FinalStage(extensionManager: extensionManager)
            default: EmptyView()
            }
        }
    }

    private func advance() {
        guard currentStage < 4, !isFindingExtensions else { return }
        if currentStage == 3 {
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
                showExtensions(includingArc: selectedBrowser == .arc)
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

    private func showExtensions(includingArc: Bool) {
        isFindingExtensions = true
        Task {
            let choices = await browserManager.extensionChoices(includingArc: includingArc)
            isFindingExtensions = false
            withAnimation(.easeInOut(duration: 0.25)) {
                showSafariImportFlow = false
                isLoading = false
                extensionChoices = choices
                currentStage = choices.isEmpty ? 3 : 2
            }
        }
    }

    private func finishExtensions(_ chosen: [ExtensionOffer]) {
        guard currentStage == 2 else { return }
        extensionManager.install(chosen)
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStage = 3
        }
    }

    private func skipImport() {
        guard !isFindingExtensions else { return }
        showExtensions(includingArc: false)
    }

    private func goBack() {
        guard currentStage > 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStage = currentStage == 3 ? 1 : currentStage - 1
        }
    }

}
