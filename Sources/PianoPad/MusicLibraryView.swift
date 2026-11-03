#if os(macOS)
import PianoCatalog
import SwiftUI

@MainActor
struct MusicLibraryView: View {
    @ObservedObject var model: MusicLibraryModel
    @EnvironmentObject var session: PlaySession

    var body: some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Music Library").font(.ppTitle)
                Spacer()
                Text("\(model.filtered.count) piano pieces · Mutopia Project")
                    .font(.ppCaption).foregroundColor(PP.inkMuted)
            }
            HStack(spacing: PP.Space.s2) {
                LibrarySearchField(text: $model.query)
                composerMenu
                ForEach([nil] + CatalogPiece.Difficulty.allCases.map(Optional.some), id: \.self) { level in
                    Toggle(level?.rawValue ?? "All levels", isOn: Binding(
                        get: { model.difficulty == level },
                        set: { if $0 { model.difficulty = level } }
                    ))
                    .toggleStyle(PPChipToggleStyle())
                    .fixedSize()
                }
                Toggle(isOn: $model.downloadedOnly) {
                    Label("Downloaded", systemImage: "arrow.down.circle")
                }
                .toggleStyle(PPChipToggleStyle())
                .fixedSize()
            }
            .tourAnchor(.catalogFilters)
            if model.downloadingID != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let progress = model.progress { ProgressView(value: progress) }
                    else { ProgressView().controlSize(.small) }
                    HStack {
                        Text("Preparing music…").font(.ppCaption)
                        Spacer()
                        Button("Cancel") { model.cancel() }
                    }
                }
            } else if let id = model.previewingID, let piece = model.pieces.first(where: { $0.id == id }) {
                HStack {
                    Label("Previewing \(piece.title)", systemImage: "speaker.wave.2.fill")
                        .font(.ppCallout).lineLimit(1)
                    Spacer()
                    Button("Stop preview") { model.cancel() }
                }.foregroundColor(PP.accent)
            }
            musicTable
                .frame(minHeight: 260, maxHeight: .infinity)
                .tourAnchor(.catalogPieces)
            if let piece = model.selected {
                detail(piece).tourAnchor(.catalogDetails)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.ppCallout).foregroundColor(PP.warning)
                    .accessibilityLabel("Music library error: \(error)")
            }
            Text("Difficulty is editorial guidance. Key signatures show the opening signature when available. Practice scores are generated from MIDI; original markings are in the PDF.")
                .font(.ppCaption).foregroundColor(PP.inkMuted)
        }
        .padding(PP.Space.s4)
        .task { await model.refreshDownloads() }
        .onDisappear { model.cancel() }
    }

    private var composerMenu: some View {
        Menu {
            Picker("Composer", selection: $model.composer) {
                Text("All composers").tag(nil as String?)
                ForEach(model.composers, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: PP.Space.s1) {
                Image(systemName: "person.fill")
                Text(model.composer ?? "All composers").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(model.composer == nil ? PP.ink : PP.accent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Composer: \(model.composer ?? "All composers")")
        }
        .menuStyle(.button)
        .buttonStyle(PPGlassButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// The pieces as glass rows under a quiet header; click a row to see its details.
    private var musicTable: some View {
        VStack(spacing: 0) {
            LibraryRowLayout(piece: Text("Piece"), composer: Text("Composer"), level: Text("Level"),
                             key: Text("Key signature"), action: Text("Preview"))
            .font(.ppEyebrow).tracking(0.8).textCase(.uppercase).foregroundColor(PP.inkMuted)
            .padding(.horizontal, PP.Space.s4).padding(.vertical, PP.Space.s2)
            Rectangle().fill(PP.inkStaff.opacity(0.35)).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filtered) { piece in
                            row(piece).id(piece.id)
                        }
                    }
                    .padding(PP.Space.s2)
                }
                .onChange(of: model.selectedID) { id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
        }
        .ppGlass(cornerRadius: PP.Radius.lg, padding: 0)
        .modifier(ArrowKeySelection(step: step))
        .overlay {
            if model.filtered.isEmpty {
                VStack(spacing: 8) {
                    Text("No matching music").font(.ppHeadline)
                    Text(model.downloadedOnly ? "Download a piece to learn it offline, or adjust your filters." : "Try another title, composer or level.")
                        .foregroundColor(PP.inkMuted)
                }.allowsHitTesting(false)
            }
        }
    }

    private func step(_ by: Int) {
        let pieces = model.filtered
        guard !pieces.isEmpty else { return }
        let current = pieces.firstIndex { $0.id == model.selected?.id } ?? 0
        model.selectedID = pieces[min(max(current + by, 0), pieces.count - 1)].id
    }

    private func row(_ piece: CatalogPiece) -> some View {
        let active = model.previewingID == piece.id
        return PPSelectableRow(selected: model.selected?.id == piece.id, select: { model.selectedID = piece.id }) {
            LibraryRowLayout(piece: HStack(spacing: 6) {
                    Text(piece.title).font(.ppCallout).foregroundColor(PP.ink).lineLimit(1).help(piece.title)
                    if model.downloaded.contains(piece.id) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(PP.success)
                            .accessibilityLabel("Available offline")
                    }
                },
                composer: Text(piece.composer).lineLimit(1),
                level: LevelBadge(level: piece.difficulty),
                key: Text(piece.keySignatureDescription ?? "—")
                    .foregroundColor(piece.keySignature == nil ? PP.inkMuted : PP.ink)
                    .help(piece.keySignature == nil ? "No key signature is supplied by this MIDI edition." : "Opening signature from the reviewed MIDI edition."),
                action: Button {
                    model.preview(piece, play: { url, finished in
                        session.previewCatalogPiece(url, onFinish: finished)
                    }, stop: { session.preview.stop() })
                } label: {
                    Label(active ? "Stop" : "Preview", systemImage: active ? "stop.fill" : "play.fill")
                        .foregroundColor(active ? PP.accent : PP.ink)
                }
                .buttonStyle(PPGlassButtonStyle(height: 26))
                .accessibilityLabel("\(active ? "Stop preview of" : "Preview") \(piece.title)"))
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(PP.inkMuted)
        }
    }

    private func detail(_ piece: CatalogPiece) -> some View {
        HStack(alignment: .top, spacing: PP.Space.s4) {
            VStack(alignment: .leading, spacing: 6) {
                Text(piece.title).font(.ppHeadline).lineLimit(2).help(piece.title)
                Text(piece.composer).font(.ppCallout).foregroundColor(PP.inkMuted)
                Text("\(piece.difficulty.rawValue) · Solo piano").font(.ppCaption)
                if model.downloaded.contains(piece.id) {
                    Label("Available offline", systemImage: "checkmark.circle.fill")
                        .font(.ppCaption).foregroundColor(PP.success)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("Edition and credits").font(.ppHeadline)
                Text(piece.attribution).font(.ppCaption).lineLimit(4).help(piece.attribution)
                HStack {
                    Link(piece.license, destination: piece.licenseURL)
                    Link("Mutopia edition", destination: piece.sourceURL)
                }
                HStack {
                    Link("PDF score", destination: piece.pdfURL)
                    Link("LilyPond source", destination: piece.lilypondURL)
                }
            }
            .font(.ppCaption)
            // Credits stay text links, not pills.
            .buttonStyle(.link)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                Button {
                    model.open(piece) { session.openCatalogPiece($0, piece: piece, tutored: true) }
                } label: { Label("Start learning", systemImage: "graduationcap.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(PPPrimaryButtonStyle(height: PP.Size.compact))
                    .disabled(model.downloadingID != nil)
                Button {
                    model.open(piece) { session.openCatalogPiece($0, piece: piece, tutored: false) }
                } label: { Label("Practise freely", systemImage: "pianokeys").frame(maxWidth: .infinity) }
                    .disabled(model.downloadingID != nil)
            }.frame(width: 180)
        }.ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s3)
    }
}
/// The library's columns: the title takes the slack, the rest are fixed.
private struct LibraryRowLayout<Piece: View, Composer: View, Level: View, Key: View, Action: View>: View {
    let piece: Piece, composer: Composer, level: Level, key: Key, action: Action

    var body: some View {
        HStack(spacing: PP.Space.s3) {
            piece.frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            composer.frame(width: 200, alignment: .leading)
            level.frame(width: 120, alignment: .leading)
            key.frame(width: 150, alignment: .leading)
            action.frame(width: 96, alignment: .trailing)
        }
    }
}

/// Up and down arrows move the selection, as they did in the table (macOS 14 and later).
private struct ArrowKeySelection: ViewModifier {
    let step: (Int) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .focusable()
                .focusEffectDisabled()
                .onKeyPress(.upArrow) { step(-1); return .handled }
                .onKeyPress(.downArrow) { step(1); return .handled }
        } else {
            content
        }
    }
}

/// Elementary, Intermediate or Advanced, on the backdrop's mint, lilac or apricot.
private struct LevelBadge: View {
    let level: CatalogPiece.Difficulty

    var body: some View {
        let tint: Color = switch level {
        case .elementary: PP.mint
        case .intermediate: PP.lilac
        case .advanced: PP.apricot
        }
        Text(level.rawValue)
            .font(.ppCaption)
            .foregroundColor(PP.ink)
            .padding(.horizontal, PP.Space.s2)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.45)))
            .overlay(Capsule().strokeBorder(tint, lineWidth: 1))
    }
}

/// A glass capsule search field with a clear button.
private struct LibrarySearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: PP.Space.s2) {
            Image(systemName: "magnifyingglass").foregroundColor(PP.inkMuted)
            TextField("Search title or composer", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($focused)
                .accessibilityLabel("Search music")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundColor(PP.inkMuted)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, PP.Space.s3)
        .frame(height: PP.Size.compact)
        .background(Capsule().fill(PP.surfaceGlass))
        .overlay(Capsule().strokeBorder(focused ? PP.focusRing : PP.inkStaff.opacity(0.45), lineWidth: focused ? 2 : 1))
        .frame(minWidth: 200, maxWidth: .infinity)
    }
}
#endif
