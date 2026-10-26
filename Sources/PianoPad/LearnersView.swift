#if os(macOS)
import PianoPadState
import SwiftUI

// Who's playing: the launch screens (add the first learner, pick a learner), the toolbar
// avatar menu, and the sheets to add and manage learners.

/// The avatars to choose from: SF Symbols, so they match the app's icons.
enum LearnerAvatars {
    static let all = [
        "person.crop.circle", "star.fill", "music.note", "pianokeys", "heart.fill", "leaf.fill",
        "sun.max.fill", "moon.stars.fill", "hare.fill", "tortoise.fill", "bird.fill", "pawprint.fill",
    ]
}

/// A learner's avatar in a tinted circle. Adults and children get different tints.
struct LearnerAvatar: View {
    let learner: Learner
    var size: CGFloat = 32

    var body: some View {
        AvatarCircle(symbol: learner.avatar, kind: learner.kind, size: size)
            .accessibilityLabel(learner.name)
    }
}

struct AvatarCircle: View {
    let symbol: String
    let kind: Learner.Kind
    var size: CGFloat
    var selected = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundColor(selected ? PP.onAccent : PP.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(selected ? PP.accent : (kind == .child ? PP.apricot : PP.lilac)))
            .overlay(Circle().strokeBorder(PP.surfaceGlassEdge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Launch screens

/// Shown over the practice screen at launch: "Add learner" when there are none, else
/// "Who's playing?" when there is more than one.
struct LearnerGateView: View {
    @EnvironmentObject var session: PlaySession

    var body: some View {
        ZStack {
            PPBackdrop()
            Group {
                if session.learners.isEmpty {
                    // First launch: setup, ending on the first lesson page.
                    OnboardingView()
                } else {
                    LearnerPickerView()
                }
            }
            .ppGlass()
        }
        .foregroundColor(PP.ink)
    }
}

/// One tile per learner, plus "Add learner".
struct LearnerPickerView: View {
    @EnvironmentObject var session: PlaySession
    @State private var adding = false

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 140), spacing: PP.Space.s4)]

