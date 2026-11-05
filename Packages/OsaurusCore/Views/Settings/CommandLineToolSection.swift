//
//  CommandLineToolSection.swift
//  osaurus
//
//  "Command Line Tool" card on Developer Tools → Server → Overview. Installs
//  the `osaurus` CLI into the user's PATH via a symlink to the embedded
//  binary. Lived on the General tab until the settings cleanup moved every
//  developer-facing control under Developer Tools.
//

import AppKit
import OsaurusRepository
import SwiftUI

struct CommandLineToolSection: View {
    @Environment(\.theme) private var theme

    @State private var installMessage: String? = nil
    @State private var installSucceeded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Command Line Tool", bundle: .module)
            } icon: {
                Image(systemName: "apple.terminal")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(theme.primaryText)

            Text(
                "Install the `nuo` CLI into your PATH for terminal access. If installed to ~/.local/bin, make sure that folder is in your PATH.",
                bundle: .module
            )
            .font(.system(size: 12))
            .foregroundColor(theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(action: installCLI) {
                    Text("Install CLI", bundle: .module)
                }
                .buttonStyle(SettingsButtonStyle())
                .localizedHelp("Create a symlink to the embedded CLI")

                if let message = installMessage {
                    HStack(spacing: 6) {
                        Image(
                            systemName: installSucceeded
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 12))
                        Text(message)
                            .font(.system(size: 11))
                            .lineLimit(2)
                    }
                    .foregroundColor(installSucceeded ? theme.successColor : theme.warningColor)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.secondaryBackground)
        )
        .settingsLandingAnchor("server.cli")
    }
}

// MARK: - Install Helper

extension CommandLineToolSection {
    private func installCLI() {
        let fm = FileManager.default

        guard let cliURL = resolveCLIExecutableURL() else {
            installSucceeded = false
            installMessage = "CLI not found. Build the app with 'make app' or install via release DMG."
            return
        }

        // Candidate target directories. /opt/homebrew/bin is intentionally
        // NOT a candidate: it's a directory Homebrew owns and manages, and
        // Osaurus isn't distributed via a Homebrew formula — its presence
        // on a user's machine for unrelated packages isn't a reason for
        // this app to write into it. See osaurus-ai/osaurus#2137.
        let usrLocalBin = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
        let userLocalBin = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)

        if tryInstall(cliURL: cliURL, into: usrLocalBin) {
            installSucceeded = true
            installMessage = "Installed to \(usrLocalBin.appendingPathComponent(Brand.slug).path)"
            return
        }

        // Fallback to user-local bin
        do {
            try fm.createDirectory(at: userLocalBin, withIntermediateDirectories: true)
        } catch {
            installSucceeded = false
            installMessage = "Failed to prepare ~/.local/bin (\(error.localizedDescription))"
            return
        }

        if tryInstall(cliURL: cliURL, into: userLocalBin) {
            let linkPath = userLocalBin.appendingPathComponent(Brand.slug).path
            let inPath = isDirInPATH(userLocalBin.path)
            installSucceeded = true
            installMessage =
                inPath
                ? "Installed to \(linkPath)"
                : "Installed to \(linkPath). Add to PATH."
            return
        }

        installSucceeded = false
        installMessage = "Installation failed. Try: scripts/install_cli_symlink.sh"
    }

    private func resolveCLIExecutableURL() -> URL? {
        let fm = FileManager.default
        let appURL = Bundle.main.bundleURL

        // 1. Prefer the embedded CLI in Helpers (production build via 'make app').
        //    The pre-rename helper is a fallback for one release: older bundles
        //    only carry `osaurus`, and it resolves to the same binary.
        for name in [Brand.slug, Brand.Legacy.slug] {
            let helpers = appURL.appendingPathComponent("Contents/Helpers/\(name)", isDirectory: false)
            if fm.fileExists(atPath: helpers.path), fm.isExecutableFile(atPath: helpers.path) {
                return helpers
            }
            let macOS = appURL.appendingPathComponent("Contents/MacOS/\(name)", isDirectory: false)
            if fm.fileExists(atPath: macOS.path), fm.isExecutableFile(atPath: macOS.path) {
                return macOS
            }
        }

        // 2. Development: try the build Products directory. `osaurus-cli` is the
        //    SwiftPM product name and stays internal.
        let productsDir = appURL.deletingLastPathComponent()
        for name in ["osaurus-cli", Brand.slug, Brand.Legacy.slug] {
            let candidate = productsDir.appendingPathComponent(name, isDirectory: false)
            if fm.fileExists(atPath: candidate.path), fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // 3. Check the Release products directory, including the app bundle.
        let releaseDir = productsDir.deletingLastPathComponent().appendingPathComponent("Release")
        for name in ["osaurus-cli", Brand.slug, Brand.Legacy.slug] {
            let candidate = releaseDir.appendingPathComponent(name, isDirectory: false)
            if fm.fileExists(atPath: candidate.path), fm.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        for appName in ["Nuo.app", "Osaurus.app"] {
            for subdir in ["Contents/Helpers", "Contents/MacOS"] {
                for name in [Brand.slug, Brand.Legacy.slug] {
                    let candidate = releaseDir.appendingPathComponent(
                        "\(appName)/\(subdir)/\(name)",
                        isDirectory: false
                    )
                    if fm.fileExists(atPath: candidate.path), fm.isExecutableFile(atPath: candidate.path) {
                        return candidate
                    }
                }
            }
        }

        return nil
    }

    private func tryInstall(cliURL: URL, into dir: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        let linkURL = dir.appendingPathComponent(Brand.slug)

        // If an entry exists, replace only if it's a symlink
        if fm.fileExists(atPath: linkURL.path) {
            do {
                _ = try fm.destinationOfSymbolicLink(atPath: linkURL.path)
                // It's a symlink – remove and replace
                try? fm.removeItem(at: linkURL)
            } catch {
                // Not a symlink (likely a real file); do not overwrite
                return false
            }
        }

        do {
            try fm.createSymbolicLink(atPath: linkURL.path, withDestinationPath: cliURL.path)
            return true
        } catch {
            return false
        }
    }

    private func isDirInPATH(_ dir: String) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return path.split(separator: ":").map(String.init).contains { $0 == dir }
    }
}
