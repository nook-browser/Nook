//
//  BoostUI.swift
//  nook-components
//
//  Created by Maciek Bagiński on 12/11/2025.
//

import SwiftUI

struct BoostUI: View {
    @Binding var config: BoostConfig
    var onConfigChange: ((BoostConfig) -> Void)?

    @State private var selectedColor: Color
    @State private var updateWorkItem: DispatchWorkItem?

    init(
        config: Binding<BoostConfig>,
        onConfigChange: ((BoostConfig) -> Void)? = nil
    ) {
        _config = config
        self.onConfigChange = onConfigChange
        _selectedColor = State(initialValue: Color(hex: config.wrappedValue.tintColor))
    }

    var body: some View {
        VStack(spacing: 15) {
            VStack(spacing: 0) {
                BoostHeader()
                Rectangle()
                    .fill(.black.opacity(0.07))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: 15) {
                BoostColorPicker(selectedColor: $selectedColor) { color in
                    config.tintColor = color.toHexString() ?? "#FF6B6B"
                    applyConfigChangeDebounced()
                }

                BoostOptions(
                    brightness: Binding(
                        get: { config.brightness },
                        set: {
                            config.brightness = $0
                            applyConfigChangeDebounced()
                        }
                    ),
                    contrast: Binding(
                        get: { config.contrast },
                        set: {
                            config.contrast = $0
                            applyConfigChangeDebounced()
                        }
                    ),
                    tintStrength: Binding(
                        get: { config.tintStrength },
                        set: {
                            config.tintStrength = $0
                            applyConfigChangeDebounced()
                        }
                    ),
                    mode: Binding(
                        get: { config.mode },
                        set: {
                            config.mode = $0
                            applyConfigChangeDebounced()
                        }
                    ),
                    onValueChange: {
                        applyConfigChangeDebounced()
                    }
                )

                BoostFonts(config: $config, onConfigChange: { newConfig in
                    config = newConfig
                    applyConfigChangeDebounced()
                })
                BoostFontOptions(config: $config, onConfigChange: { newConfig in
                    config = newConfig
                    applyConfigChangeDebounced()
                })
                BoostZapButton(isActive: .constant(false), onClick: {
                })
                BoostCodeButton(isActive: false, onClick: {
                })
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .frame(width: 185)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            onConfigChange?(config)
        }
    }

    private func applyConfigChangeDebounced() {
        updateWorkItem?.cancel()

        let workItem = DispatchWorkItem { [config] in
            Task { @MainActor in
                self.onConfigChange?(config)
            }
        }

        updateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
}

#Preview {
    @Previewable @State var config = BoostConfig()

    return BoostUI(
        config: $config,
        onConfigChange: { newConfig in
            print("Config changed: \(newConfig)")
        }
    )
}
