// Recognize Objects: turns imported machine stitches back into objects OpenHoop sews itself — fills (with their
// outline, holes, row angle, row spacing and stitch length) and satin columns (with their two rails) — so an imported
// design resizes at the same density and can be edited like one digitized here. Parts that look like neither stay
// as imported stitches; underlay and travel are left out, since the new objects sew their own.
//
// How it works, in three passes over each imported block (one thread):
//  1. Every stitch gets a label from the stitches around it: satin stitches go back and forth across a column (almost
//     every stitch turns back), fill rows run the same way and turn back at the end of each row (some turns),
//     running lines carry on without turning back. Runs of the same label are parts.
//  2. Parts are tidied: fill sections with the same rows join into one fill, and anything lying under a later, bigger
//     part of the thread is its underlay.
//  3. Each fill's row stitches are drawn on a fine grid and its edge traced (outline and holes); each satin's
//     stitches become rungs, one end on each rail. A part whose new object couldn't be sewn keeps its stitches.
import Foundation

public enum StitchRecognition {
    /// What Recognize Objects found, for its status message.
    public struct Summary: Equatable, Sendable {
        public var fills = 0, satins = 0
        /// Imported stitches kept as they are: parts that look like neither a fill nor a satin column.
        public var keptStitches = 0
        public init() {}
        /// True when something was turned into a fill or satin.
        public var foundAny: Bool { fills + satins > 0 }
    }

    /// What one stretch of stitches looks like.
    enum Kind { case fill, satin, running, unknown, underlay }

    /// Stitches shorter than this (row turns, satin steps) don't vote on which way a part runs.
    static let short = 0.8
    /// How many longer stitches on each side of a stitch are looked at to label it.
    static let window = 12
    /// A part needs at least this many stitches, or it joins its longer neighbour.
    static let minimumRun = 8
    /// The grid fill outlines are traced on, in mm.
    static let cell = 0.2

    /// One stretch of stitches with one label, from one imported block (one thread).
    struct Part {
        var kind: Kind
        var points: [Point]
        /// Fills: the direction the rows run (0–180°), and roughly how far apart they are (mm).
        var angle = 0.0, spacing = 0.0
        /// The machine stops after this part (an appliqué file stops for the fabric to be laid, say).
        var stopAfter = false
    }

    /// `block` (an imported stitch block) as recognized objects, in sewing order, and what was found. When nothing
    /// is recognized, `objects` is just `block`.
    public static func recognize(_ block: RunObject) -> (objects: [RunObject], summary: Summary) {
        guard let raw = block.rawStitches else { return ([block], Summary()) }
        var parts = pieces(raw).flatMap { piece -> [Part] in
            var made = runs(labels(piece.points)).map { Part(kind: $0.kind, points: Array(piece.points[$0.range.lowerBound...$0.range.upperBound])) }
            if piece.stopAfter, !made.isEmpty { made[made.count - 1].stopAfter = true }
            return made
        }
        tidy(&parts)
        var objects: [RunObject] = [], summary = Summary(), stopPending = false
        func kept(_ points: [Point]) -> RunObject {
            var object = RunObject(name: "\(block.name) · kept", nodes: [], color: block.color)
            object.rawStitches = RawStitchBlock(start: points[0], commands: points.dropFirst().map { RawStitch(.stitch, $0) }, sourceFormat: raw.sourceFormat)
            object.tieIn = false; object.tieOut = false; object.trimAfter = false
            summary.keptStitches += points.count - 1
            return object
        }
        for part in parts {
            var made: [RunObject] = []
            switch part.kind {
            case .underlay: break
            case .running where part.points.count < 30: break             // travel from one part to the next
            case .fill where part.points.count >= 40:
                made = fills(part, color: block.color)
                if made.isEmpty || made.contains(where: { StitchEngine.shapeProblem($0) != nil }) { made = [kept(part.points)] }
                else { summary.fills += made.count }
            case .satin where part.points.count >= 20:
                let spacing = satinSpacing(part.points)
                made = satinColumns(part.points).map { column in
                    let ring = closedRing(column), rungs = ring ?? column
                    var satin = RunObject(name: "\(block.color.name) satin", nodes: rungs.flatMap { [PathNode($0.0), PathNode($0.1)] }, color: block.color)
                    satin.closed = ring != nil
                    satin.digitizing = DigitizingSettings(kind: .satin)
                    if let spacing { satin.digitizing?.spacing = spacing }
                    return satin
                }
                if made.isEmpty || made.contains(where: { StitchEngine.shapeProblem($0) != nil }) { made = [kept(part.points)] }
                else { summary.satins += made.count }
            default: made = [kept(part.points)]
            }
            for i in made.indices { made[i].groupID = block.groupID }
            if !made.isEmpty, stopPending { made[0].stopAfter = true; stopPending = false }
            if part.stopAfter { if made.isEmpty { stopPending = true } else { made[made.count - 1].stopAfter = true } }
            objects += made
        }
        guard summary.foundAny, !objects.isEmpty else { return ([block], Summary()) }
        if block.stopAfter || stopPending { objects[objects.count - 1].stopAfter = true }
        return (objects, summary)
    }

