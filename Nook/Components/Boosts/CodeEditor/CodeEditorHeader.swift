//
//  CodeEditorHeader.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import AppKit
import SwiftUI

enum Language {
    case js
    case css
}

struct CodeEditorHeader: View {
    @Binding var selectedLanguage: Language
    var onBack: () -> Void

    var body: some View {
        HStack {
            BackButton(action: onBack)
            Spacer()
            LanguagePicker(language: $selectedLanguage)
            Spacer()
            Spacer()

        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WindowDragView())
    }

}

#Preview {
    @Previewable @State var language: Language = .css
    CodeEditorHeader(selectedLanguage: $language, onBack: {})
        .padding(10)
        .frame(width: 480)
        .background(.white)
}

struct BackButton: View {
    var action: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.85))
                Text("Back")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.85))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(isHovering ? .black.opacity(0.07) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))

        }
        .buttonStyle(.plain)
        .onHover { state in
            isHovering = state
        }
    }
}

struct LanguagePicker: View {
    @Binding var language: Language

    var body: some View {
        HStack(spacing: 1) {
            Button {
                language = .css
            } label: {
                Text("CSS")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black)
                    .frame(width: 74, height: 20)
                    .background(language == .css ? .white : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            Button {
                language = .js
            } label: {
                Text("JS")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black)
                    .frame(width: 74, height: 20)
                    .background(language == .js ? .white : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(1)
        .background(.black.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
