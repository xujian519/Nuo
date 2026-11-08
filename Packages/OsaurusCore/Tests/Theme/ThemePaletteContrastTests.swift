//
//  ThemePaletteContrastTests.swift
//  OsaurusCoreTests
//

import Foundation
import Testing

@testable import OsaurusCore

/// 内建 Light/Dark 色板的对比度门禁。
///
/// 仓库标准（`docs/ACCESSIBILITY.md`）：正文 ≥4.5:1，UI 组件边界 ≥3:1。
/// 这条测试是**机器门禁**——改了色值却没有重新核算对比度时它会失败，
/// 而不是等到有人用肉眼发现文字读不清。
///
/// 判定规则写在这里，避免"设计意图"与"实现值"各说各话：
///  · **正文级文字**（正文 / 次级 / 三级 / 占位符 / 成功 / 警告 / 错误 / 信息）
///    对它可能落到的**每一个**表面都必须 ≥4.5:1。
///  · **强调色**在画布与卡片上按正文算（≥4.5:1），在其它表面按图形算
///    （≥3:1）——强调色同时承担焦点环、选中底与文字三种角色。
///  · **组件边界**（`secondaryBorder`）≥3:1。`primaryBorder` 是分隔线，
///    不承载信息，因此不设门禁。
///  · **代码块内的语法色**对代码底 ≥4.5:1。
///
/// 半透明前景（三级文字 = sand-12 @ 65%）先合成到底色上再算对比度，
/// 否则会拿未合成的颜色算出虚高的数值。
@Suite("Built-in palette contrast")
struct ThemePaletteContrastTests {

    // MARK: - 色值解析与对比度

    private struct RGB {
        var r: Double
        var g: Double
        var b: Double
        var a: Double
    }

