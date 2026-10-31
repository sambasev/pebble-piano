#if os(macOS)
import PianoLessons
import PianoPadState
import SwiftUI

/// The book as the map: a unit's pages in order, each locked, next, in progress or done with
/// its stars, ending with the learner's goal song. Continue opens the exact step left off.
struct UnitMapView: View {
    @ObservedObject var runner: LessonRunner
    let unit: LessonUnit
    @State private var showGrownUps = false

    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: PP.Space.s4)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PP.Space.s6) {
                header
                if let warmUp = runner.warmUp {
                    WarmUpCard(runner: runner, warmUp: warmUp)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: PP.Space.s4) {
                    ForEach(Array(unit.pages.filter { !$0.isGoalSongPage }.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: PP.Space.s2) {
                            PageCard(runner: runner, page: page, number: index + 1)
                            if runner.course == .ear, let best = runner.previousEarBest(for: page) {
                                Text("Previous best: \(best)/10").font(.ppCaption).foregroundColor(PP.inkMuted)
                            }
                        }
                    }
                    if unit.pages.contains(where: \.isGoalSongPage) { GoalCard(runner: runner, unit: unit) }
                }
                Divider().padding(.vertical, PP.Space.s3)
                EarPathSection(runner: runner)
            }
            .padding(.bottom, PP.Space.s6)
        }
    }

    private var header: some View {
        let done = runner.completedPages.count
        let stars = runner.unitStars
        return HStack(alignment: .bottom, spacing: PP.Space.s6) {
            VStack(alignment: .leading, spacing: PP.Space.s1) {
                Text(runner.course == .piano ? "Book 1 · Unit 1" : "Ear training · 8 levels").ppEyebrow()
                Text(unit.title).font(.ppTitle)
                HStack(spacing: PP.Space.s4) {
                    Text("\(done) of \(unit.pages.count) pages done").font(.ppCallout).foregroundColor(PP.inkMuted)
                    if stars.possible > 0 {
                        Label("\(stars.earned) of \(stars.possible)", systemImage: "star.fill")
                            .font(.ppCallout).foregroundColor(PP.inkMuted)
                    }
                    if runner.streakDays > 0 {
                        Label(WeeklyStreak.label(days: runner.streakDays), systemImage: "flame.fill")
                            .font(.ppCallout).foregroundColor(PP.accent)
                            .help("Days you practised this week. Missing a day costs nothing.")
                    }
                }
                ProgressView(value: Double(done), total: Double(max(1, unit.pages.count)))
                    .tint(PP.accent)
                    .frame(maxWidth: 320)
                if runner.isChild {
                    Button {
                        showGrownUps = true
                    } label: {
                        Label("For grown-ups", systemImage: "person.2.fill").font(.ppCallout)
                    }
                    .buttonStyle(.borderless)
                    .help("This week, notes learned, where they're stuck, a tip, and the teacher")
                    .sheet(isPresented: $showGrownUps) { GrownUpsView(runner: runner) }
                } else {
                Menu {
                    ForEach(Persona.builtIn, id: \.id) { p in
                        Button {
                            runner.setPersona(p.id)
                        } label: {
                            if p.id == runner.persona.id {
                                Label("\(p.name): \(p.summary)", systemImage: "checkmark")
                            } else {
                                Text("\(p.name): \(p.summary)")
                            }
                        }
                    }
                } label: {
                    Label("Teacher: \(runner.persona.name)", systemImage: "person.fill")
                        .font(.ppCallout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Who teaches: how strict the judging is and how many stars a song needs")
                }
            }
            Spacer()
            if runner.hasSessionUnderway {
                Button("Finish for today") { runner.finishSession() }
                    .buttonStyle(PPGlassButtonStyle(height: PP.Size.targetMin))
                    .help("End this session and see what you did")
            }
            if let target = runner.continueTarget {
                Button {
                    runner.open(target.page.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.step > 0 ? "Continue" : "Start")
                        Text(target.step > 0 ? "\(target.page.title) · step \(target.step + 1)" : target.page.title)
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.85)
                    }
                }
                .buttonStyle(PPPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// The second path on the same lesson map. Opening a card selects its unit before routing.
private struct EarPathSection: View {
    @ObservedObject var runner: LessonRunner
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: PP.Space.s4)]

    var body: some View {
        let unit = EarLessonCourse.unit
        let progress = runner.earPathProgress
        let states = progress.mapValues {
            CoachPageState(completed: $0.isCompleted, inProgress: $0.currentBlock > 0,
                           bestStars: $0.bestStars, flagged: !$0.flaggedBlocks.isEmpty)
        }
        let next = Coach.nextPage(in: unit, states: states)
        let done = progress.values.filter(\.isCompleted).count
        return VStack(alignment: .leading, spacing: PP.Space.s6) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: PP.Space.s2) {
                    Text("Ear training path · 8 levels").ppEyebrow()
                    Label("Train your ear", systemImage: "ear").font(.ppTitle)
                    Text("Listen and recognize notes, chords, and jazz harmony.")
                        .font(.ppCallout).foregroundColor(PP.inkMuted)
                    Text("\(done) of \(unit.pages.count) lessons done").font(.ppCallout).foregroundColor(PP.inkMuted)
                    ProgressView(value: Double(done), total: Double(unit.pages.count))
                        .tint(PP.accent).frame(maxWidth: 320)
                }
                Spacer()
                if let next {
                    Button(progress.isEmpty ? "Start ear training" : "Continue ear training") { runner.openEarPage(next.id) }
                        .buttonStyle(PPPrimaryButtonStyle())
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: PP.Space.s4) {
                ForEach(Array(unit.pages.enumerated()), id: \.element.id) { index, page in
                    let saved = progress[page.id]
                    Button { runner.openEarPage(page.id) } label: {
                        VStack(alignment: .leading, spacing: PP.Space.s3) {
                            HStack {
                                Text("\(index + 1)").font(.ppHeadline)
                                    .frame(width: 34, height: 34).background(Circle().fill(PP.surfaceRaised))
                                Spacer()
                                if saved?.isCompleted == true {
                                    Image(systemName: saved?.flaggedBlocks.isEmpty == true ? "checkmark.circle.fill" : "arrow.counterclockwise")
                                        .foregroundColor(saved?.flaggedBlocks.isEmpty == true ? PP.success : PP.warning)
                                } else if next?.id == page.id {
                                    Text("Next").font(.ppCaption).foregroundColor(PP.accent)
                                }
                            }
                            Text(page.title).font(.ppHeadline).lineLimit(2)
                            if let best = runner.previousEarBest(for: page) {
                                Text("Previous best: \(best)/10").font(.ppCaption).foregroundColor(PP.inkMuted)
                            }
                            Spacer(minLength: 0)
                            Text(saved?.isCompleted == true ? (saved?.flaggedBlocks.isEmpty == true ? "Play again" : "Revisit skipped step")
                                 : (saved?.currentBlock ?? 0 > 0 ? "Continue · step \((saved?.currentBlock ?? 0) + 1)" : "\(page.blocks.count) steps"))
                                .font(.ppCaption).foregroundColor(PP.inkMuted)
                        }
                        .foregroundColor(PP.ink).padding(PP.Space.s4)
                        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: PP.Radius.lg).fill(PP.surfaceGlass))
                        .overlay(RoundedRectangle(cornerRadius: PP.Radius.lg).strokeBorder(PP.surfaceGlassEdge))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Open \(page.title)")
                }
            }
        }
    }
}

