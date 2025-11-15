//
//  CodeEditor.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI


struct CodeEditor: View {
    
    
    var body: some View {
        VStack(spacing: 0) {
            CodeEditorHeader()
            Rectangle()
                .fill(.black.opacity(0.07))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            CodeView()
                .frame(width: 480, height: 480)
            Rectangle()
                .fill(.black.opacity(0.07))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            CodeEditorFooter()
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        
    }
}

#Preview {
    CodeEditor()
        .frame(width: 480)
        .background(.white)
}
