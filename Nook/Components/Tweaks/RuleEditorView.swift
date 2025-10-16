//
//  RuleEditorView.swift
//  Nook
//
//  Editor for individual tweak rules.
//

import SwiftUI

struct RuleEditorView: View {
    let rule: TweakRuleEntity?
    let onSave: (TweakRuleEntity) -> Void
    let onCancel: () -> Void

    @State private var selectedType: TweakRuleType = .colorAdjustment
    @State private var selector: String = ""
    @State private var priority: Int = 0
    @State private var isEnabled: Bool = true

    // Color adjustment properties
    @State private var colorAdjustmentType: ColorAdjustmentType = .hueRotate
    @State private var colorAmount: Double = 0.0

    // Font override properties
    @State private var fontFamily: String = ""
    @State private var fontWeight: String = "normal"
    @State private var fontFallback: String = "system-ui"

    // Size transform properties
    @State private var scale: Double = 1.0
    @State private var zoom: Double = 1.0

    // Case transform properties
    @State private var caseTransformType: CaseTransformType = .uppercase

    // Custom code properties
    @State private var customCSS: String = ""
    @State private var customJavaScript: String = ""

    private var isEditing: Bool { rule != nil }

    init(rule: TweakRuleEntity?, onSave: @escaping (TweakRuleEntity) -> Void, onCancel: @escaping () -> Void) {
        self.rule = rule
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(isEditing ? "Edit Rule" : "New Rule")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Configure how this rule will modify the website")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Rule type selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Rule Type")
                    .font(.headline)

                Picker("Rule Type", selection: $selectedType) {
                    ForEach(TweakRuleType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Type-specific configuration
            typeSpecificConfiguration

            Divider()

            // Common settings
            VStack(alignment: .leading, spacing: 16) {
                Text("Common Settings")
                    .font(.headline)

                // CSS Selector (not for all types)
                if requiresSelector {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CSS Selector")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField(selectorPlaceholder, text: $selector)
                            .textFieldStyle(.roundedBorder)
                        Text(selectorHelpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Priority
                VStack(alignment: .leading, spacing: 4) {
                    Text("Priority")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    HStack {
                        Slider(value: Binding(
                            get: { Double(priority) },
                            set: { priority = Int($0) }
                        ), in: 0...10, step: 1)
                        Text("\(priority)")
                            .font(.caption)
                            .frame(width: 30)
                    }
                    Text("Higher priority rules override lower priority ones")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Enabled toggle
                Toggle("Enable this rule", isOn: $isEnabled)
            }

            Spacer()

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    saveRule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 500, height: 600)
        .onAppear {
            loadRuleData()
        }
    }

    @ViewBuilder
    private var typeSpecificConfiguration: some View {
        switch selectedType {
        case .colorAdjustment:
            colorAdjustmentConfiguration

        case .fontOverride:
            fontOverrideConfiguration

        case .sizeTransform:
            sizeTransformConfiguration

        case .caseTransform:
            caseTransformConfiguration

        case .elementHide:
            elementHideConfiguration

        case .customCSS:
            customCSSConfiguration

        case .customJavaScript:
            customJavaScriptConfiguration
        }
    }

    // MARK: - Type-specific configurations

    private var colorAdjustmentConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Color Adjustment")
                .font(.headline)

            Picker("Adjustment Type", selection: $colorAdjustmentType) {
                ForEach(ColorAdjustmentType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Amount")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(colorAmount, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Slider(value: $colorAmount, in: colorRange, step: 0.1)

                Text(colorAdjustmentHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fontOverrideConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Font Override")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Font Family")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("e.g., Arial, Helvetica, sans-serif", text: $fontFamily)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Font Weight")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Picker("Font Weight", selection: $fontWeight) {
                    Text("Normal").tag("normal")
                    Text("Bold").tag("bold")
                    Text("Light").tag("light")
                    Text("Medium").tag("medium")
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Fallback Font")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("system-ui", text: $fontFallback)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var sizeTransformConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Size Transform")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scale")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(scale, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $scale, in: 0.1...3.0, step: 0.1)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Zoom")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(zoom, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $zoom, in: 0.5...2.0, step: 0.1)
            }
        }
    }

    private var caseTransformConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Case Transform")
                .font(.headline)

