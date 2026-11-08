//
//  CustomTheme.swift
//  osaurus
//
//  User-customizable theme model with full color palette, background, glass, and typography support
//

import AppKit
import Foundation
import SwiftUI

// MARK: - Theme Metadata

/// Metadata for a custom theme
public struct ThemeMetadata: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var version: String
    public var author: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "Custom Theme",
        version: String = "1.0",
        author: String = "User",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        author = try container.decode(String.self, forKey: .author)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Theme Library Metadata

/// Where a theme entered the local library. This is intentionally persisted
/// with custom themes so the library can distinguish hand-authored themes
/// from file imports and share-link installs after relaunch.
public enum ThemeLibrarySource: String, Codable, CaseIterable, Sendable {
    case builtIn
    case local
    case imported
    case shared
}

public struct ThemeLibraryInfo: Codable, Equatable, Sendable {
    public var source: ThemeLibrarySource
    public var importedAt: Date?
    public var sharedAt: Date?
    public var remoteHash: String?
    public var remoteURL: String?
    public var sourceDetail: String?

    public init(
        source: ThemeLibrarySource = .local,
        importedAt: Date? = nil,
        sharedAt: Date? = nil,
        remoteHash: String? = nil,
        remoteURL: String? = nil,
        sourceDetail: String? = nil
    ) {
        self.source = source
        self.importedAt = importedAt
        self.sharedAt = sharedAt
        self.remoteHash = remoteHash
        self.remoteURL = remoteURL
        self.sourceDetail = sourceDetail
    }
}

// MARK: - Theme Colors

/// All customizable colors in a theme
public struct ThemeColors: Codable, Equatable, Sendable {
    // Primary colors
    public var primaryText: String
    public var secondaryText: String
    public var tertiaryText: String

    // Background colors
    public var primaryBackground: String
    public var secondaryBackground: String
    public var tertiaryBackground: String

    // Sidebar colors
    public var sidebarBackground: String
    public var sidebarSelectedBackground: String

    // Accent colors
    public var accentColor: String
    public var accentColorLight: String

    // Border colors
    public var primaryBorder: String
    public var secondaryBorder: String
    public var focusBorder: String

    // Status colors
    public var successColor: String
    public var warningColor: String
    public var errorColor: String
    public var infoColor: String

    // Component specific
    public var cardBackground: String
    public var cardBorder: String
    public var buttonBackground: String
    public var buttonBorder: String
    public var inputBackground: String
    public var inputBorder: String
    public var glassTintOverlay: String
    public var codeBlockBackground: String

    // Shadow
    public var shadowColor: String

    // Selection (text highlight)
    public var selectionColor: String

    // Placeholder
    public var placeholderText: String?

    // Cursor
    public var cursorColor: String

