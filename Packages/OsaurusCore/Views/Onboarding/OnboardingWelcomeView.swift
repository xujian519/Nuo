//
//  OnboardingWelcomeView.swift
//  osaurus
//
//  Welcome step — Figma screen 1. Left column (bottom-aligned): 40pt hero
//  title, 14pt subtitle, white "Get started →" pill, 10pt legal acceptance
//  line, and the usage-data checkbox. Right: rounded panel with the seal.
//

import SwiftUI

// MARK: - State

/// Welcome step state. Holds the anonymous-usage opt-in so the choice made
/// via the checkbox survives the slide transition and can be read by the
/// parent's "Get started" CTA. Moving usage consent here (the *first* step)
/// is deliberate: `TelemetryService` buffers the onboarding funnel until a
/// decision is made, so opting in up front lets us capture the drop-off
/// point even when the user bails partway through.
@MainActor
final class WelcomeState: ObservableObject {
    /// Opt-OUT, so it defaults ON (consistent with crash reporting). The
    /// parent reads this on the "Get started" CTA and, when on, calls
    /// `TelemetryService.setEnabled(true)` to flush the buffered funnel and
    /// send everything that follows live; unchecking it leaves telemetry
    /// undecided so `finishOnboarding` finalizes a decline.
    @Published var shareUsageData: Bool = true
}

// MARK: - Step view

struct WelcomeStepView: View {
    @ObservedObject var state: WelcomeState
    let onGetStarted: () -> Void

    var body: some View {
        OnboardingStepLayout {
            leftColumn
        } right: {
            heroPanel
        }
    }

    // MARK: Left column

    /// Staggered cascade: title → subtitle → CTA → legal → checkbox.
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Local agents that keep their word.", bundle: .module)
                .font(OnboardingTypography.heroTitle)
                .tracking(0.4)
                .foregroundColor(OnboardingPalette.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .onboardingEntrance(0)

            Spacer().frame(height: 16)

            Text(
                "Local agents on your Mac. Your chats, files, and keys can stay on this device. No account or cloud required.",
                bundle: .module
            )
            .font(OnboardingTypography.subtitle)
            .foregroundColor(OnboardingPalette.labelSecondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .onboardingEntrance(1)

            Spacer().frame(height: 40)

            OnboardingPillButton(
                title: "Get started",
                style: .primary,
                size: .large,
                trailingSymbol: "arrow.right",
                action: onGetStarted
            )
            .onboardingEntrance(2)

            Spacer().frame(height: 16)

            legalNotice
                .onboardingEntrance(3)

            Spacer().frame(height: 10)

            OnboardingCheckboxRow(
                isOn: $state.shareUsageData,
                label: "Share anonymous usage data to help improve Nuo"
            )
            .onboardingEntrance(4)
        }
    }

    /// First-run affirmative acceptance: proceeding is the action that
    /// accepts the Terms and Privacy Policy, which is more defensible than a
    /// passive footer link alone.
    private var legalNotice: some View {
        MarkdownLinkText(
            markdown: OsaurusWebLinks.acceptanceMarkdown,
            font: OnboardingTypography.footnote,
            textColor: OnboardingPalette.labelSecondary,
            linkColor: OnboardingPalette.sealRed,
            alignment: .leading
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Right panel

    /// 右栏铺满深底朱文印。印图自带暗底，圆角裁切后即是面板。
    private var heroPanel: some View {
        OnboardingRightPanel {
            Color.clear
                .overlay {
                    Image("osaurus-main", bundle: .module)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        }
        .clipShape(
            RoundedRectangle(cornerRadius: OnboardingLayout.panelRadius, style: .continuous)
        )
        .onboardingEntrance(1)
    }
}

// MARK: - Preview

#if DEBUG
    struct OnboardingWelcomeView_Previews: PreviewProvider {
        static var previews: some View {
            ZStack {
                OnboardingPalette.windowBackground
                WelcomeStepView(state: WelcomeState(), onGetStarted: {})
            }
            .frame(width: OnboardingMetrics.windowWidth, height: OnboardingMetrics.windowHeight)
        }
    }
#endif
