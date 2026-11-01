#if os(macOS)
import AppKit
import PianoAI
import PianoGraderCore
import SwiftUI

/// The Books tab: open a book, pick a piece by its systems, read it, review it, practise it.
struct BooksView: View {
    @ObservedObject var model: BookImportModel
    @State private var showAISettings = false

    var body: some View {
        HStack(alignment: .top, spacing: PP.Space.s4) {
            LibrarySidebar(model: model)
                .frame(width: 230)
            VStack(alignment: .leading, spacing: PP.Space.s3) {
                if let message = model.message {
                    Text(message).font(.ppCallout).foregroundColor(PP.warning)
                }
                if let note = model.aiKeyNote {
                    HStack(spacing: PP.Space.s3) {
                        Text(note).font(.ppCallout).foregroundColor(PP.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("AI settings…") { showAISettings = true }
                    }
                }
                if model.documentURL == nil {
                    emptyState
                } else {
                    switch model.phase {
                    case .choosing: BookPagePicker(model: model)
                    case .reading: ReadingProgressView(model: model)
                    case .review: ReviewView(model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { model.refreshLibrary() }
        .sheet(isPresented: $showAISettings) {
            AISettingsView { showAISettings = false; model.aiKeyNote = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: PP.Space.s4) {
            Spacer()
            Image(systemName: "book.pages").font(.system(size: 44)).foregroundColor(PP.accent)
            Text("Learn a piece from your own music book").font(.ppTitle)
            Text("Choose a book on the left (or open a PDF), pick the piece, and PerfectPiano reads the music, checks it, and teaches it to you.")
                .font(.ppBody).foregroundColor(PP.inkMuted).multilineTextAlignment(.center).frame(maxWidth: 520)
            Button("Open a book (PDF)…") { model.openBook() }
                .buttonStyle(PPPrimaryButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Library

/// The bundled books, books you've opened, and pieces you've read and saved.
struct LibrarySidebar: View {
    @ObservedObject var model: BookImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            Text("Books").font(.ppEyebrow).foregroundColor(PP.inkMuted)
            ForEach(model.library) { book in
                Button { model.open(book.url) } label: {
                    HStack(spacing: PP.Space.s2) {
                        Image(systemName: book.bundled ? "book.closed.fill" : "book.closed")
                        Text(book.title).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6).padding(.horizontal, PP.Space.s2)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(model.documentURL?.path == book.url.path ? PP.accent.opacity(0.15) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { model.openBook() } label: { Label("Open a PDF…", systemImage: "plus") }
                .buttonStyle(.plain).foregroundColor(PP.accent)

            Divider().padding(.vertical, PP.Space.s2)
            Text("Your pieces").font(.ppEyebrow).foregroundColor(PP.inkMuted)
            if model.pieces.isEmpty {
                Text("Pieces you read and check appear here, ready to practise.")
                    .font(.ppCaption).foregroundColor(PP.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.pieces) { piece in
                        Button { model.practise(piece) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(piece.title).font(.ppCallout).lineLimit(1)
                                Text("\(piece.book.replacingOccurrences(of: ".pdf", with: "")), p. \(piece.page + 1)")
                                    .font(.ppCaption).foregroundColor(PP.inkMuted).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 5).padding(.horizontal, PP.Space.s2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Practise it")
                        .contextMenu {
                            Button("Practise") { model.practise(piece) }
                            Button("Read again…") { model.readAgain(piece) }
                            Button("Show in Finder") { model.showInFinder(piece) }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s3)
    }
}

// MARK: - Choosing the piece

struct BookPagePicker: View {
    @ObservedObject var model: BookImportModel

    var body: some View {
        HStack(alignment: .top, spacing: PP.Space.s4) {
            VStack(spacing: PP.Space.s2) {
                HStack {
                    Button { model.show(page: model.pageIndex - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(model.pageIndex == 0)
                    Text("Page \(model.pageIndex + 1) of \(model.pageCount)").font(.ppCallout).monospacedDigit()
                    Button { model.show(page: model.pageIndex + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(model.pageIndex + 1 >= model.pageCount)
                    Spacer()
                    Text(model.documentURL?.lastPathComponent ?? "").font(.ppCaption).foregroundColor(PP.inkMuted)
                    Button("Re-scan page") { model.show(page: model.pageIndex, rescan: true) }
                        .help("Find the lines of music on this page again (the result is saved, so pages open instantly)")
                }
                ZStack {
                    if let image = model.pageImage, !model.isLoadingPage {
                        GeometryReader { geo in
                            let scale = min(geo.size.width / model.pageSize.width, geo.size.height / model.pageSize.height)
                            let w = model.pageSize.width * scale, h = model.pageSize.height * scale
                            ZStack(alignment: .topLeading) {
                                Image(nsImage: image).resizable().interpolation(.high).frame(width: w, height: h)
                                ForEach(model.systems, id: \.index) { s in
                                    systemOverlay(s, scale: scale)
                                }
                            }
                            .frame(width: w, height: h)
                            .background(Color.white)
                            .position(x: geo.size.width / 2, y: h / 2)
                        }
                    } else {
                        ProgressView("Finding the music on this page…")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            sidePanel.frame(width: 280)
        }
    }

    private func systemOverlay(_ s: FoundSystem, scale: CGFloat) -> some View {
        let selected = model.selection?.contains(s.index) ?? false
        return RoundedRectangle(cornerRadius: 6)
            .fill(selected ? PP.accent.opacity(0.18) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? PP.accent : PP.accent.opacity(0.35),
                                                               lineWidth: selected ? 2.5 : 1))
            .overlay(alignment: .topLeading) {
                Text("\(s.index + 1)")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(PP.onAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(selected ? PP.accent : PP.accent.opacity(0.6)))
                    .offset(x: -8, y: -8)
            }
            .frame(width: CGFloat(s.width) * scale, height: CGFloat(s.height) * scale)
            .offset(x: CGFloat(s.left) * scale, y: CGFloat(s.top) * scale)
            .contentShape(Rectangle())
            .onTapGesture { model.tapSystem(s.index, extend: NSEvent.modifierFlags.contains(.shift)) }
            .help("Click the first line of the piece; Shift-click the last")
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            Text("Pick a piece").font(.ppHeadline)
            Text("Click the first line of music in the piece, then Shift-click its last line.")
                .font(.ppCallout).foregroundColor(PP.inkMuted).fixedSize(horizontal: false, vertical: true)
            if let s = model.selection {
                Text(s.count == 1 ? "Line \(s.lowerBound + 1) selected" : "Lines \(s.lowerBound + 1)–\(s.upperBound + 1) selected")
                    .font(.ppCallout)
            }
            TextField("Name of the piece", text: $model.title)
                .textFieldStyle(.roundedBorder)
            Button("Read this piece") { model.read() }
                .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                .disabled(!model.canRead)
            Toggle("Ask Muse Wonder again", isOn: $model.freshRead)
                .font(.ppCallout)
                .help("Lines read before are reused (instant and free). Turn this on to read them again.")
            Text("Muse Wonder reads each line; PerfectPiano measures every note's pitch on the page and flags any bar it isn't sure of.")
                .font(.ppCaption).foregroundColor(PP.inkMuted).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s4)
    }
}

// MARK: - Reading

struct ReadingProgressView: View {
    @ObservedObject var model: BookImportModel

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            HStack {
                Text("Reading “\(model.title)”").font(.ppHeadline)
                Spacer()
                Button("Cancel") { model.startOver() }
            }
            let done = model.reads.filter { $0.step == .done }.count
            ProgressView(value: Double(done), total: Double(max(1, model.reads.count)))
            ScrollView {
                VStack(alignment: .leading, spacing: PP.Space.s3) {
                    ForEach(model.reads) { r in
                        VStack(alignment: .leading, spacing: PP.Space.s1) {
                            HStack(spacing: PP.Space.s2) {
                                stepIcon(r.step)
                                Text("Line \(r.id + 1): \(r.step.label)").font(.ppCallout)
                            }
                            Image(nsImage: r.image).resizable().aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 160).background(Color.white)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(_ step: BookImportModel.Step) -> some View {
        switch step {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundColor(PP.success)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundColor(PP.warning)
        case .waiting: Image(systemName: "circle").foregroundColor(PP.inkMuted)
        default: ProgressView().controlSize(.small)
        }
    }
}

// MARK: - Review

struct ReviewView: View {
    @ObservedObject var model: BookImportModel
    @State private var selected: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            HStack(spacing: PP.Space.s3) {
                Text("Check “\(model.title)”").font(.ppHeadline)
                Text(model.toReview == 0 ? "All bars checked" : "\(model.toReview) bar\(model.toReview == 1 ? "" : "s") to check")
                    .font(.ppCallout).foregroundColor(model.toReview == 0 ? PP.success : PP.warning)
                Spacer()
                Button("Start over") { model.startOver() }
                Button("Save and practise") { model.save() }
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                    .disabled(!model.canSave)
                    .help(model.canSave ? "Save the piece and open it in Practice" : "Check every flagged bar first")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: PP.Space.s4) {
                    ForEach(model.reads) { r in systemSection(r) }
                }
                .padding(.bottom, PP.Space.s6)
            }
        }
    }

    @ViewBuilder
    private func systemSection(_ r: BookImportModel.SystemRead) -> some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            Text("Line \(r.id + 1)").font(.ppEyebrow).foregroundColor(PP.inkMuted)
            // The page, with each bar marked: amber to check, green checked.
            GeometryReader { geo in
                let scale = geo.size.width / CGFloat(max(1, r.gray.width))
                ZStack(alignment: .topLeading) {
                    Image(nsImage: r.image).resizable().frame(width: geo.size.width, height: CGFloat(r.gray.height) * scale)
                    if let g = r.geometry {
                        ForEach(model.bars(inSystem: r.id)) { b in
                            if let j = b.bar.pageBar, j + 1 < g.barEdges.count {
                                let x0 = CGFloat(g.barEdges[j]) * scale
                                let x1 = CGFloat(g.barEdges[j + 1]) * scale
                                Rectangle()
                                    .fill(b.needsReview ? Color.orange.opacity(0.22) : Color.clear)
                                    .overlay(Rectangle().stroke(selected == b.id ? PP.accent : Color.clear, lineWidth: 2))
                                    .frame(width: max(1, x1 - x0), height: CGFloat(r.gray.height) * scale)
                                    .offset(x: x0)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selected = b.id }
                                    .help("Bar \(b.id): click to check or nudge its notes")
                            }
                        }
                    }
                }
                .background(Color.white)
            }
            .aspectRatio(CGFloat(r.gray.width) / CGFloat(max(1, r.gray.height)), contentMode: .fit)

            // What PerfectPiano read, engraved: red bars to check, green bars checked.
            if let engraved = model.engraving(ofSystem: r.id) {
                NotationView(score: engraved.score, scoreID: model.engravingIDs[r.id] ?? UUID(),
                             overlay: ScoreOverlay(mistakeMeasures: engraved.flagged))
                    .frame(height: 210)
            }

            ForEach(model.bars(inSystem: r.id).filter { $0.needsReview || $0.id == selected }) { b in
                BarCard(model: model, bar: b)
            }
        }
        .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s3)
    }
}

/// One bar to check: the bar from the page, why it was flagged, its notes with ↑/↓ to nudge,
/// and Listen, That's right, Fix this bar.
struct BarCard: View {
    @ObservedObject var model: BookImportModel
    let bar: BookImportModel.ReviewBar

    var body: some View {
        HStack(alignment: .top, spacing: PP.Space.s4) {
            if let image = bar.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 180).background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: PP.Space.s2) {
                HStack {
                    Text("Bar \(bar.id)").font(.ppHeadline)
                    statusLabel
                }
                if bar.needsReview, let reason = bar.reason {
                    Text(reason).font(.ppCallout).foregroundColor(PP.inkMuted)
                }
                staffRow(.upper, "Right hand")
                staffRow(.lower, "Left hand")
                HStack(spacing: PP.Space.s2) {
                    Button { model.listen(bar.id) } label: { Label("Listen", systemImage: "speaker.wave.2") }
                    Button("That's right") { model.confirm(bar.id) }
                        .disabled(!bar.needsReview)
                    Button {
                        model.fix(bar.id)
                    } label: {
                        if model.fixing.contains(bar.id) { ProgressView().controlSize(.small) } else { Text("Fix this bar") }
                    }
                    .disabled(model.fixing.contains(bar.id))
                    .help("Ask Muse Wonder to read just this bar again")
                }
            }
            Spacer()
        }
        .padding(PP.Space.s3)
        .background(RoundedRectangle(cornerRadius: PP.Radius.sm).fill(PP.surfaceRaised))
    }

    private var statusLabel: some View {
        let (text, color): (String, Color) = {
            switch bar.resolution {
            case .needsReview: return ("to check", PP.warning)
            case .confirmed: return ("checked", PP.success)
            case .fixed: return ("re-read and checked", PP.success)
            case .nudged: return ("corrected", PP.success)
            case .trusted: return ("measured", PP.success)
            }
        }()
        return Text(text).font(.ppCaption).foregroundColor(color)
    }

    private func staffRow(_ staff: SystemReading.StaffName, _ label: String) -> some View {
        HStack(spacing: PP.Space.s1) {
            Text(label).font(.ppCaption).foregroundColor(PP.inkMuted).frame(width: 72, alignment: .leading)
            ForEach(Array(bar.bar.notes(staff).enumerated()), id: \.offset) { k, n in
                noteChip(staff, k, n)
            }
        }
    }

    private func noteChip(_ staff: SystemReading.StaffName, _ k: Int, _ n: BarMerge.Note) -> some View {
        HStack(spacing: 2) {
            Text(n.note.rest ? "rest" : n.name).font(.system(size: 12, weight: .semibold).monospacedDigit())
            Text(symbol(n.note)).font(.system(size: 11)).foregroundColor(PP.inkMuted)
            if !n.note.rest {
                VStack(spacing: 0) {
                    Button { model.nudge(bar.id, staff: staff, note: k, by: 1) } label: { Image(systemName: "chevron.up") }
                        .help("One line or space higher")
                    Button { model.nudge(bar.id, staff: staff, note: k, by: -1) } label: { Image(systemName: "chevron.down") }
                        .help("One line or space lower")
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .bold))
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(PP.surface))
    }

    private func symbol(_ note: SystemReading.Note) -> String {
        let base: String
        switch note.duration {
        case .whole: base = "𝅝"
        case .half: base = "𝅗𝅥"
        case .quarter: base = "♩"
        case .eighth: base = "♪"
        case .sixteenth: base = "𝅘𝅥𝅯"
        }
        return note.dotted ? base + "." : base
    }
}
#endif
