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
            HStack {
                TextField("Search title or composer", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search music")
                Picker("Composer", selection: $model.composer) {
                    Text("All composers").tag(nil as String?)
                    ForEach(model.composers, id: \.self) { Text($0).tag(Optional($0)) }
                }.frame(maxWidth: 250)
                Picker("Difficulty", selection: $model.difficulty) {
                    Text("All levels").tag(nil as CatalogPiece.Difficulty?)
                    ForEach(CatalogPiece.Difficulty.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }.frame(maxWidth: 200)
                Toggle("Downloaded", isOn: $model.downloadedOnly).toggleStyle(.checkbox)
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

    private var musicTable: some View {
        Table(model.filtered, selection: Binding(get: { model.selected?.id }, set: { model.selectedID = $0 })) {
            TableColumn("Piece") { piece in
                HStack(spacing: 6) {
                    Text(piece.title).lineLimit(1).help(piece.title)
                    if model.downloaded.contains(piece.id) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(PP.success)
                            .accessibilityLabel("Available offline")
                    }
                }
            }.width(min: 200, ideal: 310, max: .infinity)
            TableColumn("Composer", value: \.composer)
                .width(min: 140, ideal: 190, max: 250)
            TableColumn("Difficulty") { piece in
                Text(piece.difficulty.rawValue)
            }.width(110)
            TableColumn("Key signature") { piece in
                Text(piece.keySignatureDescription ?? "—")
                    .foregroundColor(piece.keySignature == nil ? PP.inkMuted : PP.ink)
                    .help(piece.keySignature == nil ? "No key signature is supplied by this MIDI edition." : "Opening signature from the reviewed MIDI edition.")
            }.width(min: 125, ideal: 145, max: 170)
            TableColumn("Preview") { piece in
                let active = model.previewingID == piece.id
                Button {
                    model.preview(piece, play: { url, finished in
                        session.previewCatalogPiece(url, onFinish: finished)
                    }, stop: { session.preview.stop() })
                } label: {
                    Label(active ? "Stop" : "Preview", systemImage: active ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PPGlassButtonStyle(height: 24))
                .accessibilityLabel("\(active ? "Stop preview of" : "Preview") \(piece.title)")
            }.width(95)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
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
#endif
