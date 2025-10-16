//
//  TweakModels.swift
//  Nook
//
//  SwiftData models for persisting user-defined website customizations (Tweaks).
//

import Foundation
import SwiftData

// MARK: - Tweak Rule Types
enum TweakRuleType: String, CaseIterable, Codable {
    case colorAdjustment = "color_adjustment"
    case fontOverride = "font_override"
    case sizeTransform = "size_transform"
    case caseTransform = "case_transform"
    case elementHide = "element_hide"
    case customCSS = "custom_css"
    case customJavaScript = "custom_javascript"

    var displayName: String {
        switch self {
        case .colorAdjustment:
            return "Color Adjustment"
        case .fontOverride:
            return "Font Override"
        case .sizeTransform:
            return "Size Transform"
        case .caseTransform:
            return "Case Transform"
        case .elementHide:
            return "Hide Element"
        case .customCSS:
            return "Custom CSS"
        case .customJavaScript:
            return "Custom JavaScript"
        }
    }
}

// MARK: - Color Adjustment Types
enum ColorAdjustmentType: String, CaseIterable, Codable {
    case hueRotate = "hue_rotate"
    case brightness = "brightness"
    case contrast = "contrast"
    case saturation = "saturation"
    case invert = "invert"

    var displayName: String {
        switch self {
        case .hueRotate:
            return "Hue Rotate"
        case .brightness:
            return "Brightness"
        case .contrast:
            return "Contrast"
        case .saturation:
            return "Saturation"
        case .invert:
            return "Invert"
        }
    }
}

// MARK: - Case Transform Types
enum CaseTransformType: String, CaseIterable, Codable {
    case uppercase = "uppercase"
    case lowercase = "lowercase"
    case capitalize = "capitalize"

    var displayName: String {
        switch self {
        case .uppercase:
            return "UPPERCASE"
        case .lowercase:
            return "lowercase"
        case .capitalize:
            return "Capitalize"
        }
    }
}

// MARK: - Main Tweak Entity
@Model
final class TweakEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var urlPattern: String // Domain or URL pattern matching
    var isEnabled: Bool
    var createdDate: Date
    var lastModifiedDate: Date
    var profileId: UUID? // Optional profile association
    var author: String? // For shared tweaks
    var tweakDescription: String?
    var version: Int

    init(
        id: UUID = UUID(),
        name: String,
        urlPattern: String,
        isEnabled: Bool = true,
        createdDate: Date = Date(),
        lastModifiedDate: Date = Date(),
        profileId: UUID? = nil,
        author: String? = nil,
        tweakDescription: String? = nil,
        version: Int = 1
    ) {
        self.id = id
        self.name = name
        self.urlPattern = urlPattern
        self.isEnabled = isEnabled
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
        self.profileId = profileId
        self.author = author
        self.tweakDescription = tweakDescription
        self.version = version
    }

    // Update last modified date when entity changes
    func markAsModified() {
        self.lastModifiedDate = Date()
    }
}

// MARK: - Tweak Rule Entity
@Model
final class TweakRuleEntity {
    @Attribute(.unique) var id: UUID
    var type: TweakRuleType
    var selector: String? // CSS selector or target element
    var value: String? // JSON-encoded value based on rule type
    var isEnabled: Bool
    var priority: Int // Higher priority rules override lower ones
    var createdDate: Date

    // Relationship to parent tweak
    @Relationship(deleteRule: .cascade) var tweak: TweakEntity?

    init(
        id: UUID = UUID(),
        type: TweakRuleType,
        selector: String? = nil,
        value: String? = nil,
        isEnabled: Bool = true,
        priority: Int = 0,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.selector = selector
        self.value = value
        self.isEnabled = isEnabled
        self.priority = priority
        self.createdDate = createdDate
    }
}

// MARK: - Value Encoders/Decoders
extension TweakRuleEntity {

    // MARK: - Color Adjustment Values
    func setColorAdjustment(type: ColorAdjustmentType, amount: Double) {
        let value: [String: Any] = [
            "adjustmentType": type.rawValue,
            "amount": amount
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: value) {
            self.value = jsonData.base64EncodedString()
        }
    }

    func getColorAdjustment() -> (type: ColorAdjustmentType, amount: Double)? {
        guard let valueString = value,
              let data = Data(base64Encoded: valueString),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let typeString = dict["adjustmentType"],
              let type = ColorAdjustmentType(rawValue: typeString),
              let amountString = dict["amount"],
              let amount = Double(amountString) else {
            return nil
        }
        return (type: type, amount: amount)
    }

    // MARK: - Font Override Values
    func setFontOverride(fontFamily: String, weight: String? = nil, fallback: String? = nil) {
        let value: [String: Any] = [
            "fontFamily": fontFamily,
            "weight": weight ?? "normal",
            "fallback": fallback ?? "system-ui"
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: value) {
            self.value = jsonData.base64EncodedString()
        }
    }

    func getFontOverride() -> (fontFamily: String, weight: String, fallback: String)? {
        guard let valueString = value,
              let data = Data(base64Encoded: valueString),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let fontFamily = dict["fontFamily"] else {
            return nil
        }
        return (
            fontFamily: fontFamily,
            weight: dict["weight"] ?? "normal",
            fallback: dict["fallback"] ?? "system-ui"
        )
    }

