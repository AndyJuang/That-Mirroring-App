import AppKit
import SwiftUI

enum AboutWindowMetrics {
    static let width: CGFloat = 420
    static let height: CGFloat = 560
}

enum AboutSheet: String, Identifiable {
    case licenses
    case acknowledgments
    var id: String { rawValue }
}

final class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?
    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let host = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = localizedText("About That Mirroring")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("ThatMirroringAbout")
        window.backgroundColor = .windowBackgroundColor
        let size = NSSize(width: AboutWindowMetrics.width, height: AboutWindowMetrics.height)
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

enum AboutLauncher {
    static func open(_ kind: AboutLinkKind) {
        let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AboutLinks.sisterBundleIdentifier) != nil
        switch aboutDestination(kind, sisterInstalled: installed) {
        case .application(let bundleIdentifier):
            guard bundleIdentifier == AboutLinks.sisterBundleIdentifier,
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                open(url: AboutLinks.website)
                return
            }
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { running, _ in
                guard running == nil else { return }
                DispatchQueue.main.async { open(url: AboutLinks.website) }
            }
        case .url(let url):
            open(url: url)
        }
    }

    private static func open(url: URL) {
        guard aboutURLIsAllowed(url) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct AboutView: View {
    @ViewState private var version = AppVersionInfo.current()
    @ViewState private var copied = false
    @ViewState private var iconTaps = IconTapSeries()
    @ViewState private var winkTrigger = 0
    @ViewState private var sheet: AboutSheet?
    @ViewState private var notices: OpenSourceNotices?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                icon
                Text("That Mirroring")
                    .font(.system(size: 20, weight: .semibold))
                HStack(spacing: 8) {
                    Text(appVersionLabel(version))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button(action: copyVersion) {
                        if copied {
                            Text("Copied")
                        } else {
                            Text("Copy Version Info")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text("Mirror your iPhone, iPad or Android screen over USB with near-zero latency — for presentations, streaming and tutorials.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            Divider().padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sister App")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                sisterRow
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 6) {
                Text("那個數位有限公司 / Aha Digital Co., Ltd.")
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    linkButton(.website, symbol: "globe", address: AboutLinks.website.host ?? "") {
                        Text("Website")
                    }
                    linkButton(.email, symbol: "envelope", address: AboutLinks.contactAddress) {
                        Text("Contact us")
                    }
                    Button(action: { AboutLauncher.open(.youtube) }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.rectangle")
                            Text("Watch “欸那個AJ” on YouTube")
                        }
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)
            Divider()
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button(action: { sheet = .licenses }) {
                        Text("Open-Source Licenses")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    Button(action: { sheet = .acknowledgments }) {
                        Text("Acknowledgments")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                Text("© 2026 Aha Digital Co., Ltd. All rights reserved.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(width: AboutWindowMetrics.width, height: AboutWindowMetrics.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $sheet) { kind in
            AboutDetailSheet(kind: kind, notices: notices)
        }
        .onAppear(perform: loadNotices)
    }

    private var icon: some View {
        Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 76, height: 76)
            .contentShape(Rectangle())
            .onTapGesture(perform: registerIconTap)
            .modifier(CatWinkEffect(trigger: winkTrigger))
            .accessibilityLabel(Text("That Mirroring"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, registerIconTap)
    }

    private var sisterRow: some View {
        Button(action: { AboutLauncher.open(.sister) }) {
            HStack(spacing: 10) {
                sisterIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thatcaster")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Thatcaster — multi-camera, multi-screen teaching recorder & editor.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var sisterIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AboutLinks.sisterBundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 36, height: 36)
        } else {
            Image(systemName: "video.fill")
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func linkButton(_ kind: AboutLinkKind, symbol: String, address: String, @ViewBuilder label: () -> some View) -> some View {
        Button(action: { AboutLauncher.open(kind) }) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                label()
                Text(verbatim: address)
            }
        }
        .buttonStyle(.link)
    }

    private func registerIconTap() {
        if iconTaps.register(at: Date().timeIntervalSinceReferenceDate) {
            winkTrigger += 1
        }
    }

    private func copyVersion() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(version.copyText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private func loadNotices() {
        guard notices == nil, let resources = Bundle.main.resourceURL else { return }
        notices = loadOpenSourceNotices(resources: resources)
    }
}

struct AboutDetailSheet: View {
    let kind: AboutSheet
    let notices: OpenSourceNotices?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sheetTitle
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if kind == .acknowledgments {
                        Text("Android mirroring powered by scrcpy (Apache 2.0, Genymobile); also includes adb, FFmpeg (LGPL 2.1), SDL, libusb, dav1d and zlib.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let notices {
                        Text(verbatim: notices.summary)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(notices.documents) { document in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: document.relativePath)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(verbatim: document.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        Text("Open-source notices are not in this copy.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 400, height: 480)
    }

    @ViewBuilder
    private var sheetTitle: some View {
        if kind == .licenses {
            Text("Open-Source Licenses")
        } else {
            Text("Acknowledgments")
        }
    }
}
