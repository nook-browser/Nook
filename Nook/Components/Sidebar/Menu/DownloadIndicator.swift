//
//  DownloadIndicator.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/09/2025.
//


import SwiftUI

struct DownloadIndicator: View {
    @EnvironmentObject var browserManager: BrowserManager
    
    var currentDownload: Download? {
        browserManager.downloadManager.activeDownloads.first
    }
    
    var body: some View {
        Group {
            if let download = currentDownload {
                CircularProgressView(progress: download.progress)
                    .transition(.slideFromTop)
            }
        }
        .animation(.spring(duration: 0.55, bounce: 0.6), value: currentDownload?.id)
    }
}

extension AnyTransition {
    static var slideFromTop: AnyTransition {
        .asymmetric(
            insertion: .offset(y: -10).combined(with: .opacity),
            removal: .offset(y: -30).combined(with: .opacity)
        )
    }
}

struct CircularProgressView: View {
    @Environment(\.colorScheme) var colorScheme
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .frame(width: 20, height: 20)
            Image(systemName: "arrow.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(hex: colorScheme == .dark ? "FFFFFF" :"0F2B1F"))
                .frame(width: 20, height: 20)

            Circle()
                .stroke(
                    Color(hex: colorScheme == .dark ? "FFFFFF" : "0F2B1F").opacity(0.4),
                    lineWidth: 4
                )
                .frame(width: 20, height: 20)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color(hex: colorScheme == .dark ? "FFFFFF" :"0F2B1F"),
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut, value: progress)
                .frame(width: 20, height: 20)
 

        }
    }
}
