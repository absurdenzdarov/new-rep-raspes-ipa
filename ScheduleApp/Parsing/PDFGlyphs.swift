import Foundation
import PDFKit

struct Glyph {
    var ch: Character
    var cx: Double
    var cy: Double
    var w: Double
    var h: Double
}

enum PDFGlyphs {
    /// Все символы страницы с координатами. Таблица может быть нарисована повёрнутой
    /// (альбомная страница на портретном листе) — ориентацию определяем по направлению
    /// текста и приводим к обычной: слева направо, ось Y — вверх.
    static func glyphs(of page: PDFPage) -> [Glyph] {
        guard let str = page.string else { return [] }
        let ns = str as NSString
        let n = ns.length
        let box = page.bounds(for: .mediaBox)

        var raw: [(Character, Double, Double, Double, Double)] = []
        raw.reserveCapacity(n)
        for i in 0..<n {
            guard let scalar = Unicode.Scalar(ns.character(at: i)) else { continue }
            let c = Character(scalar)
            if c.isWhitespace || c.isNewline { continue }
            let r = page.characterBounds(at: i)
            if !(r.width > 0) || !(r.height > 0) || !r.width.isFinite || !r.height.isFinite { continue }
            let cx = Double(r.midX - box.minX)
            let cy = Double(r.midY - box.minY)
            raw.append((c, cx, cy, Double(r.width), Double(r.height)))
        }
        if raw.count < 2 { return [] }

        // Направление чтения
        var sx = 0.0
        var sy = 0.0
        for i in 1..<raw.count {
            let a = raw[i - 1]
            let b = raw[i]
            let dx = b.1 - a.1
            let dy = b.2 - a.2
            let lim = 3.0 * max(a.3, a.4, b.3, b.4)
            if abs(dx) < lim && abs(dy) < lim {
                sx += dx
                sy += dy
            }
        }

        let W = Double(box.width)
        let H = Double(box.height)
        var out: [Glyph] = []
        out.reserveCapacity(raw.count)

        enum Turn { case none, cw90, ccw90, flip }
        var turn: Turn = .none
        if abs(sy) > abs(sx) * 1.5 {
            turn = sy > 0 ? .cw90 : .ccw90
        } else if sx < 0 && abs(sx) > abs(sy) * 1.5 {
            turn = .flip
        }

        for g in raw {
            switch turn {
            case .none:
                out.append(Glyph(ch: g.0, cx: g.1, cy: g.2, w: g.3, h: g.4))
            case .cw90:
                out.append(Glyph(ch: g.0, cx: g.2, cy: W - g.1, w: g.4, h: g.3))
            case .ccw90:
                out.append(Glyph(ch: g.0, cx: H - g.2, cy: g.1, w: g.4, h: g.3))
            case .flip:
                out.append(Glyph(ch: g.0, cx: W - g.1, cy: H - g.2, w: g.3, h: g.4))
            }
        }
        return out
    }
}
