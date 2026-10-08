import CoreGraphics
import Foundation

/// SVG path-data parser → CGPath. Streaming reader (not a naive tokenizer) so it
/// handles SVGO-compacted paths: packed decimals ("15.12.11" = 15.12 then .11),
/// packed arc flags ("01" = flag 0 then flag 1), and leading-dot numbers (".5").
/// Supports M/L/H/V/C/S/Q/T/A/Z, absolute + relative; arcs → cubic béziers.
enum SVGPath {
    static func cgPath(from d: String) -> CGPath {
        let path = CGMutablePath()
        let s = Array(d)
        let n = s.count
        var i = 0
        var current = CGPoint.zero
        var subStart = CGPoint.zero
        var prevCtrl: CGPoint?
        var prevCmd: Character = " "

        func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
        func isSep(_ c: Character) -> Bool { c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" }
        func skipSep() { while i < n, isSep(s[i]) { i += 1 } }

        func readNumber() -> CGFloat {
            skipSep()
            let start = i
            if i < n, s[i] == "-" || s[i] == "+" { i += 1 }
            var seenDot = false
            while i < n {
                let c = s[i]
                if isDigit(c) { i += 1 }
                else if c == "." && !seenDot { seenDot = true; i += 1 }
                else { break }
            }
            if i < n, s[i] == "e" || s[i] == "E" {
                i += 1
                if i < n, s[i] == "-" || s[i] == "+" { i += 1 }
                while i < n, isDigit(s[i]) { i += 1 }
            }
            guard i > start else { return 0 }
            var str = String(s[start..<i])
            if str.hasPrefix(".") { str = "0" + str }
            else if str.hasPrefix("-.") { str = "-0" + str.dropFirst() }
            else if str.hasPrefix("+.") { str = "0" + str.dropFirst() }
            return CGFloat(Double(str) ?? 0)
        }

        // Arc flags are single characters '0' or '1' and may be packed with no separator.
        func readFlag() -> Bool {
            skipSep()
            if i < n, s[i] == "0" || s[i] == "1" { let f = s[i] == "1"; i += 1; return f }
            return readNumber() != 0
        }

        func readPoint(_ rel: Bool) -> CGPoint {
            let x = readNumber(), y = readNumber()
            return rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }
        func reflect() -> CGPoint {
            guard let c = prevCtrl else { return current }
            return CGPoint(x: 2 * current.x - c.x, y: 2 * current.y - c.y)
        }

        while i < n {
            skipSep()
            if i >= n { break }
            let iterStart = i
            var fromCommand = false
            var cmd: Character
            if "MmLlHhVvCcSsQqTtAaZz".contains(s[i]) {
                cmd = s[i]; i += 1; fromCommand = true
            } else {
                cmd = (prevCmd == "M") ? "L" : (prevCmd == "m") ? "l" : prevCmd
            }
            let rel = cmd.isLowercase
            switch Character(cmd.uppercased()) {
            case "M":
                current = readPoint(rel); path.move(to: current); subStart = current; prevCtrl = nil
            case "L":
                current = readPoint(rel); path.addLine(to: current); prevCtrl = nil
            case "H":
                let x = readNumber(); current = CGPoint(x: rel ? current.x + x : x, y: current.y)
                path.addLine(to: current); prevCtrl = nil
            case "V":
                let y = readNumber(); current = CGPoint(x: current.x, y: rel ? current.y + y : y)
                path.addLine(to: current); prevCtrl = nil
            case "C":
                let c1 = readPoint(rel), c2 = readPoint(rel), e = readPoint(rel)
                path.addCurve(to: e, control1: c1, control2: c2); current = e; prevCtrl = c2
            case "S":
                let c1 = (prevCmd == "C" || prevCmd == "c" || prevCmd == "S" || prevCmd == "s") ? reflect() : current
                let c2 = readPoint(rel), e = readPoint(rel)
                path.addCurve(to: e, control1: c1, control2: c2); current = e; prevCtrl = c2
            case "Q":
                let c = readPoint(rel), e = readPoint(rel)
                path.addQuadCurve(to: e, control: c); current = e; prevCtrl = c
            case "T":
                let c = (prevCmd == "Q" || prevCmd == "q" || prevCmd == "T" || prevCmd == "t") ? reflect() : current
                let e = readPoint(rel)
                path.addQuadCurve(to: e, control: c); current = e; prevCtrl = c
            case "A":
                let rx = readNumber(), ry = readNumber(), rot = readNumber()
                let large = readFlag(), sweep = readFlag()
                let e = readPoint(rel)
                addArc(path, from: current, rx: rx, ry: ry, rotationDeg: rot, largeArc: large, sweep: sweep, to: e)
                current = e; prevCtrl = nil
            case "Z":
                path.closeSubpath(); current = subStart; prevCtrl = nil
                if !fromCommand { i += 1 } // avoid a stall on a stray implicit Z
            default:
                i += 1
            }
            if i == iterStart { i += 1 } // safety: never stall
            prevCmd = cmd
        }
        return path
    }

    // MARK: - Arc → bézier (SVG implementation notes, F.6)

    private static func addArc(_ path: CGMutablePath, from p0: CGPoint,
                               rx rxIn: CGFloat, ry ryIn: CGFloat, rotationDeg: CGFloat,
                               largeArc: Bool, sweep: Bool, to p1: CGPoint) {
        if p0 == p1 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.addLine(to: p1); return }

        let phi = rotationDeg * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1 = cosP * dx + sinP * dy
        let y1 = -sinP * dx + cosP * dy

        var rx2 = rx * rx, ry2 = ry * ry
        let lambda = (x1 * x1) / rx2 + (y1 * y1) / ry2
        if lambda > 1 { let s = sqrt(lambda); rx *= s; ry *= s; rx2 = rx * rx; ry2 = ry * ry }

        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        var numer = rx2 * ry2 - rx2 * y1 * y1 - ry2 * x1 * x1
        if numer < 0 { numer = 0 }
        let denom = rx2 * y1 * y1 + ry2 * x1 * x1
        let coef = denom > 0 ? sign * sqrt(numer / denom) : 0
        let cxp = coef * (rx * y1 / ry)
        let cyp = coef * (-ry * x1 / rx)
        let cx = cosP * cxp - sinP * cyp + (p0.x + p1.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(min(max(len > 0 ? dot / len : 0, -1), 1))
            if (ux * vy - uy * vx) < 0 { a = -a }
            return a
        }
        let ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry
        let vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var dTheta = angle(ux, uy, vx, vy)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let segs = max(Int(ceil(abs(dTheta) / (.pi / 2))), 1)
        let delta = dTheta / CGFloat(segs)
        let t = 4.0 / 3.0 * tan(delta / 4)
        var theta = theta1

        func point(_ ct: CGFloat, _ st: CGFloat) -> CGPoint {
            let ex = rx * ct, ey = ry * st
            return CGPoint(x: cosP * ex - sinP * ey + cx, y: sinP * ex + cosP * ey + cy)
        }
        func deriv(_ ct: CGFloat, _ st: CGFloat) -> CGPoint {
            let ex = -rx * st, ey = ry * ct
            return CGPoint(x: cosP * ex - sinP * ey, y: sinP * ex + cosP * ey)
        }

        for _ in 0..<segs {
            let t2 = theta + delta
            let start = point(cos(theta), sin(theta))
            let end = point(cos(t2), sin(t2))
            let d1 = deriv(cos(theta), sin(theta))
            let d2 = deriv(cos(t2), sin(t2))
            let c1 = CGPoint(x: start.x + t * d1.x, y: start.y + t * d1.y)
            let c2 = CGPoint(x: end.x - t * d2.x, y: end.y - t * d2.y)
            path.addCurve(to: end, control1: c1, control2: c2)
            theta = t2
        }
    }
}
