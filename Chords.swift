import UIKit

// MARK: - Akkord-logika (a Python változat NS / NF / ALT / transpose / build_line része)

enum Chords {
    static let sharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flat  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    static let alt   = ["Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#", "H": "B"]

    private static let regex = try! NSRegularExpression(
        pattern: #"^([A-GH][#b]?)([^/]*)(?:/([A-GH][#b]?))?$"#
    )

    private static func semi(_ note: String) -> Int? {
        sharp.firstIndex(of: alt[note] ?? note)
    }

    static func transpose(_ chord: String, _ k: Int, _ useFlat: Bool) -> String {
        let ns = chord as NSString
        guard let m = regex.firstMatch(in: chord, range: NSRange(location: 0, length: ns.length)) else {
            return chord
        }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        guard let root = group(1), let rootSemi = semi(root) else { return chord }
        let names = useFlat ? flat : sharp
        var out = names[(((rootSemi + k) % 12) + 12) % 12] + (group(2) ?? "")
        if let bass = group(3) {
            guard let bassSemi = semi(bass) else { return chord }
            out += "/" + names[(((bassSemi + k) % 12) + 12) % 12]
        }
        return out
    }

    private static func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
    }

    /// Egy "[G]szöveg [C]szöveg" sorból akkordsort és szövegsort készít.
    static func buildLine(_ line: String, _ k: Int, _ useFlat: Bool) -> (chords: String, lyrics: String) {
        var chords = ""
        var lyrics = ""
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if chars[i] == "[",
               let j = chars[(i + 1)...].firstIndex(of: "]"),
               j > i + 1 {
                let chord = String(chars[(i + 1)..<j])
                if !chords.isEmpty && chords.count >= lyrics.count {
                    lyrics = pad(lyrics, chords.count + 1)
                }
                chords = pad(chords, lyrics.count) + transpose(chord, k, useFlat)
                i = j + 1
            } else {
                lyrics.append(chars[i])
                i += 1
            }
        }
        return (chords, lyrics)
    }
}

// MARK: - Megjelenítés (NSAttributedString, monospace)

enum Renderer {
    static let chordColor = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.55, blue: 0.62, alpha: 1)
            : UIColor(red: 0x8a / 255, green: 0x2c / 255, blue: 0x3b / 255, alpha: 1)
    }
    static let sectionColor = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.74, blue: 0.72, alpha: 1)
            : UIColor(red: 0x5b / 255, green: 0x6e / 255, blue: 0x6c / 255, alpha: 1)
    }

    static func attributed(song: Song, shift: Int, flat: Bool, size: CGFloat) -> NSAttributedString {
        let regular = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = UIFont.monospacedSystemFont(ofSize: size, weight: .bold)

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byClipping
        let titlePara = NSMutableParagraphStyle()
        titlePara.lineBreakMode = .byClipping
        titlePara.paragraphSpacing = 6

        func attrs(_ font: UIFont, _ color: UIColor, _ p: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: color, .paragraphStyle: p]
        }

        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: song.title + "\n\n", attributes: attrs(bold, .label, titlePara)))

        guard song.kind == .text else { return out }

        let text = song.text.replacingOccurrences(of: "\r\n", with: "\n")
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("#") {
                let stripped = String(line.drop(while: { $0 == "#" || $0 == " " }))
                out.append(NSAttributedString(string: stripped + "\n", attributes: attrs(regular, sectionColor, para)))
            } else if line.contains("[") {
                let (chords, lyrics) = Chords.buildLine(line, shift, flat)
                out.append(NSAttributedString(string: chords + "\n", attributes: attrs(bold, chordColor, para)))
                out.append(NSAttributedString(string: lyrics + "\n", attributes: attrs(regular, .label, para)))
            } else {
                out.append(NSAttributedString(string: line + "\n", attributes: attrs(regular, .label, para)))
            }
        }
        return out
    }
}
