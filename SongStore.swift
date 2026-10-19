import UIKit

// MARK: - Modell

struct Song: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case text, image }

    var id = UUID()
    var title: String
    var text: String = ""
    var kind: Kind = .text
    /// Fájlnév a Dokumentumok mappában (képeknél a kép, beolvasott TXT-nél a forrásfájl)
    var file: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, text, file
        case kind = "type"          // kompatibilis a Python songs.json-nal
    }
}

extension Song {
    // Elnéző dekódolás: a régi songs.json-ban nincs "id"
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .text
        file = try? c.decodeIfPresent(String.self, forKey: .file)
    }
}

// MARK: - Tároló

final class SongStore: ObservableObject {
    @Published var songs: [Song] = []

    static var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var jsonURL: URL { Self.docs.appendingPathComponent("songs.json") }
    private let imageCache = NSCache<NSString, UIImage>()
    private let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp"]

    static let sample = Song(
        title: "Amazing Grace (közkincs)",
        text: "# 1. vers\n"
            + "[G]Amazing grace, how [C]sweet the [G]sound\n"
            + "That saved a [Em]wretch like [D]me\n"
            + "I [G]once was lost, but [C]now am [G]found\n"
            + "Was [Em]blind but [D]now I [G]see\n"
    )

    init() { load() }

    // MARK: betöltés / mentés

    func load() {
        var list: [Song] = []
        let fm = FileManager.default

        // 1. songs.json
        if let data = try? Data(contentsOf: jsonURL),
           let decoded = try? JSONDecoder().decode([Song].self, from: data) {
            list = decoded.filter { song in
                if song.kind == .text { return true }
                guard let f = song.file else { return false }
                return fm.fileExists(atPath: Self.docs.appendingPathComponent(f).path)
            }
        }

        // 2. TXT és képfájlok a Dokumentumok mappából (természetes sorrendben)
        let files = ((try? fm.contentsOfDirectory(at: Self.docs, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        func title(of url: URL) -> String {
            url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        }

        for url in files where url.pathExtension.lowercased() == "txt" {
            let t = title(of: url)
            if !list.contains(where: { $0.title.lowercased() == t.lowercased() }),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                list.append(Song(title: t, text: content, kind: .text, file: url.lastPathComponent))
            }
        }
        for url in files where imageExts.contains(url.pathExtension.lowercased()) {
            let t = title(of: url)
            if !list.contains(where: { $0.title.lowercased() == t.lowercased() }) {
                list.append(Song(title: t, kind: .image, file: url.lastPathComponent))
            }
        }

        if list.isEmpty { list = [Self.sample] }
        songs = list
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? enc.encode(songs) {
            try? data.write(to: jsonURL, options: .atomic)
        }
    }

    // MARK: műveletek

    func image(for song: Song) -> UIImage? {
        guard song.kind == .image, let f = song.file else { return nil }
        if let cached = imageCache.object(forKey: f as NSString) { return cached }
        guard let img = UIImage(contentsOfFile: Self.docs.appendingPathComponent(f).path) else { return nil }
        imageCache.setObject(img, forKey: f as NSString)
        return img
    }

    func update(id: UUID, title: String, text: String) {
        guard let i = songs.firstIndex(where: { $0.id == id }) else { return }
        songs[i].title = title
        songs[i].text = text
        save()
    }

    func add(_ song: Song) {
        songs.append(song)
        save()
    }

    func delete(_ song: Song) {
        if let f = song.file {
            // különben a következő indításkor újra megtalálná a mappában
            try? FileManager.default.removeItem(at: Self.docs.appendingPathComponent(f))
        }
        songs.removeAll { $0.id == song.id }
        if songs.isEmpty { songs = [Self.sample] }
        save()
    }

    /// Fájlok importálása (fileImporter). Visszaadja az utoljára hozzáadott dalt és a hibákat.
    func importFiles(_ urls: [URL]) -> (last: Song?, errors: [String]) {
        var last: Song?
        var errors: [String] = []
        let fm = FileManager.default

        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            let ext = url.pathExtension.lowercased()
            let title = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
            do {
                if ext == "json" {
                    let data = try Data(contentsOf: url)
                    let decoded = try JSONDecoder().decode([Song].self, from: data)
                    // csak a szöveges dalok jönnek át (a képek útvonala az asztali gépre mutat)
                    for var s in decoded where s.kind == .text {
                        s.id = UUID()
                        s.file = nil
                        if !songs.contains(where: { $0.title.lowercased() == s.title.lowercased() }) {
                            songs.append(s)
                            last = s
                        }
                    }
                } else if ext == "txt" {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let s = Song(title: title, text: content, kind: .text)
                    songs.append(s)
                    last = s
                } else if imageExts.contains(ext) {
                    let dest = uniqueURL(for: url.lastPathComponent)
                    try fm.copyItem(at: url, to: dest)
                    let s = Song(title: title, kind: .image, file: dest.lastPathComponent)
                    songs.append(s)
                    last = s
                } else {
                    errors.append("\(url.lastPathComponent): nem támogatott fájlformátum")
                }
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        save()
        return (last, errors)
    }

    private func uniqueURL(for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = Self.docs.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = Self.docs.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }
}