    // MARK: - Labels

    /// The block's stitches in stretches sewn without a break: a new one starts at every jump, trim or stop.
    static func pieces(_ raw: RawStitchBlock) -> [(points: [Point], stopAfter: Bool)] {
        var pieces: [(points: [Point], stopAfter: Bool)] = [], current: [Point] = [], position = raw.start
        for command in raw.commands {
            if command.op == .stitch {
                if current.isEmpty { current = [position] }   // a stitch starts where the needle already is
                current.append(command.point)
            } else {
                if current.count > 1 { pieces.append((current, false)) }
                if command.op == .stop, !pieces.isEmpty { pieces[pieces.count - 1].stopAfter = true }
                current = []
            }
            position = command.point
        }
        if current.count > 1 { pieces.append((current, false)) }
        return pieces
    }

    /// True when stitch `b` points roughly back the way stitch `a` came.
    static func turnsBack(_ a: Point, _ b: Point) -> Bool { a.x * b.x + a.y * b.y < -0.7 * hypot(a.x, a.y) * hypot(b.x, b.y) }

    /// One label per stitch (points[i] to points[i + 1]), from the longer stitches around it: a satin turns back at
    /// nearly every stitch, fill rows now and then (and run parallel), a running line never.
    static func labels(_ points: [Point]) -> [Kind] {
        let vectors = zip(points, points.dropFirst()).map { $1 - $0 }
        let long = vectors.indices.filter { hypot(vectors[$0].x, vectors[$0].y) >= short }
        guard !long.isEmpty else { return Array(repeating: .running, count: vectors.count) }
        // turns[k]: does long stitch k turn back from long stitch k - 1?
        let turns = [false] + zip(long, long.dropFirst()).map { turnsBack(vectors[$0], vectors[$1]) }
        let longKinds = long.indices.map { k -> Kind in
            let lo = max(0, k - window), hi = min(long.count, k + window + 1)
            let turnShare = Double(turns[(lo + 1)..<hi].filter { $0 }.count) / Double(max(1, hi - lo - 1))
            // How parallel the stitches are: the average of their doubled angles is 1 when they all lie on one axis.
            var x = 0.0, y = 0.0
            for j in lo..<hi { let v = vectors[long[j]], angle = 2 * atan2(v.y, v.x); x += cos(angle); y += sin(angle) }
            let parallel = hypot(x, y) / Double(hi - lo)
            if turnShare >= 0.6 { return .satin }
            if turnShare > 0 && parallel >= 0.8 { return .fill }
            return turnShare == 0 ? .running : .unknown
        }
        // Every stitch, short ones too, takes the label of the nearest long stitch.
        var result: [Kind] = [], k = 0
        for i in vectors.indices {
            while k + 1 < long.count && abs(long[k + 1] - i) <= abs(long[k] - i) { k += 1 }
            result.append(longKinds[k])
        }
        return foldedShortRuns(result)
    }

    /// Runs shorter than `minimumRun` stitches join the longer run next to them, until none are left.
    static func foldedShortRuns(_ labels: [Kind]) -> [Kind] {
        var labels = labels
        while true {
            let all = runs(labels)
            guard all.count > 1, let n = all.firstIndex(where: { $0.range.count < minimumRun }) else { return labels }
            let neighbours = [n > 0 ? all[n - 1] : nil, n + 1 < all.count ? all[n + 1] : nil].compactMap { $0 }
            let longer = neighbours.max { $0.range.count < $1.range.count }!
            for i in all[n].range { labels[i] = longer.kind }
        }
    }

    /// Runs of equal labels, each with the range of stitches it covers.
    static func runs(_ labels: [Kind]) -> [(kind: Kind, range: Range<Int>)] {
        guard !labels.isEmpty else { return [] }
        var result: [(kind: Kind, range: Range<Int>)] = [], start = 0
        for i in 1...labels.count where i == labels.count || labels[i] != labels[start] {
            result.append((labels[start], start..<i))
            start = i
        }
        return result
    }