    // Default dark theme colors - WCAG AA compliant
    public init(
        primaryText: String = "#f9fafb",  // ~17:1 contrast ✓
        secondaryText: String = "#a1a1aa",  // ~8:1 contrast ✓ (was #9ca3af)
        tertiaryText: String = "#8b8b94",  // ~5.5:1 contrast ✓ (was #6b7280, ~3.5:1)
        primaryBackground: String = "#0f0f10",
        secondaryBackground: String = "#18181b",
        tertiaryBackground: String = "#27272a",
        sidebarBackground: String = "#141416",
        sidebarSelectedBackground: String = "#2a2a2e",
        accentColor: String = "#60a5fa",  // Higher contrast for links (was #3b82f6)
        accentColorLight: String = "#93c5fd",
        primaryBorder: String = "#3f3f46",  // Improved visibility (was #27272a)
        secondaryBorder: String = "#52525b",  // Improved visibility (was #3f3f46)
        focusBorder: String = "#60a5fa",  // Matches accentColor for consistency
        successColor: String = "#22c55e",  // Good contrast on dark ✓
        warningColor: String = "#fbbf24",  // Brighter for dark bg ✓ (was #f59e0b)
        errorColor: String = "#f87171",  // Brighter for dark bg ✓ (was #ef4444)
        infoColor: String = "#60a5fa",  // Brighter blue for dark bg (was #3b82f6)
        cardBackground: String = "#18181b",
        cardBorder: String = "#3f3f46",
        buttonBackground: String = "#18181b",
        buttonBorder: String = "#3f3f46",
        inputBackground: String = "#18181b",
        inputBorder: String = "#52525b",  // Improved visibility (was #3f3f46)
        glassTintOverlay: String = "#00000030",
        codeBlockBackground: String = "#00000059",
        shadowColor: String = "#000000",
        selectionColor: String = "#3b82f680",
        cursorColor: String = "#3b82f6",
        placeholderText: String? = "#a1a1aa"  // Matches secondaryText for better visibility
    ) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tertiaryText = tertiaryText
        self.primaryBackground = primaryBackground
        self.secondaryBackground = secondaryBackground
        self.tertiaryBackground = tertiaryBackground
        self.sidebarBackground = sidebarBackground
        self.sidebarSelectedBackground = sidebarSelectedBackground
        self.accentColor = accentColor
        self.accentColorLight = accentColorLight
        self.primaryBorder = primaryBorder
        self.secondaryBorder = secondaryBorder
        self.focusBorder = focusBorder
        self.successColor = successColor
        self.warningColor = warningColor
        self.errorColor = errorColor
        self.infoColor = infoColor
        self.cardBackground = cardBackground
        self.cardBorder = cardBorder
        self.buttonBackground = buttonBackground
        self.buttonBorder = buttonBorder
        self.inputBackground = inputBackground
        self.inputBorder = inputBorder
        self.glassTintOverlay = glassTintOverlay
        self.codeBlockBackground = codeBlockBackground
        self.shadowColor = shadowColor
        self.selectionColor = selectionColor
        self.cursorColor = cursorColor
        self.placeholderText = placeholderText
    }

    /// Create colors from dark theme defaults
    public static var darkDefaults: ThemeColors { ThemeColors() }

    /// Create colors from light theme defaults - WCAG AA compliant
    public static var lightDefaults: ThemeColors {
        ThemeColors(
            primaryText: "#1a1a1a",  // ~17:1 contrast ✓
            secondaryText: "#525252",  // ~7:1 contrast ✓ (was #6b7280, ~5:1)
            tertiaryText: "#6b6b6b",  // ~5.5:1 contrast ✓ (was #9ca3af, ~2.7:1)
            primaryBackground: "#ffffff",
            secondaryBackground: "#f9fafb",
            tertiaryBackground: "#f3f4f6",
            sidebarBackground: "#f5f5f7",
            sidebarSelectedBackground: "#e8e8ed",
            accentColor: "#1d4ed8",  // Darker blue for better contrast (was #2563eb)
            accentColorLight: "#3b82f6",
            primaryBorder: "#d1d5db",  // Improved visibility (was #e5e7eb)
            secondaryBorder: "#e5e7eb",  // Decorative (was #f3f4f6)
            focusBorder: "#2563eb",
            successColor: "#15803d",  // ~4.5:1 on white ✓ (was #10b981, ~2.5:1)
            warningColor: "#a16207",  // ~4.5:1 on white ✓ (was #f59e0b, ~2.1:1)
            errorColor: "#dc2626",  // ~4.5:1 on white ✓ (was #ef4444, ~3.1:1)
            infoColor: "#1d4ed8",  // ~7:1 on white ✓ (was #3b82f6, ~3.8:1)
            cardBackground: "#ffffff",
            cardBorder: "#d1d5db",  // Improved visibility
            buttonBackground: "#ffffff",
            buttonBorder: "#9ca3af",  // ~3:1 for UI ✓ (was #d1d5db, ~1.5:1)
            inputBackground: "#ffffff",
            inputBorder: "#9ca3af",  // ~3:1 for UI ✓ (was #d1d5db, ~1.5:1)
            glassTintOverlay: "#0000001f",
            codeBlockBackground: "#00000014",
            shadowColor: "#000000",
            selectionColor: "#2563eb50",
            cursorColor: "#2563eb",
            placeholderText: "#525252"  // Matches secondaryText for better visibility
        )
    }
}

// MARK: - System Accent Derivation

extension ThemeColors {
    /// Returns a copy with the accent-adjacent colors re-derived from
    /// `accentHex`. Everything else (backgrounds, text, status colors, …)
    /// is left untouched.
    ///
    /// When `accentHex` already matches the stored `accentColor` the
    /// receiver is returned unchanged, so themes hand-tuned against the
    /// default accent keep their exact authored values.
    public func applyingAccent(_ accentHex: String, isDark: Bool) -> ThemeColors {
        guard let accent = Self.parseHexRGB(accentHex),
            Self.normalizedHex(accentHex) != Self.normalizedHex(accentColor)
        else { return self }

        let accentString = Self.formatHexRGB(accent)
        let white: (Double, Double, Double) = (255, 255, 255)
        let black: (Double, Double, Double) = (0, 0, 0)

        var derived = self
        derived.accentColor = accentString
        derived.focusBorder = accentString
        derived.cursorColor = accentString
        derived.accentColorLight = Self.formatHexRGB(Self.blend(accent, toward: white, fraction: 0.4))
        // Keep the canonical selection alphas (see darkDefault/lightDefault).
        derived.selectionColor = accentString + (isDark ? "45" : "26")
        if isDark {
            // Factors tuned so the default blue accent lands close to the
            // hand-picked #0a3d70 / #d8e8ff selected-row colors.
            derived.sidebarSelectedBackground = Self.formatHexRGB(Self.blend(accent, toward: black, fraction: 0.55))
            derived.infoColor = derived.accentColorLight
        } else {
            derived.sidebarSelectedBackground = Self.formatHexRGB(Self.blend(accent, toward: white, fraction: 0.84))
            derived.infoColor = accentString
        }
        return derived
    }

