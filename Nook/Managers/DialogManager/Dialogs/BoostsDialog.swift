//
//  BoostsDialog.swift
//  Nook
//
//  Created by Claude on 11/11/2025.
//

import SwiftUI

struct BoostsDialog: View {
    @Binding var config: BoostConfig
    let onApplyLive: ((BoostConfig) -> Void)?

    @State private var selectedColor: Color
    @State private var updateWorkItem: DispatchWorkItem?

    init(
        config: Binding<BoostConfig>,
        onApplyLive: ((BoostConfig) -> Void)? = nil
    ) {
        _config = config
        self.onApplyLive = onApplyLive
        _selectedColor = State(initialValue: Color(hex: config.wrappedValue.tintColor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Circular color canvas (like gradient editor)
            BoostColorCanvas(selectedColor: $selectedColor) { color in
                config.tintColor = color.toHexString() ?? "#FF6B6B"
                applyLiveDebounced()
            }

            // Sliders for fine-tuning
            VStack(alignment: .leading, spacing: 12) {
                // Brightness
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "sun.max")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Text("Brightness")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(config.brightness)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(config.brightness) },
                            set: {
                                config.brightness = Int($0)
                                applyLiveDebounced()
                            }
                        ), in: 50...150, step: 1
                    )
                    .tint(.primary.opacity(0.3))
                }

                // Contrast
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Text("Contrast")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(config.contrast)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(config.contrast) },
                            set: {
                                config.contrast = Int($0)
                                applyLiveDebounced()
                            }
                        ), in: 50...150, step: 1
                    )
                    .tint(.primary.opacity(0.3))
                }

                // Tint Strength
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "paintpalette")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Text("Tint Strength")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(config.tintStrength)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(config.tintStrength) },
                            set: {
                                config.tintStrength = Int($0)
                                applyLiveDebounced()
                            }
                        ), in: 0...100, step: 1
                    )
                    .tint(.primary.opacity(0.3))
                }
            }
        }
        .onAppear {
            // Apply initial config on appear
            applyLive()
        }
    }

    private func applyLive() {
        onApplyLive?(config)
    }

    private func applyLiveDebounced() {
        // Cancel previous work item
        updateWorkItem?.cancel()

        // Create new work item
        let workItem = DispatchWorkItem { [config] in
            Task { @MainActor in
                self.onApplyLive?(config)
            }
        }

        updateWorkItem = workItem

        // Execute after short delay for smoothness
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
}

#Preview {
    @Previewable @State var config = BoostConfig()

    return BoostsDialog(
        config: $config,
        onApplyLive: { _ in }
    )
    .padding(40)
    .environmentObject(GradientColorManager())
}
