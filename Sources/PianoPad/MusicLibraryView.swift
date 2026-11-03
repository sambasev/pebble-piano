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
            }
            HStack(alignment: .top, spacing: PP.Space.s4) {
                List(selection: Binding(get: { model.selected?.id }, set: { model.selectedID = $0 })) {
                    ForEach(model.filtered) { piece in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(piece.title).font(.ppHeadline)
                                Text("\(piece.composer) · \(piece.difficulty.rawValue)")
                                    .font(.ppCaption).foregroundColor(PP.inkMuted)
                            }
                            Spacer()
                            if model.downloaded.contains(piece.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(PP.success)
                                    .accessibilityLabel("Available offline")
                            }
                            preview(piece, size: 26)
                        }
                        .padding(.vertical, 6)
                        .tag(piece.id)
                    }
                }
                .listStyle(.inset)
                .tourAnchor(.catalogPieces)
                .frame(minWidth: 320, maxWidth: .infinity)
                if let piece = model.selected {
                    ScrollView { detail(piece).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(minWidth: 320, maxWidth: 420)
                        .tourAnchor(.catalogDetails)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No matching music").font(.ppHeadline)
                        Text(model.downloadedOnly ? "Download a piece to learn it offline, or adjust your filters." : "Try another title, composer or level.")
                            .foregroundColor(PP.inkMuted)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.ppCallout).foregroundColor(PP.warning)
                    .accessibilityLabel("Music library error: \(error)")
            }
            Text("Difficulty is editorial guidance. Practice scores are generated from MIDI; the original PDF includes the publisher’s notation and markings.")
                .font(.ppCaption).foregroundColor(PP.inkMuted)
        }
        .padding(PP.Space.s4)
        .task { await model.refreshDownloads() }
        .onDisappear { model.cancel() }
    }

    /// Hear it before choosing: the MIDI downloads first if it isn't here yet.
    private func preview(_ piece: CatalogPiece, size: CGFloat) -> some View {
        PreviewButton(id: "catalog:" + piece.id, title: piece.title, size: size) {
            await model.previewFile(piece).map { ($0, nil) }
        }
    }

    private func detail(_ piece: CatalogPiece) -> some View {
        VStack(alignment: .leading, spacing: PP.Space.s3) {
            Image(systemName: "music.note.list").font(.system(size: 34)).foregroundColor(PP.accent)
                .accessibilityHidden(true)
            Text(piece.title).font(.ppTitle)
            Text(piece.composer).font(.ppHeadline).foregroundColor(PP.inkMuted)
            HStack(spacing: PP.Space.s2) {
                preview(piece, size: PP.Size.compact)
                Text("\(piece.difficulty.rawValue) · Solo piano").font(.ppCallout)
            }
            if model.downloaded.contains(piece.id) {
                Label("Available offline", systemImage: "checkmark.circle.fill").foregroundColor(PP.success)
            }
            Button {
                model.open(piece) { session.openCatalogPiece($0, piece: piece, tutored: true) }
            } label: { Label("Start learning", systemImage: "graduationcap.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .disabled(model.downloadingID != nil)
            Button {
                model.open(piece) { session.openCatalogPiece($0, piece: piece, tutored: false) }
            } label: { Label("Practise freely", systemImage: "pianokeys").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                .disabled(model.downloadingID != nil)
            Divider()
            Text("Edition and credits").font(.ppHeadline)
            Text(piece.attribution).font(.ppCallout)
            Link(piece.license, destination: piece.licenseURL)
            Link("Original Mutopia edition", destination: piece.sourceURL)
            HStack {
                Link("PDF score", destination: piece.pdfURL)
                Link("LilyPond source", destination: piece.lilypondURL)
            }
        }.ppGlass(cornerRadius: PP.Radius.lg, padding: PP.Space.s4)
    }
}
#endif