    // MARK: - Size Transform Values
    func setSizeTransform(scale: Double, zoom: Double? = nil) {
        let value: [String: Any] = [
            "scale": scale,
            "zoom": zoom ?? 1.0
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: value) {
            self.value = jsonData.base64EncodedString()
        }
    }

    func getSizeTransform() -> (scale: Double, zoom: Double)? {
        guard let valueString = value,
              let data = Data(base64Encoded: valueString),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let scaleString = dict["scale"],
              let scale = Double(scaleString),
              let zoomString = dict["zoom"],
              let zoom = Double(zoomString) else {
            return nil
        }
        return (scale: scale, zoom: zoom)
    }

    // MARK: - Case Transform Values
    func setCaseTransform(type: CaseTransformType) {
        self.value = type.rawValue
    }

    func getCaseTransform() -> CaseTransformType? {
        guard let valueString = value else { return nil }
        return CaseTransformType(rawValue: valueString)
    }

    // MARK: - Direct Access for Simple Types
    func setCustomCSS(_ css: String) {
        self.value = css
    }

    func getCustomCSS() -> String? {
        return value
    }

    func setCustomJavaScript(_ js: String) {
        self.value = js
    }

    func getCustomJavaScript() -> String? {
        return value
    }

    // Element hiding just uses the selector property
    func getElementHideSelector() -> String? {
        return selector
    }
}

// MARK: - URL Pattern Matching
extension TweakEntity {

    /// Checks if this tweak applies to the given URL
    func matches(url: URL) -> Bool {
        guard isEnabled else { return false }

        let urlString = url.absoluteString
        let host = url.host ?? ""
        let scheme = url.scheme ?? ""

        // Support different pattern formats:
        // 1. Exact domain: "example.com"
        // 2. Wildcard domain: "*.example.com"
        // 3. Full URL pattern: "https://example.com/*"
        // 4. Path pattern: "example.com/posts/*"

        let pattern = urlPattern.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle wildcard patterns
        if pattern.hasPrefix("*.") {
            let baseDomain = String(pattern.dropFirst(2))
            return host == baseDomain || host.hasSuffix("." + baseDomain)
        }

        // Handle exact domain match
        if !pattern.contains("://") && !pattern.contains("/") {
            return host == pattern || host.hasSuffix("." + pattern)
        }

        // Handle full URL patterns
        var fullPattern = pattern
        if !fullPattern.contains("://") {
            fullPattern = "*://\(fullPattern)"
        }

        // Convert to regex pattern
        let regexPattern = fullPattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: urlString.utf16.count)
            return regex.firstMatch(in: urlString, options: [], range: range) != nil
        } catch {
            // Fallback to simple string comparison if regex fails
            return urlString.contains(pattern)
        }
    }
}

// MARK: - Runtime Models (not persisted)
struct AppliedTweak {
    let id: UUID
    let name: String
    let urlPattern: String
    let rules: [AppliedTweakRule]

    init(from entity: TweakEntity, rules: [TweakRuleEntity]) {
        self.id = entity.id
        self.name = entity.name
        self.urlPattern = entity.urlPattern
        self.rules = rules.compactMap { AppliedTweakRule(from: $0) }
    }
}

struct AppliedTweakRule {
    let id: UUID
    let type: TweakRuleType
    let selector: String?
    let value: String?
    let priority: Int

    init?(from entity: TweakRuleEntity) {
        guard entity.isEnabled else { return nil }
        self.id = entity.id
        self.type = entity.type
        self.selector = entity.selector
        self.value = entity.value
        self.priority = entity.priority
    }
}

// MARK: - AppliedTweakRule Helper Methods
extension AppliedTweakRule {
    func getColorAdjustment() -> (type: ColorAdjustmentType, amount: Double)? {
        guard let valueString = value,
              let data = Data(base64Encoded: valueString),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let typeString = dict["adjustmentType"],
              let type = ColorAdjustmentType(rawValue: typeString),
              let amountString = dict["amount"],
              let amount = Double(amountString) else {
            return nil
        }
        return (type: type, amount: amount)
    }

    func getFontOverride() -> (fontFamily: String, weight: String, fallback: String)? {
        guard let valueString = value,
              let data = Data(base64Encoded: valueString),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let fontFamily = dict["fontFamily"] else {
            return nil
        }
        return (
            fontFamily: fontFamily,
            weight: dict["weight"] ?? "normal",
            fallback: dict["fallback"] ?? "system-ui"
        )
    }

    func getSizeTransform() -> (scale: Double, zoom: Double)? {
        guard let valueString = value,
              let data = Data(base64Encoded: valueString),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let scaleString = dict["scale"],
              let scale = Double(scaleString),
              let zoomString = dict["zoom"],
              let zoom = Double(zoomString) else {
            return nil
        }
        return (scale: scale, zoom: zoom)
    }

    func getCaseTransform() -> CaseTransformType? {
        guard let valueString = value else { return nil }
        return CaseTransformType(rawValue: valueString)
    }

    func getCustomCSS() -> String? {
        return type == .customCSS ? value : nil
    }

    func getCustomJavaScript() -> String? {
        return type == .customJavaScript ? value : nil
    }

    func getElementHideSelector() -> String? {
        return type == .elementHide ? selector : nil
    }
}