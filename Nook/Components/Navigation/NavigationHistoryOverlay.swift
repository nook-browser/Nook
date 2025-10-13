//
//  NavigationHistoryOverlay.swift
//  Nook
//
//  Created by Jonathan Caudill on 01/10/2025.
//

import SwiftUI

enum NavigationHistoryMenuType {
    case back
    case forward
}

struct NavigationHistoryOverlay: View {
    @EnvironmentObject var browserManager: BrowserManager
    let windowState: BrowserWindowState
    @Binding var isPresented: Bool
    let menuType: NavigationHistoryMenuType

    var body: some View {
        ZStack {
            // Background overlay to catch taps
            if isPresented {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(0)
            }

            // Menu content
            if isPresented {
                VStack {
                    Spacer()

                    HStack {
                        if menuType == .back {
                            NavigationHistoryMenu(
                                windowState: windowState,
                                historyType: .back
                            )
                            .environmentObject(browserManager)
                            .onAppear {
                                // Menu is shown automatically
                            }
                            .onDisappear {
                                isPresented = false
                            }
                            .padding(.leading, 8)
                        } else {
                            NavigationHistoryMenu(
                                windowState: windowState,
                                historyType: .forward
                            )
                            .environmentObject(browserManager)
                            .onAppear {
                                // Menu is shown automatically
                            }
                            .onDisappear {
                                isPresented = false
                            }
                            .padding(.leading, 50)
                        }

                        Spacer()
                    }

                    Spacer()
                }
                .zIndex(1)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .scale(scale: 0.9))
                ))
                .animation(.easeInOut(duration: 0.2), value: isPresented)
            }
        }
        .ignoresSafeArea()
    }
}