    /// 解析 `#RRGGBB` / `RRGGBB` / `#RRGGBBAA` / `RRGGBBAA`（alpha 在尾部）。
    private static func parse(_ hex: String) -> RGB? {
        var body = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("#") { body.removeFirst() }
        guard body.count == 6 || body.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: body).scanHexInt64(&value) else { return nil }
        return RGB(
            r: Double((value >> (body.count == 8 ? 24 : 16)) & 0xFF) / 255,
            g: Double((value >> (body.count == 8 ? 16 : 8)) & 0xFF) / 255,
            b: Double((value >> (body.count == 8 ? 8 : 0)) & 0xFF) / 255,
            a: body.count == 8 ? Double(value & 0xFF) / 255 : 1
        )
    }

    private static func linearize(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func luminance(_ color: RGB) -> Double {
        0.2126 * linearize(color.r) + 0.7152 * linearize(color.g) + 0.0722 * linearize(color.b)
    }

    /// 把半透明前景合成到底色上，得到真正显示出来的颜色。
    private static func composite(_ foreground: RGB, over background: RGB) -> RGB {
        RGB(
            r: foreground.r * foreground.a + background.r * (1 - foreground.a),
            g: foreground.g * foreground.a + background.g * (1 - foreground.a),
            b: foreground.b * foreground.a + background.b * (1 - foreground.a),
            a: 1
        )
    }

    private static func contrastRatio(foreground: String, background: String) -> Double? {
        guard let fg = parse(foreground), let bg = parse(background) else { return nil }
        return contrastRatio(composite(fg, over: bg), bg)
    }

    private static func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    // MARK: - 字段表

    /// 承载正文的字段。
    private static let bodyTextFields: [String] = [
        "primaryText", "secondaryText", "tertiaryText", "placeholderText",
        "successColor", "warningColor", "errorColor", "infoColor",
    ]

    /// 文字可能落到的表面。
    ///
    /// 含 `codeBlockBackground`：App 里的代码语法高亮走 Highlightr，
    /// 但代码底本身是这个主题字段，正文仍可能落到它上面。
    private static let surfaces: [String] = [
        "primaryBackground", "secondaryBackground", "tertiaryBackground",
        "sidebarBackground", "sidebarSelectedBackground", "cardBackground",
        "buttonBackground", "inputBackground", "codeBlockBackground",
    ]

    private static func value(_ field: String, _ colors: ThemeColors) -> String? {
        switch field {
        case "primaryText": return colors.primaryText
        case "secondaryText": return colors.secondaryText
        case "tertiaryText": return colors.tertiaryText
        case "placeholderText": return colors.placeholderText
        case "successColor": return colors.successColor
        case "warningColor": return colors.warningColor
        case "errorColor": return colors.errorColor
        case "infoColor": return colors.infoColor
        case "accentColor": return colors.accentColor
        case "primaryBorder": return colors.primaryBorder
        case "secondaryBorder": return colors.secondaryBorder
        case "primaryBackground": return colors.primaryBackground
        case "secondaryBackground": return colors.secondaryBackground
        case "tertiaryBackground": return colors.tertiaryBackground
        case "sidebarBackground": return colors.sidebarBackground
        case "sidebarSelectedBackground": return colors.sidebarSelectedBackground
        case "cardBackground": return colors.cardBackground
        case "buttonBackground": return colors.buttonBackground
        case "inputBackground": return colors.inputBackground
        case "codeBlockBackground": return colors.codeBlockBackground
        default: return nil
        }
    }

    // MARK: - 门禁

    @Test("body text meets 4.5:1 on every surface it can land on")
    func bodyTextMeetsAAOnEverySurface() {
        for (name, colors) in [("Light", CustomTheme.lightDefault.colors), ("Dark", CustomTheme.darkDefault.colors)] {
            for field in Self.bodyTextFields {
                guard let foreground = Self.value(field, colors) else {
                    Issue.record("\(name).\(field) 取不到色值")
                    continue
                }
                for surface in Self.surfaces {
                    guard let background = Self.value(surface, colors) else { continue }
                    let ratio = Self.contrastRatio(foreground: foreground, background: background)
                    #expect(
                        ratio != nil,
                        "\(name).\(field) 无法解析：\(foreground)"
                    )
                    guard let ratio else { continue }
                    #expect(
                        ratio >= 4.5,
                        "\(name).\(field)=\(foreground) 在 \(surface)=\(background) 上只有 \(String(format: "%.2f", ratio)):1，低于 AA 正文线 4.5:1"
                    )
                }
            }
        }
    }

    @Test("accent reads as text on canvas and card, and as a graphic elsewhere")
    func accentMeetsItsRoleThreshold() {
        for (name, colors) in [("Light", CustomTheme.lightDefault.colors), ("Dark", CustomTheme.darkDefault.colors)] {
            let accent = colors.accentColor
            for surface in Self.surfaces {
                guard let background = Self.value(surface, colors) else { continue }
                guard let ratio = Self.contrastRatio(foreground: accent, background: background) else {
                    Issue.record("\(name).accentColor 无法解析：\(accent)")
                    continue
                }
                // 画布与卡片是强调色当**文字**用的地方，其余是焦点环 / 选中底。
                let required: Double = (surface == "primaryBackground" || surface == "cardBackground") ? 4.5 : 3.0
                #expect(
                    ratio >= required,
                    "\(name).accentColor=\(accent) 在 \(surface)=\(background) 上只有 \(String(format: "%.2f", ratio)):1，低于该角色要求的 \(required):1"
                )
            }
        }
    }

    @Test("component borders meet 3:1 on every surface")
    func componentBordersMeetNonTextContrast() {
        for (name, colors) in [("Light", CustomTheme.lightDefault.colors), ("Dark", CustomTheme.darkDefault.colors)] {
            let border = colors.secondaryBorder
            for surface in Self.surfaces {
                // 选中行不画组件边界，这一组合不存在。
                if surface == "sidebarSelectedBackground" { continue }
                guard let background = Self.value(surface, colors) else { continue }
                guard let ratio = Self.contrastRatio(foreground: border, background: background) else {
                    Issue.record("\(name).secondaryBorder 无法解析：\(border)")
                    continue
                }
                #expect(
                    ratio >= 3.0,
                    "\(name).secondaryBorder=\(border) 在 \(surface)=\(background) 上只有 \(String(format: "%.2f", ratio)):1，低于组件边界线 3:1"
                )
            }
        }
    }

    @Test("the code block background is distinguishable from the canvas")
    func codeBlockBackgroundIsDistinctFromCanvas() {
        for (name, colors) in [("Light", CustomTheme.lightDefault.colors), ("Dark", CustomTheme.darkDefault.colors)] {
            guard
                let ratio = Self.contrastRatio(
                    foreground: colors.codeBlockBackground,
                    background: colors.primaryBackground
                )
            else {
                Issue.record("\(name).codeBlockBackground 无法解析")
                continue
            }
            // 代码底与画布必须看得出是两块面，但不该刺眼。
            #expect(
                ratio >= 1.02 && ratio <= 1.8,
                "\(name).codeBlockBackground=\(colors.codeBlockBackground) 对画布 \(colors.primaryBackground) 是 \(String(format: "%.2f", ratio)):1，代码底与画布应可分辨但不应跳脱"
            )
        }
    }
}