    private static func normalizedHex(_ hex: String) -> String {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    }

    private static func parseHexRGB(_ hex: String) -> (Double, Double, Double)? {
        let body = normalizedHex(hex)
        guard body.count == 6, body.allSatisfy(\.isHexDigit) else { return nil }
        var int: UInt64 = 0
        Scanner(string: body).scanHexInt64(&int)
        return (Double(int >> 16 & 0xFF), Double(int >> 8 & 0xFF), Double(int & 0xFF))
    }

    private static func formatHexRGB(_ rgb: (Double, Double, Double)) -> String {
        String(
            format: "#%02x%02x%02x",
            Int(rgb.0.rounded()),
            Int(rgb.1.rounded()),
            Int(rgb.2.rounded())
        )
    }

    private static func blend(
        _ from: (Double, Double, Double),
        toward target: (Double, Double, Double),
        fraction: Double
    ) -> (Double, Double, Double) {
        (
            from.0 + (target.0 - from.0) * fraction,
            from.1 + (target.1 - from.1) * fraction,
            from.2 + (target.2 - from.2) * fraction
        )
    }
}

// MARK: - Theme Background

/// Background configuration for the theme
public struct ThemeBackground: Codable, Equatable, Sendable {
    public enum BackgroundType: String, Codable, Sendable {
        case solid
        case gradient
        case image
    }

    public enum ImageFit: String, Codable, Sendable {
        case fill
        case fit
        case stretch
        case tile
    }

    public var type: BackgroundType
    public var solidColor: String?
    public var gradientColors: [String]?
    /// Gradient direction in degrees using the CSS convention: 0 points
    /// up (bottom to top), 90 points right, 180 points down (top to
    /// bottom, the default when unset).
    public var gradientAngle: Double?
    public var imageData: String?  // Base64 encoded image data
    public var imageFit: ImageFit?
    public var imageOpacity: Double?
    public var overlayColor: String?
    public var overlayOpacity: Double?

    public init(
        type: BackgroundType = .solid,
        solidColor: String? = nil,
        gradientColors: [String]? = nil,
        gradientAngle: Double? = nil,
        imageData: String? = nil,
        imageFit: ImageFit? = nil,
        imageOpacity: Double? = nil,
        overlayColor: String? = nil,
        overlayOpacity: Double? = nil
    ) {
        self.type = type
        self.solidColor = solidColor
        self.gradientColors = gradientColors
        self.gradientAngle = gradientAngle
        self.imageData = imageData
        self.imageFit = imageFit
        self.imageOpacity = imageOpacity
        self.overlayColor = overlayColor
        self.overlayOpacity = overlayOpacity
    }

    /// Default solid background (uses theme's primary background)
    public static var `default`: ThemeBackground {
        ThemeBackground(type: .solid)
    }

    /// Process-wide cache of decoded background images, keyed by their base64
    /// payload. `CustomizableTheme.backgroundImage` reads `decodedImage()` from
    /// SwiftUI body getters, so without this every render of a themed surface
    /// re-ran a full base64 + `NSImage(data:)` decode of a potentially
    /// wallpaper-sized image on the main thread — enough to trip the app-hang
    /// watchdog. Keying on the payload means edits (new base64) miss naturally;
    /// `NSCache` evicts under memory pressure so no manual invalidation is needed.
    /// `nonisolated(unsafe)` is sound here: `NSCache` performs its own internal
    /// locking, so concurrent `object(forKey:)` / `setObject(_:forKey:)` from any
    /// actor is safe despite the type not being `Sendable`.
    private nonisolated(unsafe) static let decodedImageCache = NSCache<NSString, NSImage>()

    /// Decode base64 image data to NSImage (memoized by payload).
    public func decodedImage() -> NSImage? {
        guard let imageData, !imageData.isEmpty else { return nil }
        let key = imageData as NSString
        if let cached = Self.decodedImageCache.object(forKey: key) { return cached }
        guard let data = Data(base64Encoded: imageData),
            let image = NSImage(data: data)
        else { return nil }
        Self.decodedImageCache.setObject(image, forKey: key)
        return image
    }

