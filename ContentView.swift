import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = SongStore()

    @State private var selectedID: UUID?
    @State private var shift = 0
    @State private var useFlat = false
    @State private var fontSize: CGFloat = 16
    @State private var scrolling = false
    @State private var speed = 3.0

    @State private var editing = false
    @State private var draftTitle = ""
    @State private var draftText = ""

    @State private var showImporter = false
    @State private var showDelete = false
    @State private var errorMessage: String?

    private var song: Song? { store.songs.first { $0.id == selectedID } }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.plainText, .png, .jpeg, .webP],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert("Hiba", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: selectedID) { _ in
            shift = 0
            scrolling = false
        }
        .onChange(of: scrolling) { on in
            // görgetés közben ne aludjon el a kijelző
            UIApplication.shared.isIdleTimerDisabled = on
        }
    }

    // MARK: dallista

    private var sidebar: some View {
        List(store.songs, selection: $selectedID) { s in
            Label(
                s.title.isEmpty ? "Névtelen dal" : s.title,
                systemImage: s.kind == .image ? "photo" : "music.note"
            )
        }
        .disabled(editing)
        .navigationTitle("Akkordkönyv")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showImporter = true } label: { Image(systemName: "folder") }
                Button { newSong() } label: { Image(systemName: "plus") }
            }
        }
    }

    // MARK: részletek

    @ViewBuilder
    private var detail: some View {
        if let song {
            Group {
                if editing {
                    editor
                } else {
                    SongView(
                        content: Renderer.attributed(song: song, shift: shift, flat: useFlat, size: fontSize),
                        image: store.image(for: song),
                        songID: song.id,
                        scrolling: scrolling,
                        speed: speed,
                        onEnd: { scrolling = false }
                    )
                }
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if song.kind == .text {
                        Button(editing ? "Mentés" : "Szerkesztés") { toggleEdit(song) }
                    }
                    Button(role: .destructive) { showDelete = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !editing { controls(for: song) }
            }
            .confirmationDialog("Biztosan törlöd ezt a dalt?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Törlés", role: .destructive) { deleteCurrent() }
            }
        } else {
            Text("Válassz egy dalt")
                .foregroundStyle(.secondary)
        }
    }

    private var editor: some View {
        VStack(spacing: 8) {
            TextField("Cím", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $draftText)
                .font(.system(size: 16, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
        }
        .padding()
    }

    // MARK: vezérlők

    private func controls(for song: Song) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                if song.kind == .text {
                    Button { step(-1) } label: { Image(systemName: "minus") }
                    Text(shift == 0 ? "0" : String(format: "%+d", shift))
                        .monospacedDigit()
                        .frame(minWidth: 32)
                    Button { step(1) } label: { Image(systemName: "plus") }
                    Button(useFlat ? "♭" : "♯") { useFlat.toggle() }
                }
                Spacer()
                Button { fontSize = max(10, fontSize - 2) } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                Button { fontSize = min(40, fontSize + 2) } label: {
                    Image(systemName: "textformat.size.larger")
                }
            }
            HStack(spacing: 12) {
                Button { scrolling.toggle() } label: {
                    Label(scrolling ? "Megállít" : "Görgetés",
                          systemImage: scrolling ? "pause.fill" : "play.fill")
                }
                Text("Sebesség").font(.footnote).foregroundStyle(.secondary)
                Slider(value: $speed, in: 1...10)
            }
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: műveletek

    private func step(_ k: Int) {
        shift = ((shift + k + 5) % 12 + 12) % 12 - 5
    }

    private func newSong() {
        guard !editing else { return }
        let s = Song(title: "Új dal", text: "[C]Szöveg [G]akkordokkal\n")
        store.add(s)
        selectedID = s.id
        DispatchQueue.main.async { startEditing(s) }
    }

    private func startEditing(_ s: Song) {
        scrolling = false
        draftTitle = s.title
        draftText = s.text
        editing = true
    }

    private func toggleEdit(_ s: Song) {
        if editing {
            store.update(id: s.id, title: draftTitle.trimmingCharacters(in: .whitespaces), text: draftText)
            editing = false
        } else {
            startEditing(s)
        }
    }

    private func deleteCurrent() {
        guard let s = song else { return }
        scrolling = false
        editing = false
        store.delete(s)
        selectedID = nil
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard !editing else { return }
        switch result {
        case .success(let urls):
            let (last, errors) = store.importFiles(urls)
            if let last {
                selectedID = last.id
                shift = 0
            }
            if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
