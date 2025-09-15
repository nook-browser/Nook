//
//  DialogView.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct DialogView: View {
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        ZStack {
            if browserManager.dialogManager.isVisible {
                overlayBackground
                dialogContent
                    .transition(.asymmetric(
                        insertion: .offset(y: 30).combined(with: .opacity),
                        removal: .offset(y: -30).combined(with: .opacity)
                    ))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: browserManager.dialogManager.isVisible)
    }
    
    @ViewBuilder
    private var overlayBackground: some View {
        Color.black.opacity(0.4)
            .ignoresSafeArea()
            .onTapGesture {
                browserManager.dialogManager.closeDialog()
            }
            .transition(.opacity)
    }
    
    @ViewBuilder
    private var dialogContent: some View {
        HStack {
            Spacer()
            
            VStack(alignment: .leading, spacing: hasHeader || hasBody || hasFooter || hasCustomContent ? 32 : 0) {
                if hasHeader {
                    browserManager.dialogManager.headerContent
                }
                
                if hasCustomContent {
                    browserManager.dialogManager.customContent
                } else if hasBody {
                    browserManager.dialogManager.bodyContent
                }
                
                if hasFooter {
                    browserManager.dialogManager.footerContent
                }
            }
            .padding(24)
            .background(.thinMaterial)
            .frame(maxWidth: 500)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2))
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            Spacer()
        }
    }
    
    // MARK: - Computed Properties
    
    private var hasHeader: Bool {
        browserManager.dialogManager.headerContent != nil
    }
    
    private var hasBody: Bool {
        browserManager.dialogManager.bodyContent != nil
    }
    
    private var hasFooter: Bool {
        browserManager.dialogManager.footerContent != nil
    }
    
    private var hasCustomContent: Bool {
        browserManager.dialogManager.customContent != nil
    }
}