    /// Start and end points for a `LinearGradient` that honors
    /// `gradientAngle`. Unset angle renders top to bottom, matching the
    /// pre-angle behavior of every background surface.
    public var gradientUnitPoints: (start: UnitPoint, end: UnitPoint) {
        let radians = (gradientAngle ?? 180) * .pi / 180
        // CSS convention: 0deg points up, angles increase clockwise. In
        // SwiftUI unit space y grows downward, so "up" is negative y.
        let dx = sin(radians) / 2
        let dy = -cos(radians) / 2
        return (
            UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
        )
    }
}

// MARK: - Theme Glass

/// Glass effect configuration
public struct ThemeGlass: Codable, Equatable, Sendable {
    public enum GlassMaterial: String, Codable, Sendable {
        case titlebar
        case selection
        case menu
        case popover
        case sidebar
        case headerView
        case sheet
        case windowBackground
        case hudWindow
        case fullScreenUI
        case toolTip
        case contentBackground
        case underWindowBackground
        case underPageBackground

        public var nsMaterial: NSVisualEffectView.Material {
            switch self {
            case .titlebar: return .titlebar
            case .selection: return .selection
            case .menu: return .menu
            case .popover: return .popover
            case .sidebar: return .sidebar
            case .headerView: return .headerView
            case .sheet: return .sheet
            case .windowBackground: return .windowBackground
            case .hudWindow: return .hudWindow
            case .fullScreenUI: return .fullScreenUI
            case .toolTip: return .toolTip
            case .contentBackground: return .contentBackground
            case .underWindowBackground: return .underWindowBackground
            case .underPageBackground: return .underPageBackground
            }
        }
    }

    /// Whether glass effect is enabled for the chat area background.
    public var enabled: Bool
    /// Whether glass effect is enabled for the chat session sidebar.
    public var sidebarEnabled: Bool
    /// Whether glass effect is enabled for the prompt/input card.
    public var inputEnabled: Bool
    public var material: GlassMaterial
    public var blurRadius: Double
    public var opacityPrimary: Double
    public var opacitySecondary: Double
    public var opacityTertiary: Double
    public var tintColor: String?
    public var tintOpacity: Double?
    public var edgeLight: String
    public var edgeLightWidth: Double?
    public var windowBackingOpacity: Double

    public init(
        enabled: Bool = false,
        sidebarEnabled: Bool = false,
        inputEnabled: Bool = false,
        material: GlassMaterial = .hudWindow,
        blurRadius: Double = 30,
        opacityPrimary: Double = 0.10,
        opacitySecondary: Double = 0.08,
        opacityTertiary: Double = 0.05,
        tintColor: String? = nil,
        tintOpacity: Double? = nil,
        edgeLight: String = "#ffffff33",
        edgeLightWidth: Double? = nil,
        windowBackingOpacity: Double = 0.55
    ) {
        self.enabled = enabled
        self.sidebarEnabled = sidebarEnabled
        self.inputEnabled = inputEnabled
        self.material = material
        self.blurRadius = blurRadius
        self.opacityPrimary = opacityPrimary
        self.opacitySecondary = opacitySecondary
        self.opacityTertiary = opacityTertiary
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.edgeLight = edgeLight
        self.edgeLightWidth = edgeLightWidth
        self.windowBackingOpacity = windowBackingOpacity
    }

    /// Dark theme glass defaults
    public static var darkDefaults: ThemeGlass { ThemeGlass() }

    /// Light theme glass defaults
    public static var lightDefaults: ThemeGlass {
        ThemeGlass(
            enabled: false,
            material: .hudWindow,
            blurRadius: 20,
            opacityPrimary: 0.15,
            opacitySecondary: 0.10,
            opacityTertiary: 0.05,
            edgeLight: "#ffffff4d",
            windowBackingOpacity: 0.65
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        sidebarEnabled = try container.decodeIfPresent(Bool.self, forKey: .sidebarEnabled) ?? false
        inputEnabled = try container.decodeIfPresent(Bool.self, forKey: .inputEnabled) ?? false
        material = try container.decode(GlassMaterial.self, forKey: .material)
        blurRadius = try container.decode(Double.self, forKey: .blurRadius)
        opacityPrimary = try container.decode(Double.self, forKey: .opacityPrimary)
        opacitySecondary = try container.decode(Double.self, forKey: .opacitySecondary)
        opacityTertiary = try container.decode(Double.self, forKey: .opacityTertiary)
        tintColor = try container.decodeIfPresent(String.self, forKey: .tintColor)
        tintOpacity = try container.decodeIfPresent(Double.self, forKey: .tintOpacity)
        edgeLight = try container.decode(String.self, forKey: .edgeLight)
        edgeLightWidth = try container.decodeIfPresent(Double.self, forKey: .edgeLightWidth)
        windowBackingOpacity = try container.decodeIfPresent(Double.self, forKey: .windowBackingOpacity) ?? 0.55
    }
}

// MARK: - Theme Typography

/// Typography configuration
public struct ThemeTypography: Codable, Equatable, Sendable {
    public var primaryFont: String
    public var monoFont: String
    public var titleSize: Double
    public var headingSize: Double
    public var bodySize: Double
    public var smallBodySize: Double
    public var captionSize: Double
    public var codeSize: Double