/// One page of the unit.
private struct PageCard: View {
    @ObservedObject var runner: LessonRunner
    let page: LessonPage
    let number: Int

    private enum CardState { case locked, next, inProgress(step: Int), done(stars: Int?), open }

    private var state: CardState {
        let saved = runner.progress[page.id]
        if !runner.isUnlocked(page.id) { return .locked }
        if let saved, saved.isCompleted { return .done(stars: saved.bestStars) }
        if let saved, saved.currentBlock > 0 { return .inProgress(step: saved.currentBlock) }
        if runner.nextPageID == page.id { return .next }
        return .open
    }

    var body: some View {
        let state = self.state
        let isNext: Bool = { if case .next = state { return true }; if case .inProgress = state { return runner.nextPageID == page.id }; return false }()
        let locked: Bool = { if case .locked = state { return true }; return false }()
        return Button {
            runner.open(page.id)
        } label: {
            VStack(alignment: .leading, spacing: PP.Space.s3) {
                HStack {
                    Text("\(number)")
                        .font(.ppHeadline)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(isNext ? PP.accent : PP.surfaceRaised))
                        .foregroundColor(isNext ? PP.onAccent : PP.ink)
                    Spacer()
                    badge(state)
                }
                Text(page.title).font(.ppHeadline).lineLimit(2)
                if page.isCheckpointSong {
                    Label("Checkpoint song", systemImage: "music.note")
                        .font(.ppCaption).foregroundColor(PP.warning)
                } else if !page.newNotes.isEmpty {
                    HStack(spacing: PP.Space.s1) {
                        ForEach(page.newNotes, id: \.self) { note in
                            Text(note.name)
                                .font(.ppCaption)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(PP.lilac.opacity(0.6)))
                        }
                        Text("new").font(.ppCaption).foregroundColor(PP.inkMuted)
                    }
                }
                Spacer(minLength: 0)
                footer(state)
            }
            .padding(PP.Space.s4)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: PP.Radius.lg, style: .continuous)
                .fill(isNext ? PP.accent.opacity(0.10) : PP.surfaceGlass))
            .overlay(RoundedRectangle(cornerRadius: PP.Radius.lg, style: .continuous)
                .strokeBorder(isNext ? PP.accent : PP.surfaceGlassEdge, lineWidth: isNext ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.55 : 1)
        .help(locked ? "Finish the page before to open this one" : "Open \(page.title)")
    }

    @ViewBuilder
    private func badge(_ state: CardState) -> some View {
        switch state {
        case .locked: Image(systemName: "lock.fill").foregroundColor(PP.inkMuted)
        case .done(let stars):
            HStack(spacing: 6) {
                if let stars { StarsView(stars: stars, size: 14) } else if !runner.isChild {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(PP.success)
                }
                if runner.isChild, let sticker = runner.sticker(forPage: page.id) {
                    StickerView(sticker: sticker, size: 30)
                }
            }
        case .next: Text("Next").font(.ppCaption).foregroundColor(PP.accent)
        case .inProgress, .open: EmptyView()
        }
    }

    @ViewBuilder
    private func footer(_ state: CardState) -> some View {
        switch state {
        case .inProgress(let step):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(step), total: Double(max(1, page.blocks.count))).tint(PP.accent)
                Text("Step \(step + 1) of \(page.blocks.count)").font(.ppCaption).foregroundColor(PP.inkMuted)
            }
        case .done:
            Text("Play again").font(.ppCaption).foregroundColor(PP.inkMuted)
        case .locked:
            Text("\(page.blocks.count) steps").font(.ppCaption).foregroundColor(PP.inkMuted)
        case .next, .open:
            Text("\(page.blocks.count) steps").font(.ppCaption).foregroundColor(PP.accent)
        }
    }
}

