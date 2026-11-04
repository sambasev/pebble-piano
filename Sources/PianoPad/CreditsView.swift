import SwiftUI

/// Who made Pebble Piano, and the licences of everything it includes from others.
/// Opened from the Pebble Piano logo in the header.
struct CreditsView: View {
    var onDone: () -> Void

    @State private var expanded: String?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (s?, b?) where s != b: return "Version \(s) (\(b))"
        case let (s?, _): return "Version \(s)"
        default: return "Development build"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            HStack(spacing: PP.Space.s3) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(PP.onAccent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: PP.Radius.md, style: .continuous).fill(PP.accent))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pebble Piano").font(.ppHeadline)
                    Text(version).font(.ppCaption).foregroundColor(PP.inkMuted)
                }
            }

            VStack(alignment: .leading, spacing: PP.Space.s1) {
                Text("Made by").ppEyebrow()
                Text("Sambasevam Shanmugam").font(.ppCallout).foregroundColor(PP.ink)
                Text("Copyright © 2026 Sambasevam Shanmugam. All rights reserved, except for the third-party material below, which keeps its own licence.")
                    .font(.ppCaption).foregroundColor(PP.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: PP.Space.s4) {
                    section("Software") {
                        ForEach(ThirdPartyLicenses.all) { item in
                            licenseRow(item)
                        }
                    }
                    section("Books and music") {
                        contentRow("Learning the Code, Book 1",
                                   "James L. King III, 2003. Creative Commons Attribution-ShareAlike 4.0 (originally GNU Free Documentation License 1.1 or later). The passage notes and reference MIDI made from it are shared under the same licence.",
                                   url: "https://creativecommons.org/licenses/by-sa/4.0/")
                        contentRow("Beyer, Vorschule im Klavierspiel, Op. 101",
                                   "Ferdinand Beyer, ed. Ruthardt (Peters, 1895). Public domain. Scan from IMSLP #81208.",
                                   url: nil)
                        contentRow("Pebble Piano Starter Book",
                                   "Written for Pebble Piano and engraved with LilyPond. Traditional and public-domain tunes.",
                                   url: nil)
                    }
                    section("AI models") {
                        contentRow("Muse Spark and Muse Wonder",
                                   "Meta's models, used through the Meta Model API with your own key. They aren't included in the app.",
                                   url: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 380)

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(PPPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PP.Space.s6)
        .frame(width: 560)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            Text(title).ppEyebrow()
            content()
        }
    }

    private func licenseRow(_ item: ThirdPartyLicense) -> some View {
        let open = expanded == item.id
        return VStack(alignment: .leading, spacing: PP.Space.s1) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.ppCallout).foregroundColor(PP.ink)
                    Text("\(item.use) · \(item.license)").font(.ppCaption).foregroundColor(PP.inkMuted)
                }
                Spacer()
                if let url = URL(string: item.url) {
                    Link("Website", destination: url).font(.ppCaption)
                }
                Button(open ? "Hide licence" : "Licence") {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded = open ? nil : item.id }
                }
                .buttonStyle(PPGlassButtonStyle(height: 26))
                .accessibilityLabel(open ? "Hide \(item.name) licence" : "Show \(item.name) licence")
            }
            if open {
                Text(item.text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PP.inkMuted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(PP.Space.s2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: PP.Radius.sm, style: .continuous).fill(PP.surfaceRaised.opacity(0.6)))
            }
        }
    }

    private func contentRow(_ name: String, _ detail: String, url: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.ppCallout).foregroundColor(PP.ink)
                Spacer()
                if let url, let link = URL(string: url) {
                    Link("Licence", destination: link).font(.ppCaption)
                }
            }
            Text(detail).font(.ppCaption).foregroundColor(PP.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