    public init(
        primaryFont: String = "SF Pro",
        monoFont: String = "SF Mono",
        titleSize: Double = 28,
        headingSize: Double = 18,
        bodySize: Double = 14,
        smallBodySize: Double = 14,
        captionSize: Double = 12,
        codeSize: Double = 13
    ) {
        self.primaryFont = primaryFont
        self.monoFont = monoFont
        self.titleSize = titleSize
        self.headingSize = headingSize
        self.bodySize = bodySize
        self.smallBodySize = smallBodySize
        self.captionSize = captionSize
        self.codeSize = codeSize
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryFont = try container.decode(String.self, forKey: .primaryFont)
        monoFont = try container.decode(String.self, forKey: .monoFont)
        titleSize = try container.decode(Double.self, forKey: .titleSize)
        headingSize = try container.decode(Double.self, forKey: .headingSize)
        bodySize = try container.decode(Double.self, forKey: .bodySize)
        smallBodySize = try container.decodeIfPresent(Double.self, forKey: .smallBodySize) ?? 14
        captionSize = try container.decode(Double.self, forKey: .captionSize)
        codeSize = try container.decode(Double.self, forKey: .codeSize)
    }

    public static var `default`: ThemeTypography { ThemeTypography() }
}

// MARK: - Theme Animation

/// Animation timing configuration
public struct ThemeAnimation: Codable, Equatable, Sendable {
    public var durationQuick: Double
    public var durationMedium: Double
    public var durationSlow: Double
    public var springResponse: Double
    public var springDamping: Double

    public init(
        durationQuick: Double = 0.2,
        durationMedium: Double = 0.3,
        durationSlow: Double = 0.4,
        springResponse: Double = 0.4,
        springDamping: Double = 0.8
    ) {
        self.durationQuick = durationQuick
        self.durationMedium = durationMedium
        self.durationSlow = durationSlow
        self.springResponse = springResponse
        self.springDamping = springDamping
    }

    public static var `default`: ThemeAnimation { ThemeAnimation() }

    /// SwiftUI Animation from spring config
    public var spring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }
}

// MARK: - Theme Shadows

/// Shadow configuration
public struct ThemeShadows: Codable, Equatable, Sendable {
    public var shadowOpacity: Double
    public var cardShadowRadius: Double
    public var cardShadowRadiusHover: Double
    public var cardShadowY: Double
    public var cardShadowYHover: Double

    public init(
        shadowOpacity: Double = 0.3,
        cardShadowRadius: Double = 12,
        cardShadowRadiusHover: Double = 20,
        cardShadowY: Double = 4,
        cardShadowYHover: Double = 8
    ) {
        self.shadowOpacity = shadowOpacity
        self.cardShadowRadius = cardShadowRadius
        self.cardShadowRadiusHover = cardShadowRadiusHover
        self.cardShadowY = cardShadowY
        self.cardShadowYHover = cardShadowYHover
    }

    /// Dark theme shadow defaults
    public static var darkDefaults: ThemeShadows { ThemeShadows() }

    /// Light theme shadow defaults
    public static var lightDefaults: ThemeShadows {
        ThemeShadows(
            shadowOpacity: 0.05,
            cardShadowRadius: 8,
            cardShadowRadiusHover: 16,
            cardShadowY: 2,
            cardShadowYHover: 6
        )
    }
}

// MARK: - Theme Messages

/// Message bubble customization
public struct ThemeMessages: Codable, Equatable, Sendable {
    /// Corner radius for message bubbles
    public var bubbleCornerRadius: Double
    /// Opacity for user message bubble background
    public var userBubbleOpacity: Double
    /// Opacity for assistant message bubble background
    public var assistantBubbleOpacity: Double
    /// Override color for user bubbles (nil = use accentColor)
    public var userBubbleColor: String?
    /// Override color for assistant bubbles (nil = use secondaryBackground)
    public var assistantBubbleColor: String?
    /// Border width for message bubbles
    public var borderWidth: Double
    /// Whether to show edge light effect on bubbles
    public var showEdgeLight: Bool
    /// Whether the agent avatar is shown inline next to assistant messages.
    /// When false, the inline header drops the avatar and the name slides
    /// flush left.
    public var showInlineAvatar: Bool
    /// Diameter (in points) of the inline avatar shown beside assistant
    /// messages. Clamped at consumption time to a sensible range.
    public var inlineAvatarSize: Double
    /// Whether the agent's display name is shown next to the avatar.
    /// When false, only the avatar identifies the assistant in the header.
    public var showAgentName: Bool
    /// Font size (in points) of the agent's display name in the header.
    public var agentNameSize: Double