/// The learner's goal song, pinned at the end of the unit: the unit's goal-song page.
private struct GoalCard: View {
    @ObservedObject var runner: LessonRunner
    let unit: LessonUnit

    var body: some View {
        let page = unit.pages.first { $0.isGoalSongPage }
        let regular = unit.pages.filter { !$0.isGoalSongPage }
        let left = regular.filter { !runner.completedPages.contains($0.id) }.count
        let unlocked = page.map { runner.isUnlocked($0.id) } ?? false
        let saved = page.flatMap { runner.progress[$0.id] }
        let isNext = page.map { runner.nextPageID == $0.id } ?? false
        Button {
            if let page { runner.open(page.id) }
        } label: {
            VStack(alignment: .leading, spacing: PP.Space.s3) {
                HStack {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(PP.warning.opacity(0.25)))
                    Spacer()
                    if let stars = saved?.bestStars {
                        StarsView(stars: stars, size: 14)
                    } else if !unlocked {
                        Image(systemName: "lock.fill").foregroundColor(PP.inkMuted)
                    } else if isNext {
                        Text("Next").font(.ppCaption).foregroundColor(PP.accent)
                    }
                }
                Text("Goal song").ppEyebrow()
                Text(runner.goalSong?.title ?? "Your song").font(.ppHeadline).lineLimit(2)
                Spacer(minLength: 0)
                Text(unlocked ? (saved?.isCompleted == true ? "Play again" : "Ready to play") : "\(left) page\(left == 1 ? "" : "s") to go")
                    .font(.ppCaption).foregroundColor(unlocked ? PP.accent : PP.inkMuted)
            }
            .padding(PP.Space.s4)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: PP.Radius.lg, style: .continuous)
                .fill(isNext ? PP.warning.opacity(0.12) : PP.surfaceGlass))
            .overlay(RoundedRectangle(cornerRadius: PP.Radius.lg, style: .continuous)
                .strokeBorder(PP.warning.opacity(isNext ? 1 : 0.6),
                              style: StrokeStyle(lineWidth: isNext ? 2 : 1.5, dash: unlocked ? [] : [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .help(unlocked ? "Play your goal song" : "Finish the pages before to unlock your song")
    }
}
#endif
