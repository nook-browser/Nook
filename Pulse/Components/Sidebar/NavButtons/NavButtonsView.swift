//
//  NavButtonsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct NavButtonsView: View {
    var body: some View {
        HStack(spacing: 2) {
            MacButtonsView()
                .frame(width: 70)
            NavButton(iconName: "sidebar.left")
            Spacer()
            HStack(alignment: .center,spacing: 8) {
                NavButton(iconName: "arrow.backward")
                NavButton(iconName: "arrow.forward")
            }
            
        }
    }
}
