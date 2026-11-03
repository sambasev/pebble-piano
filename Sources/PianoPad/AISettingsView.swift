#if os(macOS)
import PianoAI
import SwiftUI

// AI settings (hackathon H1): API keys, saved in the Keychain, and checks that call each
// endpoint once. Keys are typed here and never shown again; only "Saved" is displayed.

struct AISettingsView: View {
    var onDone: () -> Void

    @State private var tutorModel = AISettings.shared.tutorModel
    @State private var provider: ModelProvider = .meta
    @State private var keyDraft = ""
    @State private var modalURL = AISettings.shared.modalBaseURL?.absoluteString ?? ""
    @State private var openModel = ""
    @State private var source: APIKeyStore.Source = .none
    @State private var message: String?
    @State private var running = false
    @State private var results: [AIChecks.Result] = []
    @State private var totals = UsageLog.Totals()

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text("AI settings").font(.ppHeadline)

            Picker("Provider", selection: $provider) {
                ForEach(ModelProvider.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            keySection

            if provider == .meta {
                LabeledContent("Practice tutor model") {
                    TextField(MetaModels.spark, text: $tutorModel)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveSettings)
                }
                Text("The Practice tutor uses this Meta key. Piano audio and grading stay on your Mac.")
                    .font(.ppCaption).foregroundColor(PP.inkMuted)
            }

            if provider == .modal {
                LabeledContent("Base URL") {
                    TextField("https://…modal.run/v1", text: $modalURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveSettings)
                }
            }
            if provider != .meta {
                LabeledContent("Model to check") {
                    TextField("model ID (optional)", text: $openModel)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(saveSettings)
                }
            }

            HStack {
                Button(running ? "Checking…" : "Run checks", action: runChecks)
                    .disabled(running || (provider.requiresKey && source == .none))
                if running { ProgressView().controlSize(.small) }
                Spacer()
                Text("Calls \(totals.calls) · tokens in \(totals.inputTokens), out \(totals.outputTokens)")
                    .font(.ppCaption.monospacedDigit())
                    .foregroundColor(PP.inkMuted)
            }

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: PP.Space.s2) {
                    ForEach(results) { r in
                        HStack(alignment: .firstTextBaseline, spacing: PP.Space.s2) {
                            Image(systemName: r.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundColor(r.passed ? PP.success : PP.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(r.name) · \(String(format: "%.1f s", r.seconds))").font(.ppCallout)
                                Text(r.detail).font(.ppCaption).foregroundColor(PP.inkMuted)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            if let message { Text(message).font(.ppCaption).foregroundColor(PP.inkMuted) }

            HStack {
                Spacer()
                Button("Done") { saveSettings(); onDone() }
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PP.Space.s6)
        .frame(width: 560)
        .onAppear(perform: load)
        .onChange(of: provider) { _ in load() }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            HStack {
                SecureField(provider.requiresKey ? "Paste your \(provider.displayName) key" : "Key (optional)",
                            text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveKey)
                Button("Save", action: saveKey).disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Remove") { setKey(nil) }.disabled(source != .keychain)
            }
            Text(sourceText).font(.ppCaption).foregroundColor(PP.inkMuted)
        }
    }

    private var sourceText: String {
        switch source {
        case .keychain: return "Saved in the Keychain."
        case .environment(let name): return "Using \(name) from the environment."
        case .none: return provider.requiresKey ? "No key yet." : "No key (fine if your deployment doesn't need one)."
        }
    }

    private func load() {
        keyDraft = ""
        source = APIKeyStore.source(for: provider)
        openModel = AISettings.shared.openModel(for: provider) ?? ""
        results = []
        message = nil
        Task { totals = await UsageLog.shared.totals() }
    }

    private func saveKey() { setKey(keyDraft) }

    private func setKey(_ key: String?) {
        do {
            try APIKeyStore.setKey(key, for: provider)
            message = key == nil ? "Key removed." : "Key saved."
        } catch {
            message = error.localizedDescription
        }
        keyDraft = ""
        source = APIKeyStore.source(for: provider)
    }

    private func saveSettings() {
        AISettings.shared.tutorModel = tutorModel
        if provider == .modal {
            let trimmed = modalURL.trimmingCharacters(in: .whitespaces)
            AISettings.shared.modalBaseURL = trimmed.isEmpty ? nil : URL(string: trimmed)
        }
        if provider != .meta { AISettings.shared.setOpenModel(openModel, for: provider) }
    }

    private func runChecks() {
        saveSettings()
        running = true
        results = []
        message = nil
        let provider = provider
        Task {
            do {
                let client = try ModelClient.configured(provider)
                let r = await AIChecks.run(client, openModel: AISettings.shared.openModel(for: provider))
                results = r
                message = r.allSatisfy(\.passed) ? "All checks passed." : nil
            } catch {
                message = error.localizedDescription
            }
            totals = await UsageLog.shared.totals()
            running = false
        }
    }
}
#endif
