//
//  ImportStage.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import SwiftUI

enum Browsers {
    case arc
    case chrome
    case safari
    case dia
    case firefox
    case zen

    var isImplemented: Bool {
        switch self {
        case .arc, .dia, .safari: return true
        case .chrome, .firefox, .zen: return false
        }
    }
}

struct ImportStage: View {
    @Binding var selectedBrowser: Browsers

    var body: some View {
        VStack(spacing: 24){
            Text("Transition to Nook")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            VStack(spacing: 12){
                HStack(spacing: 24) {
                    browserButton(image: "arc-logo", browser: .arc)
                    browserButton(image: "chrome-logo", browser: .chrome)
                    browserButton(image: "safari-logo", browser: .safari)
                }
                HStack(spacing: 24) {
                    browserButton(image: "dia-logo", browser: .dia)
                    browserButton(image: "firefox-logo", browser: .firefox)
                    browserButton(image: "zen-logo", browser: .zen)
                }
            }
        }
    }

    @ViewBuilder
    private func browserButton(image: String, browser: Browsers) -> some View {
        let enabled = browser.isImplemented
        Button {
            if enabled {
                selectedBrowser = browser
            }
        } label: {
            Image(image)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
                .frame(width: 44, height: 44)
                .background(selectedBrowser == browser ? .white : .white.opacity(enabled ? 0.5 : 0.2))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .animation(.easeInOut(duration: 0.1), value: selectedBrowser == browser)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!enabled)
    }
}
