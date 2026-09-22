// Licensed under GPL-3.0. See LICENSE.
//
//  ImportStage.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import NookDesign
import SwiftUI

enum Browsers {
    case arc
    case chrome
    case safari
    case dia
    case firefox
    case zen
}

struct ImportStage: View {
    @Binding var selectedBrowser: Browsers

    var body: some View {
        VStack(spacing: 24) {
            Text("Transition to Nook")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 24) {
                browserButton(icon: "globe", name: "Arc", browser: .arc)
                browserButton(icon: "safari", name: "Safari", browser: .safari)
                browserButton(icon: "globe", name: "Dia", browser: .dia)
            }
        }
    }

    @ViewBuilder
    private func browserButton(icon: String, name: String, browser: Browsers) -> some View {
        Button {
            selectedBrowser = browser
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selectedBrowser == browser ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(selectedBrowser == browser ? .white : .white.opacity(0.2))
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .animation(.easeInOut(duration: 0.1), value: selectedBrowser == browser)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