    // MARK: - Tidying

    /// A fill's row direction (0–180°) and roughly how far apart its rows are: the width across the rows shared out
    /// over the number of turns.
    static func rows(_ points: [Point]) -> (angle: Double, spacing: Double) {
        let long = zip(points, points.dropFirst()).map { $1 - $0 }.filter { hypot($0.x, $0.y) >= short }
        guard long.count >= 2 else { return (0, 0) }
        let x = long.reduce(0) { $0 + cos(2 * atan2($1.y, $1.x)) }, y = long.reduce(0) { $0 + sin(2 * atan2($1.y, $1.x)) }
        let axis = atan2(y, x) / 2
        let across = points.map { -$0.x * sin(axis) + $0.y * cos(axis) }
        let turns = zip(long, long.dropFirst()).filter { turnsBack($0, $1) }.count
        var degrees = (axis * 180 / .pi).truncatingRemainder(dividingBy: 180)
        if degrees < 0 { degrees += 180 }
        return (degrees, (across.max()! - across.min()!) / Double(max(1, turns)))
    }

    /// A square of a 1 mm grid.
    struct Square: Hashable { var x, y: Int }

    /// The 1 mm squares a stretch of stitches passes over (looked at every 0.5 mm along each stitch).
    static func squares(_ points: [Point]) -> Set<Square> {
        var result = Set<Square>()
        for (a, b) in zip(points, points.dropFirst()) {
            let steps = max(1, Int(a.distance(to: b) / 0.5))
            for k in 0...steps {
                let p = a + (b - a) * (Double(k) / Double(steps))
                result.insert(Square(x: Int(floor(p.x)), y: Int(floor(p.y))))
            }
        }
        return result
    }

    /// `squares` with every square next to them added (1 mm more all round).
    static func grown(_ squares: Set<Square>) -> Set<Square> {
        var result = Set<Square>()
        for s in squares { for dx in -1...1 { for dy in -1...1 { result.insert(Square(x: s.x + dx, y: s.y + dy)) } } }
        return result
    }

    /// How much of `points` lies on `squares`, 0 to 1.
    static func coveredShare(_ points: [Point], _ squares: Set<Square>) -> Double {
        let mine = Self.squares(points)
        return Double(mine.intersection(squares).count) / Double(max(1, mine.count))
    }

    /// Joins fill sections into one fill, and marks underlay.
    /// - A fill, then at most five bits of 40 stitches or fewer, then a fill with rows within 8° and similar spacing:
    ///   one fill sewn in sections. Travel between them joins it; a small satin or fill outside them stays its own
    ///   part, sewn after the joined fill.
    /// - Underlay: whatever is sewn just before a fill (from 150 stitches) or satin (from 40) of its thread and lies on
    ///   it (85% within 1 mm of its stitches), and then anything else lying under a later, bigger part.
    static func tidy(_ parts: inout [Part]) {
        for i in parts.indices {
            if parts[i].kind == .unknown {
                let vectors = zip(parts[i].points, parts[i].points.dropFirst()).map { $1 - $0 }.filter { hypot($0.x, $0.y) >= short }
                if !zip(vectors, vectors.dropFirst()).contains(where: { turnsBack($0, $1) }) { parts[i].kind = .running }
            }
            if parts[i].kind == .fill { (parts[i].angle, parts[i].spacing) = rows(parts[i].points) }
        }
        func sameRows(_ a: Part, _ b: Part) -> Bool {
            let d = abs(a.angle - b.angle).truncatingRemainder(dividingBy: 180)
            return min(d, 180 - d) <= 8 && max(a.spacing, b.spacing) / max(0.01, min(a.spacing, b.spacing)) < 2.5
        }
        var joined = true
        while joined {
            joined = false
            search: for i in parts.indices.dropLast() where parts[i].kind == .fill {
                for j in (i + 1)..<min(i + 7, parts.count) {
                    let between = parts[(i + 1)..<j]
                    if between.contains(where: { $0.points.count > 40 }) { break }
                    guard parts[j].kind == .fill, sameRows(parts[i], parts[j]) else { continue }
                    let both = squares(parts[i].points).union(squares(parts[j].points))
                    let outside = between.filter { $0.kind != .running && $0.kind != .unknown && coveredShare($0.points, both) < 0.85 }
                    let inside = between.filter { $0.kind == .running || $0.kind == .unknown || coveredShare($0.points, both) >= 0.85 }
                    parts[i].points += inside.flatMap(\.points) + parts[j].points
                    parts[i].stopAfter = parts[i].stopAfter || between.contains(where: \.stopAfter) || parts[j].stopAfter
                    (parts[i].angle, parts[i].spacing) = rows(parts[i].points)
                    parts.replaceSubrange((i + 1)...j, with: outside)
                    joined = true
                    break search
                }
            }
        }
        func big(_ part: Part) -> Bool { (part.kind == .fill && part.points.count >= 150) || (part.kind == .satin && part.points.count >= 40) }
        for i in parts.indices where big(parts[i]) {
            let under = grown(squares(parts[i].points))
            var j = i - 1
            while j >= 0, parts[j].kind != .underlay, parts[j].points.count < parts[i].points.count, coveredShare(parts[j].points, under) >= 0.85 {
                parts[j].kind = .underlay
                j -= 1
            }
        }
        for i in parts.indices where big(parts[i]) {
            let under = grown(squares(parts[i].points))
            for k in 0..<i where [.fill, .satin, .unknown].contains(parts[k].kind) && parts[k].points.count < parts[i].points.count
                && coveredShare(parts[k].points, under) >= 0.85 {
                parts[k].kind = .underlay
            }
        }
    }

