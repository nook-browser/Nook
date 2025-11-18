//
//  CodeEditor.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI


struct CodeEditor: View {
    @Binding var cssCode: String
    @Binding var jsCode: String
    @Binding var selectedLanguage: Language
    var onBack: () -> Void
    var onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            CodeEditorHeader(
                selectedLanguage: $selectedLanguage,
                onBack: onBack
            )
            Rectangle()
                .fill(.black.opacity(0.07))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            CodeView(
                code: Binding(
                    get: { selectedLanguage == .css ? cssCode : jsCode },
                    set: { newValue in
                        if selectedLanguage == .css {
                            cssCode = newValue
                        } else {
                            jsCode = newValue
                        }
                    }
                ),
                language: selectedLanguage == .css ? "css" : "javascript"
            )
            .frame(width: 480, height: 480)
            Rectangle()
                .fill(.black.opacity(0.07))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            CodeEditorFooter(onRefresh: onRefresh)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        
    }
}

#Preview {
    @Previewable @State var cssCode = "body { color: red; }"
    @Previewable @State var jsCode = "console.log('test');"
    @Previewable @State var language: Language = .css
    CodeEditor(
        cssCode: $cssCode,
        jsCode: $jsCode,
        selectedLanguage: $language,
        onBack: {},
        onRefresh: {}
    )
    .frame(width: 480)
    .background(.white)
}