    public init(
        bubbleCornerRadius: Double = 20,
        userBubbleOpacity: Double = 0.3,
        assistantBubbleOpacity: Double = 0.85,
        userBubbleColor: String? = nil,
        assistantBubbleColor: String? = nil,
        borderWidth: Double = 0.5,
        showEdgeLight: Bool = true,
        showInlineAvatar: Bool = true,
        inlineAvatarSize: Double = 24,
        showAgentName: Bool = true,
        agentNameSize: Double = 13
    ) {
        self.bubbleCornerRadius = bubbleCornerRadius
        self.userBubbleOpacity = userBubbleOpacity
        self.assistantBubbleOpacity = assistantBubbleOpacity
        self.userBubbleColor = userBubbleColor
        self.assistantBubbleColor = assistantBubbleColor
        self.borderWidth = borderWidth
        self.showEdgeLight = showEdgeLight
        self.showInlineAvatar = showInlineAvatar
        self.inlineAvatarSize = inlineAvatarSize
        self.showAgentName = showAgentName
        self.agentNameSize = agentNameSize
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bubbleCornerRadius = try c.decodeIfPresent(Double.self, forKey: .bubbleCornerRadius) ?? 20
        userBubbleOpacity = try c.decodeIfPresent(Double.self, forKey: .userBubbleOpacity) ?? 0.3
        assistantBubbleOpacity = try c.decodeIfPresent(Double.self, forKey: .assistantBubbleOpacity) ?? 0.85
        userBubbleColor = try c.decodeIfPresent(String.self, forKey: .userBubbleColor)
        assistantBubbleColor = try c.decodeIfPresent(String.self, forKey: .assistantBubbleColor)
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0.5
        showEdgeLight = try c.decodeIfPresent(Bool.self, forKey: .showEdgeLight) ?? true
        showInlineAvatar = try c.decodeIfPresent(Bool.self, forKey: .showInlineAvatar) ?? true
        inlineAvatarSize = try c.decodeIfPresent(Double.self, forKey: .inlineAvatarSize) ?? 24
        showAgentName = try c.decodeIfPresent(Bool.self, forKey: .showAgentName) ?? true
        agentNameSize = try c.decodeIfPresent(Double.self, forKey: .agentNameSize) ?? 13
    }

    public static var `default`: ThemeMessages { ThemeMessages() }
}

// MARK: - Theme Borders

/// Border and corner radius customization
public struct ThemeBorders: Codable, Equatable, Sendable {
    /// Default border width for UI elements
    public var defaultWidth: Double
    /// Corner radius for card-style elements
    public var cardCornerRadius: Double
    /// Corner radius for input fields
    public var inputCornerRadius: Double
    /// Default border opacity applied to border colors
    public var borderOpacity: Double

    public init(
        defaultWidth: Double = 1.0,
        cardCornerRadius: Double = 12,
        inputCornerRadius: Double = 8,
        borderOpacity: Double = 0.3
    ) {
        self.defaultWidth = defaultWidth
        self.cardCornerRadius = cardCornerRadius
        self.inputCornerRadius = inputCornerRadius
        self.borderOpacity = borderOpacity
    }

    public static var `default`: ThemeBorders { ThemeBorders() }
}

public enum ThemeInputStyle: String, Codable, Sendable { case gradient, shadow }

// MARK: - Custom Theme

/// Complete custom theme configuration
public struct CustomTheme: Codable, Equatable, Sendable {
    public var metadata: ThemeMetadata
    public var colors: ThemeColors
    public var background: ThemeBackground
    public var glass: ThemeGlass
    public var typography: ThemeTypography
    public var animationConfig: ThemeAnimation
    public var shadows: ThemeShadows
    public var messages: ThemeMessages
    public var borders: ThemeBorders
    public var inputStyle: ThemeInputStyle

    /// Syntax highlighting theme name (Highlightr). nil = auto (dark/light).
    public var codeHighlightTheme: String?

    /// Optional library provenance. Missing values are treated as local
    /// custom themes, while built-in presets are always classified as built-in.
    public var library: ThemeLibraryInfo?

    /// Whether this is a built-in theme (cannot be deleted)
    public var isBuiltIn: Bool
    public var isDark: Bool

    /// When true, accent-adjacent colors are re-derived from the user's
    /// system accent color (System Settings > Appearance) at theme-build
    /// time. The stored hex values act as the palette for the default
    /// (blue) accent. See `ThemeColors.applyingAccent(_:isDark:)`.
    public var followsSystemAccent: Bool

