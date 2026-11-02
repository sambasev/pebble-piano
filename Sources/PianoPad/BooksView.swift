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
                    // A piece is read in place, on its page; the check view opens only if a bar needs a look.
                    case .choosing, .reading: BookPagePicker(model: model)
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
                        let status = model.status(ofBook: book.url)
                        Image(systemName: book.bundled ? "book.closed.fill" : "book.closed")
                            .foregroundColor(status?.color ?? (model.wasOpened(book.url) ? PP.ink : PP.inkMuted))
                        Text(book.title).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if let status {
                            let count = model.pieces(in: book.url).count
                            PieceStatusTag(status: status, text: "\(count)")
                                .help("\(count) piece\(count == 1 ? "" : "s") read from this book; furthest: \(status.label.lowercased())")
                        } else if model.wasOpened(book.url) {
                            Text("Opened").font(.ppCaption).foregroundColor(PP.inkMuted)
                                .help("Opened before; no piece read from it yet")
                        }
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
                            HStack(spacing: PP.Space.s2) {
                                let status = model.status(piece)
                                Circle().fill(status.color).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(piece.title).font(.ppCallout).lineLimit(1)
                                    Text("\(piece.book.replacingOccurrences(of: ".pdf", with: "")), p. \(piece.page + 1)")
                                        .font(.ppCaption).foregroundColor(PP.inkMuted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                PieceStatusTag(status: status)
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
    /// A line's box while one of its handles is dragged; set on the model when the drag ends.
    @State private var resizing: FoundSystem?

    var body: some View {
        HStack(alignment: .top, spacing: PP.Space.s4) {
            PageThumbnailStrip(model: model).frame(width: 132)
                .disabled(reading)
            VStack(spacing: PP.Space.s2) {
                HStack {
                    Button { model.showMusic(step: -1) } label: { musicSkipLabel(back: true) }
                        .disabled(model.pageIndex == 0 || model.seekingPage != nil)
                        .help("Previous page with music on it")
                    Button { model.show(page: model.pageIndex - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(model.pageIndex == 0)
                    Text("Page \(model.pageIndex + 1) of \(model.pageCount)").font(.ppCallout).monospacedDigit()
                    if !model.pagesWithPieces.isEmpty {
                        let pages = model.pagesWithPieces.sorted().map { String($0 + 1) }.joined(separator: ", ")
                        Text("Pieces read on page\(model.pagesWithPieces.count == 1 ? "" : "s") \(pages)")
                            .font(.ppCaption).foregroundColor(PP.inkMuted)
                    }
                    Button { model.show(page: model.pageIndex + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(model.pageIndex + 1 >= model.pageCount)
                    Button { model.showMusic(step: 1) } label: { musicSkipLabel(back: false) }
                        .disabled(model.pageIndex + 1 >= model.pageCount || model.seekingPage != nil)
                        .help("Next page with music on it")
                    if let seeking = model.seekingPage {
                        ProgressView().controlSize(.small)
                        Text("Looking at page \(seeking + 1)…").font(.ppCaption).foregroundColor(PP.inkMuted).monospacedDigit()
                    }
                    Spacer()
                    Text(model.documentURL?.lastPathComponent ?? "").font(.ppCaption).foregroundColor(PP.inkMuted)
                    Button("Re-scan page") { model.show(page: model.pageIndex, rescan: true) }
                        .help("Find the lines of music on this page again (the result is saved, so pages open instantly)")
                }
                .disabled(reading)
                ZStack {
                    if let image = model.pageImage, !model.isLoadingPage {
                        GeometryReader { geo in
                            let scale = min(geo.size.width / model.pageSize.width, geo.size.height / model.pageSize.height)
                            let w = model.pageSize.width * scale, h = model.pageSize.height * scale
                            ZStack(alignment: .topLeading) {
                                Image(nsImage: image).resizable().interpolation(.high).frame(width: w, height: h)
                                ForEach(model.systems, id: \.index) { s in
                                    systemOverlay(shown(s), scale: scale)
                                }
                                if !reading, let selection = model.selection {
                                    ForEach(model.systems.filter { selection.contains($0.index) }, id: \.index) { s in
                                        resizeHandles(s, scale: scale)
                                    }
                                    .frame(width: w, height: h, alignment: .topLeading)
                                }
                            }
                            .frame(width: w, height: h)
                            .coordinateSpace(name: "bookPage")
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

    private var reading: Bool { model.phase == .reading }

    private func musicSkipLabel(back: Bool) -> some View {
        HStack(spacing: 1) {
            if back { Image(systemName: "chevron.left.2") }
            Image(systemName: "music.note")
            if !back { Image(systemName: "chevron.right.2") }
        }
    }

    private func systemOverlay(_ s: FoundSystem, scale: CGFloat) -> some View {
        let selected = model.selection?.contains(s.index) ?? false
        // A line already read into a saved piece is tinted by how far that piece has got.
        let saved = model.savedPiece(onLine: s.index)
        let status = saved.map(model.status)
        let tint = status?.color ?? PP.accent
        return RoundedRectangle(cornerRadius: 6)
            .fill(selected ? PP.accent.opacity(0.18) : status != nil ? tint.opacity(0.10) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? PP.accent : status != nil ? tint.opacity(0.7) : PP.accent.opacity(0.35),
                                                               lineWidth: selected ? 2.5 : status != nil ? 1.5 : 1))
            .overlay {
                if let step = model.readingStep(onLine: s.index) {
                    ReadingLineOverlay(step: step)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // The piece's name and status, once per piece (on its first line).
                if !reading, let saved, let status, saved.firstLine == s.index {
                    PieceStatusTag(status: status, text: "\(saved.title) · \(status.label)")
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                Text("\(s.index + 1)")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(PP.onAccent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(selected ? PP.accent : PP.accent.opacity(0.6)))
                    .offset(x: -8, y: -8)
            }
            .frame(width: CGFloat(s.width) * scale, height: CGFloat(s.height) * scale)
            // Hit-test before moving: `.offset` moves the drawing but not the click area, so
            // every line's click area sat at the page's top left and the last line took clicks.
            // A little beyond the outline, so the line's number (which sticks out of its top
            // left corner) is clickable too.
            .contentShape(Rectangle().inset(by: -14))
            .onTapGesture { model.tapSystem(s.index, extend: NSEvent.modifierFlags.contains(.shift)) }
            .help("Click the first line of the piece; Shift-click the last")
            .offset(x: CGFloat(s.left) * scale, y: CGFloat(s.top) * scale)
    }

    /// A line as drawn: with the box being dragged, while it is.
    private func shown(_ s: FoundSystem) -> FoundSystem {
        resizing?.index == s.index ? resizing! : s
    }

    /// Handles on the sides and corners of a selected line's box: drag one to fit the box to the
    /// music (the box is what's cut from the page and read).
    private func resizeHandles(_ s: FoundSystem, scale: CGFloat) -> some View {
        let box = shown(s)
        let rect = CGRect(x: CGFloat(box.left) * scale, y: CGFloat(box.top) * scale,
                          width: CGFloat(box.width) * scale, height: CGFloat(box.height) * scale)
        return ZStack(alignment: .topLeading) {
            ForEach(BoxHandle.allCases, id: \.self) { handle in
                BoxHandleView(handle: handle)
                    .position(handle.point(in: rect))
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("bookPage"))
                            .onChanged { drag in resizing = resized(s, handle, drag.translation, scale) }
                            .onEnded { drag in
                                model.resizeSystem(s.index, to: resized(s, handle, drag.translation, scale))
                                resizing = nil
                            }
                    )
            }
        }
    }

    private func resized(_ s: FoundSystem, _ handle: BoxHandle, _ by: CGSize, _ scale: CGFloat) -> FoundSystem {
        s.moving(handle.edges, dx: Int((by.width / scale).rounded()), dy: Int((by.height / scale).rounded()),
                 pageWidth: Int(model.pageSize.width), pageHeight: Int(model.pageSize.height),
                 minimum: Int(max(24, 4 * s.spacing)))
    }

    /// Asked before reading when the staves don't print a treble clef over a bass clef.
    private var handsQuestion: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            Text("Which hand plays which staff?").font(.ppCallout.weight(.semibold))
            Text("These staves don't show a treble clef above a bass clef, so it isn't clear. A staff with no clef is read as treble.")
                .font(.ppCaption).foregroundColor(PP.inkMuted).fixedSize(horizontal: false, vertical: true)
            Button { model.answerHands(.rightOnly) } label: {
                Label("Both right hand, one line after the other", systemImage: "hand.raised")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { model.answerHands(.split) } label: {
                Label("Right hand on top, left hand below, together", systemImage: "hands.clap")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(PP.Space.s3)
        .background(RoundedRectangle(cornerRadius: PP.Radius.sm).stroke(PP.warning, lineWidth: 1.5))
    }

    /// In place of the Read button while the piece is read: how far it's got, and Cancel.
    private var readingStatus: some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            HStack(spacing: PP.Space.s2) {
                ProgressView().controlSize(.small)
                Text("Reading the piece…").font(.ppCallout.weight(.semibold))
                Spacer()
                Button("Cancel") { model.startOver() }
            }
            ProgressView(value: model.readingProgress)
                .animation(.easeInOut, value: model.readingProgress)
            Text(model.fixing.isEmpty
                 ? "It opens in Practice when it's done. If a bar needs a look, you'll check it first."
                 : "Reading again the bar\(model.fixing.count == 1 ? "" : "s") the first reading skipped…")
                .font(.ppCaption).foregroundColor(PP.inkMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            Text("Pick a piece").font(.ppHeadline)
            Text("Click the first line of music in the piece, then Shift-click its last line.")
                .font(.ppCallout).foregroundColor(PP.inkMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                PieceStatusTag(status: .read)
                PieceStatusTag(status: .learning)
                PieceStatusTag(status: .passed)
            }
            .help("Lines already read are tinted: read into a saved piece, being learned (tutor or Learn), or passed")
            if let s = model.selection {
                Text(s.count == 1 ? "Line \(s.lowerBound + 1) selected" : "Lines \(s.lowerBound + 1)–\(s.upperBound + 1) selected")
                    .font(.ppCallout)
                if !reading {
                    Text("Box missing some notes, or taking in too much? Drag its edges or corners. Re-scan page puts back the boxes found.")
                        .font(.ppCaption).foregroundColor(PP.inkMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            TextField("Name (filled in from the page)", text: $model.title)
                .textFieldStyle(.roundedBorder)
                .disabled(reading)
            if reading {
                readingStatus
            } else {
                if let saved = model.savedForSelection, !model.freshRead {
                    Text("Already read and saved as \(saved.title).").font(.ppCallout).foregroundColor(PP.inkMuted)
                }
                Button(model.savedForSelection != nil && !model.freshRead ? "Open saved piece" : "Read this piece") { model.read() }
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.targetMin))
                    .disabled(!model.canRead)
                if model.asksHands { handsQuestion }
                Toggle("Ask Muse Wonder again", isOn: $model.freshRead)
                    .font(.ppCallout)
                    .help("Lines read before are reused (instant and free). Turn this on to read them again.")
            }
            Text("Muse Wonder reads each line; PerfectPiano measures every note's pitch on the page and flags any bar it isn't sure of.")
                .font(.ppCaption).foregroundColor(PP.inkMuted).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s4)
    }
}

/// A handle on a line's box: a side or a corner.
enum BoxHandle: CaseIterable {
    case top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

    var edges: FoundSystem.Edges {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .left
        case .right: return .right
        case .topLeft: return [.top, .left]
        case .topRight: return [.top, .right]
        case .bottomLeft: return [.bottom, .left]
        case .bottomRight: return [.bottom, .right]
        }
    }

    var isCorner: Bool { edges.rawValue.nonzeroBitCount == 2 }

    func point(in r: CGRect) -> CGPoint {
        let x = edges.contains(.left) ? r.minX : edges.contains(.right) ? r.maxX : r.midX
        let y = edges.contains(.top) ? r.minY : edges.contains(.bottom) ? r.maxY : r.midY
        return CGPoint(x: x, y: y)
    }

    var cursor: NSCursor {
        switch self {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }
}

private struct BoxHandleView: View {
    let handle: BoxHandle

    var body: some View {
        let vertical = handle == .left || handle == .right
        Group {
            if handle.isCorner {
                Circle().fill(Color.white).overlay(Circle().stroke(PP.accent, lineWidth: 2)).frame(width: 11, height: 11)
            } else {
                Capsule().fill(Color.white).overlay(Capsule().stroke(PP.accent, lineWidth: 2))
                    .frame(width: vertical ? 7 : 26, height: vertical ? 26 : 7)
            }
        }
        // A bigger target than the drawing.
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .onHover { inside in inside ? handle.cursor.push() : NSCursor.pop() }
        .help("Drag to resize this line's box")
    }
}

/// Every page of the open book, small, like a PDF reader's sidebar: scroll to the page you
/// want and click it. Pages with a piece read from them carry its status.
struct PageThumbnailStrip: View {
    @ObservedObject var model: BookImportModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: PP.Space.s3) {
                    ForEach(0..<model.pageCount, id: \.self) { index in
                        PageThumbnail(model: model, index: index, current: index == model.pageIndex)
                            .id(index)
                    }
                }
                .padding(.vertical, PP.Space.s2)
            }
            // A fresh strip for each book, starting at the page it opened on.
            .id(model.documentURL)
            .onAppear { proxy.scrollTo(model.pageIndex, anchor: .center) }
            .onChange(of: model.pageIndex) { index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
        .ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s2)
    }
}

private struct PageThumbnail: View {
    @ObservedObject var model: BookImportModel
    let index: Int
    let current: Bool
    @State private var image: NSImage?

    var body: some View {
        Button { model.show(page: index) } label: {
            VStack(spacing: 4) {
                ZStack {
                    Color.white
                    if let image {
                        Image(nsImage: image).resizable().interpolation(.medium).aspectRatio(contentMode: .fit)
                    }
                }
                .aspectRatio(image.map { $0.size.width / max(1, $0.size.height) } ?? 0.75, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(current ? PP.accent : Color.black.opacity(0.15), lineWidth: current ? 3 : 1))
                .overlay(alignment: .topTrailing) {
                    if let status = model.status(ofPage: index) {
                        Image(systemName: status.icon)
                            .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                            .padding(4).background(Circle().fill(status.color))
                            .padding(4)
                            .help("A piece read from this page: \(status.label.lowercased())")
                    }
                }
                Text("\(index + 1)")
                    .font(.ppCaption.monospacedDigit())
                    .foregroundColor(current ? PP.accent : PP.inkMuted)
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Page \(index + 1)")
        .task(id: index) { image = model.thumbnail(ofPage: index) }
    }
}

// MARK: - Reading

/// Over a line of the page while it's read: a sweep of light, and how far it has got.
private struct ReadingLineOverlay: View {
    let step: BookImportModel.Step
    @State private var sweep = false

    var body: some View {
        let done = step == .done
        let failed: Bool = { if case .failed = step { return true } else { return false } }()
        let tint = failed ? PP.warning : done ? PP.success : PP.accent
        RoundedRectangle(cornerRadius: 6)
            .fill(tint.opacity(0.12))
            .overlay {
                if !done && !failed {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, PP.accent.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: sweep ? geo.size.width : -geo.size.width * 0.3)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onAppear {
                        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { sweep = true }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 4) {
                    if done {
                        Image(systemName: "checkmark.circle.fill")
                    } else if failed {
                        Image(systemName: "exclamationmark.triangle.fill")
                    } else {
                        ProgressView().controlSize(.mini)
                    }
                    Text(done ? "Read" : failed ? "Couldn't read it" : step.label)
                }
                .font(.ppCaption.weight(.semibold))
                .foregroundColor(done || failed ? PP.onAccent : PP.ink)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(done || failed ? tint : PP.surface))
                .padding(4)
            }
            .allowsHitTesting(false)
            .animation(.easeInOut, value: done)
    }
}

// MARK: - Review

struct ReviewView: View {
    @ObservedObject var model: BookImportModel
    @State private var selected: Int?
    /// How far the lines from the page are zoomed in: 1 fits the line to the width (no taller
    /// than `pageMaxHeight`).
    @State private var zoom: CGFloat = 1
    /// The width a line from the page has to fit in.
    @State private var pageWidth: CGFloat = 600

    /// The tallest the line from the page is drawn, unzoomed.
    static let pageMaxHeight: CGFloat = 220
    static let zoomSteps: [CGFloat] = [0.5, 0.75, 1, 1.5, 2, 3, 4]

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            HStack(spacing: PP.Space.s3) {
                Text("Check “\(model.title)”").font(.ppHeadline)
                Text(model.toReview == 0 ? "All bars checked" : "\(model.toReview) bar\(model.toReview == 1 ? "" : "s") to check")
                    .font(.ppCallout).foregroundColor(model.toReview == 0 ? PP.success : PP.warning)
                Spacer()
                zoomButtons
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
            .background(GeometryReader { geo in
                Color.clear.preference(key: PageWidthKey.self, value: geo.size.width)
            })
            .onPreferenceChange(PageWidthKey.self) { width in
                // Less the line's own padding (`ppGlass`, s3 each side).
                pageWidth = max(100, width - 2 * PP.Space.s3)
            }
        }
    }

    private var zoomButtons: some View {
        HStack(spacing: 2) {
            Button { zoom = Self.zoomSteps.last { $0 < zoom } ?? zoom } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(zoom <= Self.zoomSteps.first!)
                .help("Zoom out of the page")
            Button { zoom = 1 } label: { Text("\(Int((zoom * 100).rounded()))%").monospacedDigit().frame(minWidth: 40) }
                .help("Fit the page to the width")
            Button { zoom = Self.zoomSteps.first { $0 > zoom } ?? zoom } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(zoom >= Self.zoomSteps.last!)
                .help("Zoom in on the page")
        }
    }

    @ViewBuilder
    private func systemSection(_ r: BookImportModel.SystemRead) -> some View {
        VStack(alignment: .leading, spacing: PP.Space.s2) {
            Text("Line \(r.id + 1)").font(.ppEyebrow).foregroundColor(PP.inkMuted)
            // The page, with each bar marked: amber to check, green checked.
            // Fitted to the width but capped in height, so a tall crop (a worksheet, a line with
            // text around it) doesn't push the engraving and the bars to check off the screen;
            // then zoomed, scrolling sideways when it's wider than the window.
            let fit = min(pageWidth / CGFloat(max(1, r.gray.width)), Self.pageMaxHeight / CGFloat(max(1, r.gray.height)))
            let scale = max(0.01, fit * zoom)
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: r.image).resizable().interpolation(.high)
                        .frame(width: CGFloat(r.gray.width) * scale, height: CGFloat(r.gray.height) * scale)
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
            .frame(height: CGFloat(r.gray.height) * scale)

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

private struct PageWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
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
                    .frame(maxWidth: 180, maxHeight: 120).background(Color.white)
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