    // MARK: - Fills

    /// A recognized fill as fill objects, one per separate patch of rows: outline and holes traced from its rows,
    /// with its row angle, row spacing and stitch length.
    static func fills(_ part: Part, color: ThreadColor) -> [RunObject] {
        let gap = rowGap(part.points, angle: part.angle), length = typicalStitch(part.points)
        // Shown in Properties as −90…90°.
        let angle = (part.angle > 90 ? part.angle - 180 : part.angle).rounded()
        let pattern = tatamiPattern(part.points, rowAngle: part.angle, angle: angle, gap: gap, length: length)
        let handStitch = fillHandStitch(part.points)
        return regions(part).map { region in
            var fill = RunObject(name: "\(color.name) fill", nodes: region[0].map { PathNode($0) }, color: color)
            fill.closed = true
            fill.holes = region.count > 1 ? region.dropFirst().map { $0.map { PathNode($0) } } : nil
            var settings = DigitizingSettings(kind: .fill)
            settings.angle = angle
            settings.spacing = (gap * 2 * 100).rounded() / 100        // Spacing is measured across two rows
            settings.tatamiPattern = pattern
            settings.fillHandStitch = handStitch
            fill.digitizing = settings
            fill.stitchLength = (length * 10).rounded() / 10
            return fill
        }
    }

    /// The tatami pattern a recognized fill was sewn with (its id), or nil for Smooth, or when no row pattern in the
    /// library matches closely (picture and random patterns aren't looked for). A pattern says how far along each
    /// row's needle holes start, row after row in the order they're sewn; so the rows are numbered in the direction
    /// they were sewn, and for each one the shift of its holes from the row before is measured hole by hole against
    /// that row's nearest hole (so a small error in the stitch length doesn't add up along the row). That list of
    /// shifts is compared with each pattern's, from each of its rows in turn. `rowAngle` is the rows' direction as
    /// measured (0–180°), `angle` the fill's Angle as set (−90–90°): the rows are turned by it as the fill engine does.
    static func tatamiPattern(_ points: [Point], rowAngle: Double, angle: Double, gap: Double, length: Double) -> String? {
        guard gap > 0, length > 0 else { return nil }
        let stitches = rowStitches(points, angle: rowAngle).filter { $0.0.distance(to: $0.1) >= short }
            .map { (AreaGeometry.rotate($0.0, degrees: -angle), AreaGeometry.rotate($0.1, degrees: -angle)) }
        guard let first = stitches.first, let last = stitches.last, let low = stitches.map({ min($0.0.y, $0.1.y) }).min(),
              let high = stitches.map({ max($0.0.y, $0.1.y) }).max() else { return nil }
        // Rows numbered from the side the fill started on.
        let upward = first.0.y <= last.0.y
        func row(_ y: Double) -> Int { Int(((upward ? y - low : high - y) / gap).rounded()) }
        var holes: [Int: Set<Double>] = [:]
        for (a, b) in stitches { for p in [a, b] { holes[row(p.y), default: []].insert((p.x * 100).rounded() / 100) } }
        let rows = holes.mapValues { $0.sorted() }
        func fraction(_ x: Double) -> Double { x - floor(x) }
        func apart(_ a: Double, _ b: Double) -> Double { let d = abs(a - b); return min(d, 1 - d) }
        // Each row's shift from the row before, as a fraction of a stitch (0 up to 1); a row's end holes are on the
        // fill's edge, not on its pattern, so they're left out.
        var shifts: [(row: Int, shift: Double)] = []
        for (number, these) in rows where these.count >= 4 {
            guard let before = rows[number - 1], before.count >= 4 else { continue }
            let inner = Array(before.dropFirst().dropLast())
            let measured = these.dropFirst().dropLast().map { x in fraction((x - inner.min { abs($0 - x) < abs($1 - x) }!) / length) }
            // The usual shift: the commonest 1/32 of a stitch, averaged with its neighbours.
            var counts = [Int](repeating: 0, count: 32)
            for m in measured { counts[Int(m * 32) % 32] += 1 }
            let usual = (Double(counts.indices.max { counts[$0] < counts[$1] }!) + 0.5) / 32
            let near = measured.filter { apart($0, usual) <= 1.0 / 32 }
            guard near.count >= 2 else { continue }
            let pull = near.map { $0 - usual > 0.5 ? $0 - 1 : usual - $0 > 0.5 ? $0 + 1 : $0 }
            shifts.append((number, fraction(pull.reduce(0, +) / Double(pull.count))))
        }
        guard shifts.count >= 8 else { return nil }
        var best: (id: String, error: Double)?
        for pattern in TatamiPattern.library where pattern.picture == nil && !pattern.rows.isEmpty {
            let starts = pattern.rows, n = starts.count
            let steps = (0..<n).map { fraction(starts[($0 + 1) % n] - starts[$0]) }
            for phase in 0..<n {
                let error = shifts.reduce(0) { $0 + apart($1.shift, steps[(($1.row - 1 + phase) % n + n) % n]) } / Double(shifts.count)
                if error < best?.error ?? .infinity { best = (pattern.id, error) }
            }
        }
        guard let best, best.error <= 0.04, best.id != TatamiPattern.smooth.id else { return nil }
        return best.id
    }