    public init(
        metadata: ThemeMetadata = ThemeMetadata(),
        colors: ThemeColors = ThemeColors(),
        background: ThemeBackground = .default,
        glass: ThemeGlass = ThemeGlass(),
        typography: ThemeTypography = ThemeTypography(),
        animationConfig: ThemeAnimation = ThemeAnimation(),
        shadows: ThemeShadows = ThemeShadows(),
        messages: ThemeMessages = ThemeMessages(),
        borders: ThemeBorders = ThemeBorders(),
        inputStyle: ThemeInputStyle = .gradient,
        codeHighlightTheme: String? = nil,
        library: ThemeLibraryInfo? = nil,
        isBuiltIn: Bool = false,
        isDark: Bool = true,
        followsSystemAccent: Bool = false
    ) {
        self.metadata = metadata
        self.colors = colors
        self.background = background
        self.glass = glass
        self.typography = typography
        self.animationConfig = animationConfig
        self.shadows = shadows
        self.messages = messages
        self.borders = borders
        self.inputStyle = inputStyle
        self.codeHighlightTheme = codeHighlightTheme
        self.library = library
        self.isBuiltIn = isBuiltIn
        self.isDark = isDark
        self.followsSystemAccent = followsSystemAccent
    }

    /// Backward-compatible decoding: new fields fall back to defaults if missing
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadata = try container.decode(ThemeMetadata.self, forKey: .metadata)
        colors = try container.decode(ThemeColors.self, forKey: .colors)
        background = try container.decode(ThemeBackground.self, forKey: .background)
        glass = try container.decode(ThemeGlass.self, forKey: .glass)
        typography = try container.decode(ThemeTypography.self, forKey: .typography)
        animationConfig = try container.decode(ThemeAnimation.self, forKey: .animationConfig)
        shadows = try container.decode(ThemeShadows.self, forKey: .shadows)
        messages = try container.decodeIfPresent(ThemeMessages.self, forKey: .messages) ?? ThemeMessages()
        borders = try container.decodeIfPresent(ThemeBorders.self, forKey: .borders) ?? ThemeBorders()
        inputStyle = try container.decodeIfPresent(ThemeInputStyle.self, forKey: .inputStyle) ?? .gradient
        codeHighlightTheme = try container.decodeIfPresent(String.self, forKey: .codeHighlightTheme)
        library = try container.decodeIfPresent(ThemeLibraryInfo.self, forKey: .library)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        isDark = try container.decode(Bool.self, forKey: .isDark)
        followsSystemAccent = try container.decodeIfPresent(Bool.self, forKey: .followsSystemAccent) ?? false
    }

    /// Default dark theme — Nuo "夜纸" palette.
    ///
    /// Schema 7 起，默认皮肤是「纸与印」；此前跟随系统强调色的行为被关闭，
    /// 因为朱红是品牌语义（存在 / 承诺），跟随系统会被替换成蓝色。
    /// Schema 8 起配色改由 Radix Colors 12 级色阶推导（见 `NuoThemeSkin`）。
    public static var darkDefault: CustomTheme {
        CustomTheme(
            metadata: ThemeMetadata(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Dark",
                version: "2.0",
                author: "Nuo"
            ),
            colors: NuoThemeSkin.night,
            background: .default,
            glass: NuoThemeSkin.nightGlass,
            typography: ThemeTypography(
                primaryFont: "SF Pro",
                monoFont: "SF Mono",
                titleSize: 26,
                headingSize: 18,
                bodySize: 15,
                captionSize: 12,
                codeSize: 13
            ),
            animationConfig: ThemeAnimation(
                durationQuick: 0.15,
                durationMedium: 0.25,
                durationSlow: 0.35,
                springResponse: 0.35,
                springDamping: 0.82
            ),
            shadows: ThemeShadows(
                shadowOpacity: 0.32,
                cardShadowRadius: 10,
                cardShadowRadiusHover: 18,
                cardShadowY: 3,
                cardShadowYHover: 7
            ),
            messages: ThemeMessages(
                bubbleCornerRadius: 18,
                userBubbleOpacity: 0.2,
                assistantBubbleOpacity: 0.95,
                borderWidth: 0.5,
                showEdgeLight: true,
                showInlineAvatar: true,
                inlineAvatarSize: 24,
                showAgentName: true,
                agentNameSize: 13
            ),
            borders: ThemeBorders(
                defaultWidth: 1,
                cardCornerRadius: 10,
                inputCornerRadius: 7,
                borderOpacity: 0.5
            ),
            isBuiltIn: true,
            isDark: true,
            // 不跟随系统强调色：朱红是品牌语义，不是可替换的装饰。
            // 跟随系统会把 accent / focus / cursor / selection 一并换成系统蓝。
            followsSystemAccent: false
        )
    }

    /// Default light theme — Nuo "纸" palette.
    ///
    /// 暖灰宣纸底 + 印泥朱红；正文 15.5:1、三级文字 5.0:1，全部过 AA。
    public static var lightDefault: CustomTheme {
        CustomTheme(
            metadata: ThemeMetadata(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Light",
                version: "2.0",
                author: "Nuo"
            ),
            colors: NuoThemeSkin.paper,
            background: .default,
            glass: NuoThemeSkin.paperGlass,
            typography: ThemeTypography(
                primaryFont: "SF Pro",
                monoFont: "SF Mono",
                titleSize: 26,
                headingSize: 18,
                bodySize: 15,
                captionSize: 12,
                codeSize: 13
            ),
            animationConfig: ThemeAnimation(
                durationQuick: 0.15,
                durationMedium: 0.25,
                durationSlow: 0.35,
                springResponse: 0.35,
                springDamping: 0.82
            ),
            shadows: ThemeShadows(
                shadowOpacity: 0.12,
                cardShadowRadius: 8,
                cardShadowRadiusHover: 16,
                cardShadowY: 2,
                cardShadowYHover: 6
            ),
            messages: ThemeMessages(
                bubbleCornerRadius: 18,
                userBubbleOpacity: 0.16,
                assistantBubbleOpacity: 0.95,
                borderWidth: 0.5,
                showEdgeLight: true,
                showInlineAvatar: true,
                inlineAvatarSize: 24,
                showAgentName: true,
                agentNameSize: 13
            ),
            borders: ThemeBorders(
                defaultWidth: 1,
                cardCornerRadius: 10,
                inputCornerRadius: 7,
                borderOpacity: 0.45
            ),
            isBuiltIn: true,
            isDark: false,
            // 不跟随系统强调色：朱红是品牌语义，不是可替换的装饰。
            // 跟随系统会把 accent / focus / cursor / selection 一并换成系统蓝。
            followsSystemAccent: false
        )
    }

    /// All built-in theme presets.
    ///
    /// 只有浅色与深色两个。其它配色一律走"导入主题"或"复制后自改"，
    /// 内置列表保持最小：预设越多，用户越难判断哪一个是"默认"。
    ///
    /// ⚠️ 增删内建预设必须同时递增
    /// `ThemeConfigurationStore.currentBuiltInThemeSchema`，否则存量安装
    /// 不会收到新的预设文件。
    public static var allBuiltInPresets: [CustomTheme] {
        [.darkDefault, .lightDefault]
    }
}

