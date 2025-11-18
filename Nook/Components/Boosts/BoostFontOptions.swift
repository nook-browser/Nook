//
//  BoostFontOptions.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI

struct BoostFontOptions: View {
    @Binding var config: BoostConfig
    var onConfigChange: (BoostConfig) -> Void

    var body: some View {
        HStack(spacing: 8) {
            BoostFontOptionSize(
                pageZoom: Binding(
                    get: { config.pageZoom },
                    set: {
                        config.pageZoom = $0
                        onConfigChange(config)
                    }
                )
            )
            BoostFontOptionCase(
                textTransform: Binding(
                    get: { config.textTransform },
                    set: {
                        config.textTransform = $0
                        onConfigChange(config)
                    }
                )
            )
        }
    }
}

#Preview {
    @Previewable @State var config = BoostConfig()
    BoostFontOptions(config: $config) { _ in }
        .frame(width: 300, height: 300)
        .background(.white)
}

enum FontSizes: Int {
    case percent90 = 90
    case percent100 = 100
    case percent110 = 110
    case percent125 = 125
    case percent150 = 150

    var color: AnyGradient {
        switch self {
        case .percent90: return Color.blue.gradient
        case .percent100: return Color.clear.gradient
        case .percent110: return Color.yellow.gradient
        case .percent125: return Color.orange.gradient
        case .percent150: return Color.red.gradient
        }
    }

    var displayName: String {
        switch self {
        case .percent90: return "90%"
        case .percent100: return "Size"
        case .percent110: return "110%"
        case .percent125: return "125%"
        case .percent150: return "150%"
        }
    }
}

enum FontCases {
    case uppercase
    case lowercase
    case titlecase
    case normal

    var text: String {
        switch self {
        case .uppercase: return "AA"
        case .lowercase: return "aa"
        case .titlecase: return "Aa"
        case .normal: return "Case"
        }
    }

    var color: AnyGradient {
        switch self {
        case .uppercase: return Color.orange.gradient
        case .lowercase: return Color.red.gradient
        case .titlecase: return Color.yellow.gradient
        case .normal: return Color.clear.gradient
        }
    }
}

struct BoostFontOptionSize: View {
    @Binding var pageZoom: Int
    @State private var isHovering: Bool = false
    
    private var currentSize: FontSizes {
        FontSizes(rawValue: pageZoom) ?? .percent100
    }

    var body: some View {
        Button {
            cycleSize()
        } label: {
            Text(currentSize.displayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    currentSize == .percent100 ? .black.opacity(0.75) : .white
                )
                .padding(.vertical, 12)
                .frame(width: 70)
                .background(currentSize.color)
                .background(
                    currentSize == .percent100 ? .black.opacity(0.07) : .clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovering ? .black.opacity(0.03) : .clear)
                }
        }
        .buttonStyle(ScaleButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: pageZoom)
        .onHover { state in
            isHovering = state
        }
    }

    private func cycleSize() {
        switch currentSize {
        case .percent100:
            pageZoom = 110
        case .percent110:
            pageZoom = 125
        case .percent125:
            pageZoom = 150
        case .percent150:
            pageZoom = 90
        case .percent90:
            pageZoom = 100
        }
    }
}
struct BoostFontOptionCase: View {
    @Binding var textTransform: String
    @State private var isHovering: Bool = false
    
    private var currentCase: FontCases {
        switch textTransform {
        case "uppercase": return .uppercase
        case "lowercase": return .lowercase
        case "capitalize": return .titlecase
        default: return .normal
        }
    }

    var body: some View {
        Button {
            cycleCase()
        } label: {
            Text(currentCase.text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    currentCase == .normal ? .black.opacity(0.75) : .white
                )
                .padding(.vertical, 12)
                .frame(width: 70)
                .background(currentCase.color)
                .background(
                    currentCase == .normal ? .black.opacity(0.07) : .clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHovering ? .black.opacity(0.03) : .clear)
                }
        }
        .buttonStyle(ScaleButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: textTransform)
        .onHover { state in
            isHovering = state
        }
    }

    private func cycleCase() {
        switch currentCase {
        case .normal:
            textTransform = "uppercase"
        case .uppercase:
            textTransform = "lowercase"
        case .lowercase:
            textTransform = "capitalize"
        case .titlecase:
            textTransform = "none"
        }
    }
}
