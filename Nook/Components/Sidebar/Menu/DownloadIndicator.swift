//
//  DownloadIndicator.swift
//  Nook
//
//  Created by Maciek Bagiński on 13/09/2025.
//

import SwiftUI
import NookDesign

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
        .animation(NookDesign.Motion.spring, value: currentDownload?.id)
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
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .frame(width: 20, height: 20)
            Image(systemName: "arrow.down")
                .font(NookDesign.Font.caption)
                .foregroundStyle(Color.primary)
                .frame(width: 20, height: 20)

            Circle()
                .stroke(
                    Color.secondary.opacity(0.4),
                    lineWidth: 4
                )
                .frame(width: 20, height: 20)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.primary,
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(NookDesign.Motion.standard, value: progress)
                .frame(width: 20, height: 20)
        }
    }
}