    /// A recognized fill's hand stitch (FillHandStitch.swift), or nil when its rows are neat. In a neat fill each hole
    /// inside a row lies on the straight line between its neighbours (a machine file rounds it by at most a few
    /// hundredths of a millimeter); hand stitch moves it off that line. So the usual distance off the line says
    /// whether the fill was hand-stitched, and how strongly: OpenHoop's own Light, Medium and Strong come to about
    /// 0.12, 0.23 and 0.37 mm, and the neat fills of five real designs to 0.05 mm or less.
    static func fillHandStitch(_ points: [Point]) -> FillHandStitch? {
        var off: [Double] = []
        for i in 1..<max(1, points.count - 1) {
            let a = points[i] - points[i - 1], b = points[i + 1] - points[i], across = points[i + 1] - points[i - 1]
            let la = hypot(a.x, a.y), lb = hypot(b.x, b.y), lc = hypot(across.x, across.y)
            // A hole between two row stitches going the same way (not a row's turn, not a short step).
            guard la >= short, lb >= short, (a.x * b.x + a.y * b.y) / (la * lb) > 0.5 else { continue }
            off.append(abs(a.x * across.y - a.y * across.x) / lc)
        }
        guard off.count >= 50 else { return nil }
        let usual = off.sorted()[off.count / 2]
        guard usual >= 0.09 else { return nil }
        var hand = FillHandStitch()
        hand.strength = usual < 0.17 ? .light : usual < 0.29 ? .medium : .strong
        return hand
    }

    /// The stitches that make a fill's rows: those within 20° of the row direction, and the short turns between
    /// rows. Longer stitches at other angles are travel, which would draw lines across the fill's holes.
    static func rowStitches(_ points: [Point], angle: Double) -> [(Point, Point)] {
        zip(points, points.dropFirst()).filter { a, b in
            guard a.distance(to: b) >= short else { return true }
            let d = abs(atan2(b.y - a.y, b.x - a.x) * 180 / .pi - angle).truncatingRemainder(dividingBy: 180)
            return min(d, 180 - d) <= 20
        }
    }

