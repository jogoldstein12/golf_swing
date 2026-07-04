// Custom glyphs drawn as paths — deliberately not SF Symbols. Every mark in the app
// comes from this small set so the line weight and voice stay consistent.
import SwiftUI

struct CheckGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.08, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.minY + r.height * 0.85))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.95, y: r.minY + r.height * 0.12))
        return p
    }
}

struct CrossGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        return p
    }
}

struct PlayGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.12, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct PauseGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width * 0.3
        p.addRoundedRect(in: CGRect(x: r.minX + r.width * 0.08, y: r.minY, width: w, height: r.height),
                         cornerSize: CGSize(width: w * 0.35, height: w * 0.35))
        p.addRoundedRect(in: CGRect(x: r.maxX - r.width * 0.08 - w, y: r.minY, width: w, height: r.height),
                         cornerSize: CGSize(width: w * 0.35, height: w * 0.35))
        return p
    }
}

/// Exclamation stroke for fault markers.
struct BangGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.62))
        p.move(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.02))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}