            Picker("Transform Type", selection: $caseTransformType) {
                ForEach(CaseTransformType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    private var elementHideConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hide Elements")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("CSS Selector")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField(".advertisement, .sidebar, #popup", text: $selector)
                    .textFieldStyle(.roundedBorder)
                Text("Enter CSS selectors for elements to hide")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var customCSSConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom CSS")
                .font(.headline)

            Text("Enter CSS rules to apply to the page")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $customCSS)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.controlBackgroundColor), lineWidth: 1)
                )
        }
    }

    private var customJavaScriptConfiguration: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom JavaScript")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("JavaScript runs in a sandboxed environment with limited APIs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: $customJavaScript)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(.controlBackgroundColor), lineWidth: 1)
                )
        }
    }

    // MARK: - Helper properties

    private var requiresSelector: Bool {
        switch selectedType {
        case .colorAdjustment, .fontOverride, .sizeTransform, .caseTransform, .elementHide:
            return true
        case .customCSS, .customJavaScript:
            return false
        }
    }

    private var selectorPlaceholder: String {
        switch selectedType {
        case .colorAdjustment, .fontOverride, .sizeTransform, .caseTransform:
            return "body, .content, #main"
        case .elementHide:
            return ".advertisement, .sidebar, #popup"
        default:
            return ""
        }
    }

    private var selectorHelpText: String {
        switch selectedType {
        case .colorAdjustment:
            return "Target elements for color adjustment"
        case .fontOverride:
            return "Target elements for font changes"
        case .sizeTransform:
            return "Target elements for size transformation"
        case .caseTransform:
            return "Target elements for text case changes"
        case .elementHide:
            return "CSS selectors for elements to hide"
        default:
            return ""
        }
    }

    private var colorRange: ClosedRange<Double> {
        switch colorAdjustmentType {
        case .hueRotate:
            return 0...360
        case .brightness, .contrast, .saturation:
            return 0...200
        case .invert:
            return 0...100
        }
    }

    private var colorAdjustmentHelpText: String {
        switch colorAdjustmentType {
        case .hueRotate:
            return "Rotate colors around the color wheel (0-360 degrees)"
        case .brightness:
            return "Adjust brightness (0-200%, 100% is normal)"
        case .contrast:
            return "Adjust contrast (0-200%, 100% is normal)"
        case .saturation:
            return "Adjust color saturation (0-200%, 100% is normal)"
        case .invert:
            return "Invert colors (0-100%)"
        }
    }

    private var canSave: Bool {
        switch selectedType {
        case .colorAdjustment:
            return !selector.isEmpty
        case .fontOverride:
            return !selector.isEmpty && !fontFamily.isEmpty
        case .sizeTransform:
            return !selector.isEmpty
        case .caseTransform:
            return !selector.isEmpty
        case .elementHide:
            return !selector.isEmpty
        case .customCSS:
            return !customCSS.isEmpty
        case .customJavaScript:
            return !customJavaScript.isEmpty
        }
    }

    // MARK: - Data management

    private func loadRuleData() {
        if let rule = rule {
            selectedType = rule.type
            selector = rule.selector ?? ""
            priority = rule.priority
            isEnabled = rule.isEnabled

            switch rule.type {
            case .colorAdjustment:
                if let adjustment = rule.getColorAdjustment() {
                    colorAdjustmentType = adjustment.type
                    colorAmount = adjustment.amount
                }

            case .fontOverride:
                if let font = rule.getFontOverride() {
                    fontFamily = font.fontFamily
                    fontWeight = font.weight
                    fontFallback = font.fallback
                }

            case .sizeTransform:
                if let transform = rule.getSizeTransform() {
                    scale = transform.scale
                    zoom = transform.zoom
                }

            case .caseTransform:
                if let caseType = rule.getCaseTransform() {
                    caseTransformType = caseType
                }

            case .customCSS:
                customCSS = rule.getCustomCSS() ?? ""

            case .customJavaScript:
                customJavaScript = rule.getCustomJavaScript() ?? ""

            case .elementHide:
                // Selector already loaded above - no additional data needed
                break
            }
        }
    }

    private func saveRule() {
        let savedRule: TweakRuleEntity

        if let existingRule = rule {
            savedRule = existingRule
        } else {
            savedRule = TweakRuleEntity(
                type: selectedType,
                selector: selector.isEmpty ? nil : selector,
                priority: priority,
                createdDate: Date()
            )
        }

        savedRule.isEnabled = isEnabled
        savedRule.priority = priority
        savedRule.selector = selector.isEmpty ? nil : selector

        // Set type-specific values
        switch selectedType {
        case .colorAdjustment:
            savedRule.setColorAdjustment(type: colorAdjustmentType, amount: colorAmount)

        case .fontOverride:
            savedRule.setFontOverride(fontFamily: fontFamily, weight: fontWeight, fallback: fontFallback)

        case .sizeTransform:
            savedRule.setSizeTransform(scale: scale, zoom: zoom)

        case .caseTransform:
            savedRule.setCaseTransform(type: caseTransformType)

        case .customCSS:
            savedRule.setCustomCSS(customCSS)

        case .customJavaScript:
            savedRule.setCustomJavaScript(customJavaScript)

        case .elementHide:
            // Selector already set
            break
        }

        onSave(savedRule)
    }
}

#Preview {
    RuleEditorView(
        rule: nil,
        onSave: { _ in },
        onCancel: { }
    )
}