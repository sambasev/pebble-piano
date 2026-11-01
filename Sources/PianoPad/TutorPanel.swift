#if os(macOS)
import SwiftUI
import Security
import PianoLessons

enum TutorKeychain {
    static let service = "com.sambasev.perfectpiano.tutor"
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "meta"] }
    static func read() -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ key: String) -> OSStatus {
        let data = Data(key.utf8)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result != errSecItemNotFound { return result }
        var q = query; q[kSecValueData as String] = data
        return SecItemAdd(q as CFDictionary, nil)
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
}

struct TutorPanel: View {
    @EnvironmentObject var session: PlaySession
    @State private var settings = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Piece tutor").font(.headline); Spacer(); Button("AI settings") { settings = true } }
            if let engine = session.tutor {
                Text(session.tutorAI.isEmpty ? session.tutorText : session.tutorAI)
                if session.tutorBusy { ProgressView("Preparing explanation…") }
                Text("\(engine.exercise.title) · bars \(engine.exercise.measures.lowerBound)–\(engine.exercise.measures.upperBound) · \(Int(engine.exercise.tempoPercent))%")
                Text("Clean runs: \(engine.cleanStreak)/\(engine.needed)").font(.caption)
                if session.tutorAttempt == nil {
                    Text("Ready when you are. Click Start assessment below, then play after the count-in.")
                        .font(.callout)
                }
                Button {
                    session.startTutorExercise()
                } label: {
                    Label(engine.exercise.kind == .assessment ? "Start assessment" : "Start exercise", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.phase == .recording)
                HStack {
                    Button("Hear it first") { session.startListening() }
                    Button("Learn note by note") { session.tutor?.learnNotes(); session.startTutorExercise() }
                }
                HStack {
                    Button("Try again") { session.retryTutorExercise() }
                    Button("Reassess piece") { session.tutor?.reassess(); session.startTutorExercise() }
                }
                Button("Move on from exercise") { session.tutor?.skip() }
                HStack {
                    Button("What went wrong?") { session.askTutor("What went wrong?") }
                    Button("Why this exercise?") { session.askTutor("Why this exercise?") }
                }.disabled(session.phase == .recording)
                Button("End tutoring") { session.endTutoring() }
            } else if session.reference?.notes.isEmpty == false {
                Button("Teach me this piece") { session.beginTutoring() }
            }
        }.sheet(isPresented: $settings) { TutorSettings() }
    }
}
struct TutorSettings: View {
    @State private var key = ""
    @AppStorage("TutorModel") private var model = "muse-spark-1.3"
    @State private var status = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Meta Muse tutor").font(.headline)
            Text("Your piano audio stays on this Mac. AI receives score context, grading findings and the selected exercise.")
            SecureField("Meta API key", text: $key)
            TextField("Model", text: $model)
            HStack {
                Button("Save key") { status = TutorKeychain.save(key) == errSecSuccess ? "Key saved." : "Could not save key."; key = "" }.disabled(key.isEmpty)
                Button("Remove key") { TutorKeychain.remove(); status = "Key removed." }
                Button("Test connection") {
                    guard let saved = TutorKeychain.read() else { status = "Save a key first."; return }
                    status = "Testing…"
                    Task { @MainActor in
                        do { _ = try await MetaTutorFeedbackClient(key: saved, model: model).explain(context: "Connection test. No performance assessed.", question: "Say ready."); status = "Connected." }
                        catch { status = "Connection failed. Check your key, model and network." }
                    }
                }
            }
            Text(status)
            Button("Done") { dismiss() }
        }.padding(24).frame(width: 480)
    }
}
#endif
