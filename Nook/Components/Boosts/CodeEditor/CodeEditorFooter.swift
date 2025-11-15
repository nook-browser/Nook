//
//  CodeEditorFooter.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI


struct CodeEditorFooter: View {
    
    
    var body: some View {
        HStack{
            HStack(spacing: 10) {
                OptionButton(icon: "eyedropper", isActive: false) {
                    
                }
                OptionButton(icon: "hammer", isActive: false) {
                    
                }
            }
            Spacer()
            Text("Refresh to Run")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.black.opacity(0.45))
            OptionButton(icon: "arrow.clockwise", isActive: false) {
                
            }
        }
        .padding(15)

    }
}

#Preview {
    CodeEditorFooter()
        .frame(width: 480, height: 70)
        .background(.white)
}





struct FooterButton: View {
    @State private var isHovered: Bool = false
    
    
    var body: some View {
        Button {
            
        } label: {
            Image(systemName: "hammer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black.opacity(0.75))
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