    var body: some View {
        VStack(spacing: PP.Space.s6) {
            Text("Who's playing?").font(.ppTitle)
            LazyVGrid(columns: columns, spacing: PP.Space.s4) {
                ForEach(session.learners) { learner in
                    Button { session.pickLearner(learner.id) } label: {
                        VStack(spacing: PP.Space.s2) {
                            LearnerAvatar(learner: learner, size: 72)
                            Text(learner.name).font(.ppCallout).lineLimit(1)
                        }
                        .frame(width: 120, height: 128)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Play as \(learner.name)")
                }
                Button { adding = true } label: {
                    VStack(spacing: PP.Space.s2) {
                        Image(systemName: "plus")
                            .font(.system(size: 28, weight: .semibold))
                            .frame(width: 72, height: 72)
                            .background(Circle().strokeBorder(PP.inkStaff, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                        Text("Add learner").font(.ppCallout).foregroundColor(PP.inkMuted)
                    }
                    .frame(width: 120, height: 128)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 600)
        }
        .sheet(isPresented: $adding) {
            // A new learner goes through the same setup as the first one.
            OnboardingView(onCancel: { adding = false }, onFinish: { adding = false })
                .padding(PP.Space.s6)
                .environmentObject(session)
        }
    }
}

// MARK: - Toolbar menu

/// The active learner's avatar in the header: switch learner, add, manage.
struct LearnerMenu: View {
    @EnvironmentObject var session: PlaySession
    @State private var adding = false
    @State private var managing = false

    var body: some View {
        Menu {
            ForEach(session.learners.filter { $0.id != session.learner?.id }) { learner in
                Button("Switch to \(learner.name)") { session.switchLearner(to: learner.id) }
            }
            if session.learners.count > 1 { Divider() }
            Button("Add learner…") { adding = true }
            Button("Manage learners…") { managing = true }
        } label: {
            HStack(spacing: PP.Space.s2) {
                if let learner = session.learner {
                    LearnerAvatar(learner: learner, size: 24)
                    Text(learner.name).font(.ppCallout).lineLimit(1)
                } else {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .menuStyle(.button)
        .buttonStyle(PPGlassButtonStyle())
        .fixedSize()
        .help("Who's playing: switch, add or manage learners")
        .accessibilityLabel("Learner: \(session.learner?.name ?? "none")")
        .sheet(isPresented: $adding) {
            // A new learner goes through the same setup as the first one.
            OnboardingView(onCancel: { adding = false }, onFinish: { adding = false })
                .padding(PP.Space.s6)
                .environmentObject(session)
        }
        .sheet(isPresented: $managing) {
            ManageLearnersView { managing = false }
                .environmentObject(session)
        }
    }
}

// MARK: - Add or edit a learner

/// Name, avatar, adult or child, and (when adding) a rough level.
struct LearnerForm: View {
    enum Mode: Equatable {
        /// The first learner, on the launch screen: no Cancel.
        case first
        case add
        case edit(Learner)
    }

    @EnvironmentObject var session: PlaySession
    let mode: Mode
    var onDone: () -> Void = {}

    @State private var name = ""
    @State private var avatar = Learner.defaultAvatar
    @State private var kind = Learner.Kind.adult
    @State private var level: Learner.Level?
    @State private var loaded = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEditing: Bool { if case .edit = mode { return true } else { return false } }

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            if mode != .first {
                Text(isEditing ? "Edit learner" : "Add learner").font(.ppHeadline)
            }
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.ppBody)
                .onSubmit(save)

            VStack(alignment: .leading, spacing: PP.Space.s2) {
                Text("Avatar").ppEyebrow()
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: PP.Space.s2), count: 6),
                          alignment: .leading, spacing: PP.Space.s2) {
                    ForEach(LearnerAvatars.all, id: \.self) { symbol in
                        Button { avatar = symbol } label: {
                            AvatarCircle(symbol: symbol, kind: kind, size: 40, selected: avatar == symbol)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                        .accessibilityAddTraits(avatar == symbol ? .isSelected : [])
                    }
                }
            }

            Picker("Learner", selection: $kind) {
                Text("Adult").tag(Learner.Kind.adult)
                Text("Child").tag(Learner.Kind.child)
            }
            .pickerStyle(.segmented)

            if !isEditing {
                Picker("Level", selection: $level) {
                    Text("Not sure").tag(Learner.Level?.none)
                    Text("Just starting").tag(Learner.Level?.some(.beginner))
                    Text("Knows the basics").tag(Learner.Level?.some(.basics))
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                if mode != .first {
                    Button("Cancel", action: onDone)
                        .buttonStyle(PPGlassButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                Button(isEditing ? "Save" : (mode == .first ? "Start" : "Add"), action: save)
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if case .edit(let learner) = mode {
            name = learner.name
            avatar = learner.avatar
            kind = learner.kind
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        switch mode {
        case .edit(let learner):
            if trimmedName != learner.name { session.renameLearner(learner.id, to: trimmedName) }
            if avatar != learner.avatar { session.setLearnerAvatar(learner.id, to: avatar) }
            if kind != learner.kind { session.setLearnerKind(learner.id, to: kind) }
            onDone()
        case .first, .add:
            let wasFirst = session.learners.isEmpty
            guard session.addLearner(name: trimmedName, avatar: avatar, kind: kind, level: level) != nil else { return }
            // The main window asks (this form goes away with the launch screen).
            if wasFirst && session.shouldOfferCalibration { session.offersCalibration = true }
            onDone()
        }
    }
}

// MARK: - Manage learners

/// Rename, change avatar or kind, reset progress, export and delete.
struct ManageLearnersView: View {
    @EnvironmentObject var session: PlaySession
    var onDone: () -> Void

    @State private var editing: Learner?
    @State private var deleting: Learner?
    @State private var resetting: Learner?

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s4) {
            Text("Learners").font(.ppHeadline)
            VStack(spacing: 0) {
                ForEach(session.learners) { learner in
                    HStack(spacing: PP.Space.s3) {
                        LearnerAvatar(learner: learner, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(learner.name).font(.ppCallout)
                            Text(subtitle(learner)).font(.ppCaption).foregroundColor(PP.inkMuted)
                        }
                        Spacer()
                        Button("Edit…") { editing = learner }
                            .buttonStyle(PPGlassButtonStyle())
                        Menu {
                            Button("Export…") { session.exportLearner(learner.id) }
                            Button("Reset progress…") { resetting = learner }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.button)
                        .buttonStyle(PPIconButtonStyle())
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Export or reset \(learner.name)'s progress")
                        .accessibilityLabel("More for \(learner.name)")
                        Button { deleting = learner } label: { Image(systemName: "trash") }
                            .buttonStyle(PPIconButtonStyle())
                            .help("Delete \(learner.name)")
                            .accessibilityLabel("Delete \(learner.name)")
                    }
                    .padding(.vertical, PP.Space.s2)
                    if learner.id != session.learners.last?.id { Divider() }
                }
            }
            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(PP.Space.s6)
        .frame(width: 480)
        .sheet(item: $editing) { learner in
            LearnerForm(mode: .edit(learner)) { editing = nil }
                .padding(PP.Space.s6)
                .frame(width: 440)
                .environmentObject(session)
        }
        .background(
            // A second alert needs its own view in SwiftUI before macOS 14.
            Color.clear.alert(item: $resetting) { learner in
                Alert(
                    title: Text("Reset \(learner.name)'s progress?"),
                    message: Text("This deletes \(learner.name)'s saved takes and progress. Settings and recent pieces stay. Export first to keep a copy."),
                    primaryButton: .destructive(Text("Reset")) { session.resetProgress(for: learner.id) },
                    secondaryButton: .cancel()
                )
            }
        )
        .alert(item: $deleting) { learner in
            Alert(
                title: Text("Delete \(learner.name)?"),
                message: Text("This removes \(learner.name)'s settings, recent pieces, saved takes and progress from this Mac. Books, annotations, backing tracks and the piano calibration stay."),
                primaryButton: .destructive(Text("Delete")) {
                    session.deleteLearner(learner.id)
                    if session.learners.isEmpty { onDone() }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func subtitle(_ learner: Learner) -> String {
        var parts = [learner.kind == .child ? "Child" : "Adult"]
        if learner.id == session.learner?.id { parts.append("playing now") }
        return parts.joined(separator: " · ")
    }
}
#endif