    /// The fill's shape: its row stitches drawn on a 0.2 mm grid, the gaps between rows closed (0.4 mm), and the
    /// edges traced, softened and fitted to what a fill can hold. Each region is an outline, then its holes.
    static func regions(_ part: Part) -> [[[Point]]] {
        let stitches = rowStitches(part.points, angle: part.angle)
        let all = stitches.flatMap { [$0.0, $0.1] }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(), let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        let margin = 4, originX = minX - Double(margin) * cell, originY = minY - Double(margin) * cell
        let w = Int((maxX - minX) / cell) + 2 * margin + 1, h = Int((maxY - minY) / cell) + 2 * margin + 1
        guard w * h <= 4_000_000 else { return [] }                       // larger than 400 × 400 mm: not a fill
        var mask = [Bool](repeating: false, count: w * h)
        for (a, b) in stitches {
            let steps = max(1, Int(a.distance(to: b) / (cell / 2)))
            for k in 0...steps {
                let p = a + (b - a) * (Double(k) / Double(steps))
                mask[Int((p.y - originY) / cell) * w + Int((p.x - originX) / cell)] = true
            }
        }
        mask = shrunk(grown(mask, w, h, by: 2), w, h, by: 2)
        AutoDigitize.separateDiagonals(&mask, width: w, height: h)
        let rings = AutoDigitize.traceRings(mask, width: w, height: h)
            .map { AutoDigitize.simplify(AutoDigitize.softened($0), tolerance: 0.5) }
            .filter { $0.count >= 3 }
            .map { $0.map { Point(originX + $0.x * cell, originY + $0.y * cell) } }
        guard let traced = try? AreaGeometry.svgRegions(rings, nonzero: false) else { return [] }
        return traced.compactMap { region in
            guard let (fitted, _) = AutoDigitize.fitted(region, smallest: 3) else { return nil }
            let area = AreaGeometry.area(fitted[0]).magnitude - fitted.dropFirst().reduce(0) { $0 + AreaGeometry.area($1).magnitude }
            guard area >= 3, (try? AreaGeometry.validate(fitted)) != nil else { return nil }
            return fitted
        }
    }

    /// The grid with every filled square spread `by` squares each way (a square brush), row by row then column by column.
    static func grown(_ mask: [Bool], _ w: Int, _ h: Int, by r: Int) -> [Bool] { spread(mask, w, h, by: r, value: true) }
    /// The grid with every empty square spread `by` squares each way: the filled area shrinks back.
    static func shrunk(_ mask: [Bool], _ w: Int, _ h: Int, by r: Int) -> [Bool] { spread(mask, w, h, by: r, value: false) }
    static func spread(_ mask: [Bool], _ w: Int, _ h: Int, by r: Int, value: Bool) -> [Bool] {
        var across = mask
        for y in 0..<h { for x in 0..<w where mask[y * w + x] == value {
            for dx in max(0, x - r)...min(w - 1, x + r) { across[y * w + dx] = value }
        } }
        var result = across
        for y in 0..<h { for x in 0..<w where across[y * w + x] == value {
            for dy in max(0, y - r)...min(h - 1, y + r) { result[dy * w + x] = value }
        } }
        return result
    }

    /// How far apart a fill's rows are: its long stitches grouped into rows (a row ends where the direction turns),
    /// each row placed by its middle stitch across the rows, and the middle of the steps from one row to the next.
    static func rowGap(_ points: [Point], angle: Double) -> Double {
        let axis = angle * .pi / 180, along = Point(cos(axis), sin(axis)), across = Point(-sin(axis), cos(axis))
        var rows: [[Double]] = [], current: [Double] = [], direction = 0
        for (a, b) in zip(points, points.dropFirst()) where a.distance(to: b) >= short {
            let d = b - a, sign = d.x * along.x + d.y * along.y > 0 ? 1 : -1
            if !current.isEmpty && sign != direction { rows.append(current); current = [] }
            direction = sign
            let middle = (a + b) * 0.5
            current.append(middle.x * across.x + middle.y * across.y)
        }
        if !current.isEmpty { rows.append(current) }
        let places = rows.filter { $0.count >= 2 }.map { $0.sorted()[$0.count / 2] }
        let steps = zip(places, places.dropFirst()).map { abs($1 - $0) }.filter { $0 < 1.5 }.sorted()
        return steps.isEmpty ? 0.2 : min(1, max(0.1, steps[steps.count / 2]))
    }