// MARK: - Color Parsing Extension

extension Color {
    // Theme color accessors funnel through this initializer from view bodies
    // on every SwiftUI body evaluation, and each call pays for a CharacterSet
    // inversion plus a Scanner parse. Themes draw from a small fixed palette,
    // so parsed colors are memoized by their hex string.
    private static let themeHexCacheLock = NSLock()
    private nonisolated(unsafe) static var themeHexCache: [String: Color] = [:]

    /// Initialize from hex string with alpha support
    init(themeHex hex: String) {
        Color.themeHexCacheLock.lock()
        if let cached = Color.themeHexCache[hex] {
            Color.themeHexCacheLock.unlock()
            self = cached
            return
        }
        Color.themeHexCacheLock.unlock()

        let key = hex
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // RGBA (32-bit) — theme colors are authored web-style with
            // trailing alpha ("#3b82f680", accent+"45"). This previously read
            // ARGB, so the leading red byte became the alpha and colors like
            // the system-accent selection "#007aff26" resolved fully
            // transparent (invisible selection highlight, issue #2129).
            // Mirrors the same fix in Color(hex:) (Theme.swift).
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )

        Color.themeHexCacheLock.lock()
        // Safety-net cap (reset-on-overflow): the theme palette is small and
        // fixed, but custom themes contribute arbitrary hex strings over time.
        if Color.themeHexCache.count >= 512 { Color.themeHexCache.removeAll() }
        Color.themeHexCache[key] = self
        Color.themeHexCacheLock.unlock()
    }

    /// Convert Color to hex string
    func toHex(includeAlpha: Bool = false) -> String {
        // Convert to sRGB color space first for consistent round-trip with Color(themeHex:)
        let nsColor: NSColor
        if let converted = NSColor(self).usingColorSpace(.sRGB) {
            nsColor = converted
        } else if let converted = NSColor(self).usingColorSpace(.deviceRGB) {
            nsColor = converted
        } else {
            return "#000000"
        }

        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        let a = Int((nsColor.alphaComponent * 255).rounded())

        // Trailing alpha ("#RRGGBBAA") to match how Color(themeHex:) parses
        // 8-digit strings. This used to emit leading alpha, so every color
        // with opacity below 100% round-tripped with its channels shifted
        // (alpha became red), which made the theme editor's color picker
        // snap to a different color on every drag tick.
        if includeAlpha && a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