    /// The middle length of a part's long stitches: the stitch length it was digitized with (1–7 mm).
    static func typicalStitch(_ points: [Point]) -> Double {
        let lengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }.filter { $0 >= short }.sorted()
        return lengths.isEmpty ? 3 : min(7, max(1, lengths[lengths.count / 2]))
    }

    // MARK: - Satins

    typealias Rung = (Point, Point)

    static func middle(_ rung: Rung) -> Point { (rung.0 + rung.1) * 0.5 }

    /// How far apart a recognized satin's stitches are along the column: its Spacing, in mm, or nil if there are too
    /// few stitches across to tell. Each stitch across moves on half a spacing (it goes over to one side, the next one
    /// back to the other), so it's twice the usual step between the middles of neighbouring stitches across. Steps
    /// longer than 1.5 mm are moves between passes, not spacing.
    static func satinSpacing(_ points: [Point]) -> Double? {
        guard points.count >= 3 else { return nil }
        var steps: [Double] = []
        for i in 0..<(points.count - 2) where points[i].distance(to: points[i + 1]) >= short && points[i + 1].distance(to: points[i + 2]) >= short {
            let step = ((points[i] + points[i + 1]) * 0.5).distance(to: (points[i + 1] + points[i + 2]) * 0.5)
            if step <= 1.5 { steps.append(step) }
        }
        guard steps.count >= 10 else { return nil }
        let typical = steps.sorted()[steps.count / 2] * 2
        return min(5, max(0.15, (typical * 100).rounded() / 100))   // within what Properties lets Spacing be
    }

    /// A recognized satin as columns, each a list of rungs (one end on each rail). Stitches not parallel to their
    /// neighbours (travel, a stitch across) are left out. Some programs sew a satin in passes — an oval's top half
    /// downwards, then its bottom half upwards — so the stitches are split where the needle moves on more than
    /// 1.5 mm, and passes that meet are joined (turned round if they meet end to end).
    static func satinColumns(_ points: [Point]) -> [[Rung]] {
        let rungs: [Rung] = zip(points, points.dropFirst()).filter { $0.distance(to: $1) >= short }
        func axis(_ r: Rung) -> Double {
            let a = atan2(r.1.y - r.0.y, r.1.x - r.0.x) * 180 / .pi
            return a < 0 ? a + 180 : a
        }
        func apart(_ p: Double, _ q: Double) -> Double { let d = abs(p - q).truncatingRemainder(dividingBy: 180); return min(d, 180 - d) }
        let kept = rungs.indices.filter { i in
            let near = rungs[max(0, i - 4)..<min(rungs.count, i + 5)].map(axis)
            // The usual direction nearby: the one closest to all the others.
            let usual = near.min { a, b in near.reduce(0) { $0 + apart(a, $1) } < near.reduce(0) { $0 + apart(b, $1) } }!
            return apart(axis(rungs[i]), usual) <= 25
        }.map { rungs[$0] }
        guard kept.count >= 4 else { return [] }
        var passes: [[Rung]] = [[kept[0]]]
        for rung in kept.dropFirst() {
            if middle(rung).distance(to: middle(passes[passes.count - 1].last!)) > 1.5 { passes.append([]) }
            passes[passes.count - 1].append(rung)
        }
        var joined: [[Rung]] = []
        for pass in passes where pass.count >= 4 {
            if let last = joined.last {
                if middle(pass[0]).distance(to: middle(last.last!)) <= 1.5 { joined[joined.count - 1] += pass; continue }
                if middle(pass.last!).distance(to: middle(last.last!)) <= 1.5 { joined[joined.count - 1] += pass.reversed(); continue }
            }
            joined.append(pass)
        }
        return joined.map { cleaned(smoothed(withoutTurningBack(picked(sameSides($0))))) }.filter { !$0.isEmpty }
    }

    /// A column whose two ends meet (a satin ring, such as a border round a shape) as a closed satin's rungs: the
    /// rungs at the end that come back over the first one (within 1.5 mm of it) are dropped, so the ring closes
    /// smoothly instead of pinching where it meets itself. nil when the ends are apart, when the column is too short
    /// to go round anything, or when its rails would join crossed (left to right).
    static func closedRing(_ rungs: [Rung]) -> [Rung]? {
        guard rungs.count >= 8, let first = rungs.first else { return nil }
        var kept = rungs
        while kept.count > 3, middle(kept[kept.count - 1]).distance(to: middle(first)) <= 1.5 { kept.removeLast() }
        guard kept.count >= 6, let last = kept.last, middle(last).distance(to: middle(first)) <= 3 else { return nil }
        let around = zip(kept, kept.dropFirst()).reduce(0) { $0 + middle($1.0).distance(to: middle($1.1)) }
        guard around >= 10 else { return nil }
        let straight = last.0.distance(to: first.0) + last.1.distance(to: first.1), crossed = last.0.distance(to: first.1) + last.1.distance(to: first.0)
        return straight < crossed ? kept : nil
    }

    /// Each rung's ends swapped where needed so the first end stays on the same rail as the last rung's.
    static func sameSides(_ rungs: [Rung]) -> [Rung] {
        var result = [rungs[0]]
        for rung in rungs.dropFirst() {
            let last = result[result.count - 1]
            let straight = rung.0.distance(to: last.0) + rung.1.distance(to: last.1), swapped = rung.1.distance(to: last.0) + rung.0.distance(to: last.1)
            result.append(straight <= swapped ? rung : (rung.1, rung.0))
        }
        return result
    }

    /// At least 14 rungs per column and at most one a millimetre: the longest in each stretch, so the shortened
    /// stitches on the inside of a curve don't pull the rail in. (The middle of a satin's stitches zigzags, so half
    /// the distance along the middles is about the column's length.)
    static func picked(_ rungs: [Rung]) -> [Rung] {
        var along = [0.0]
        for (a, b) in zip(rungs, rungs.dropFirst()) { along.append(along[along.count - 1] + middle(a).distance(to: middle(b))) }
        let step = min(1, along[along.count - 1] / 2 / 14)
        var result: [Rung] = [], end = 0.0, best: Int?
        for i in rungs.indices {
            if along[i] / 2 > end, let b = best { result.append(rungs[b]); best = nil; end = along[i] / 2 + step }
            if best == nil || rungs[i].0.distance(to: rungs[i].1) > rungs[best!].0.distance(to: rungs[best!].1) { best = i }
        }
        if let b = best { result.append(rungs[b]) }
        return result
    }

    /// Without rungs where the column doubles back (the step to it points the opposite way from the next step),
    /// such as a lead-in stitch sewn just short of the tip the column then starts from.
    static func withoutTurningBack(_ rungs: [Rung]) -> [Rung] {
        var rungs = rungs
        func back(_ a: Point, _ b: Point, _ c: Point) -> Bool { (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y) < 0 }
        while rungs.count > 3 {
            let m = rungs.map(middle), n = m.count
            guard let i = m.indices.first(where: { i in
                i == 0 ? back(m[0], m[1], m[2]) : i == n - 1 ? back(m[n - 3], m[n - 2], m[n - 1]) : back(m[i - 1], m[i], m[i + 1])
            }) else { break }
            rungs.remove(at: i)
        }
        return rungs
    }

    /// Each rail point averaged with its neighbours (¼, ½, ¼), keeping both ends where they are.
    static func smoothed(_ rungs: [Rung]) -> [Rung] {
        guard rungs.count >= 3 else { return rungs }
        func blend(_ p: Point, _ q: Point, _ r: Point) -> Point { (p + q * 2 + r) * 0.25 }
        return [rungs[0]] + rungs.indices.dropFirst().dropLast().map { i in
            (blend(rungs[i - 1].0, rungs[i].0, rungs[i + 1].0), blend(rungs[i - 1].1, rungs[i].1, rungs[i + 1].1))
        } + [rungs[rungs.count - 1]]
    }

    /// Without the rungs a satin column can't have: ends narrower than 0.6 mm (the tips of an oval, where the rails
    /// would touch), and rungs where either rail doesn't move on by at least 0.1 mm, or goes backwards.
    static func cleaned(_ rungs: [Rung]) -> [Rung] {
        var rungs = rungs
        while rungs.count > 2 && rungs[0].0.distance(to: rungs[0].1) < 0.6 { rungs.removeFirst() }
        while rungs.count > 2 && rungs[rungs.count - 1].0.distance(to: rungs[rungs.count - 1].1) < 0.6 { rungs.removeLast() }
        guard let first = rungs.first else { return [] }
        var result = [first]
        for rung in rungs.dropFirst() {
            let last = result[result.count - 1], d = middle(rung) - middle(last)
            func onward(_ from: Point, _ to: Point) -> Bool { from.distance(to: to) >= 0.1 && (to.x - from.x) * d.x + (to.y - from.y) * d.y > 0 }
            if onward(last.0, rung.0) && onward(last.1, rung.1) { result.append(rung) }
        }
        return result.count >= 2 ? result : []
    }
}

extension Design {
    /// Recognize Objects: each imported stitch block among `ids` replaced, in place, by the fills and satin columns
    /// recognized in it (StitchRecognition), with what can't be recognized kept as imported stitches. A block where
    /// nothing is recognized stays as it is. Returns what was found; the design only changes when something was.
    public mutating func recognizeObjects(_ ids: Set<UUID>) -> StitchRecognition.Summary {
        var total = StitchRecognition.Summary(), result: [RunObject] = []
        for object in objects {
            guard ids.contains(object.id), object.rawStitches != nil else { result.append(object); continue }
            let (made, summary) = StitchRecognition.recognize(object)
            total.fills += summary.fills; total.satins += summary.satins; total.keptStitches += summary.keptStitches
            result += made
        }
        if total.foundAny { objects = result }
        return total
    }
}
