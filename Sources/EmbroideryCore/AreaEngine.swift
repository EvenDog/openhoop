import Foundation

public struct StitchSection: Sendable {
    public var points:[Point]
    public var underlay:Bool
    /// True when this section carries straight on from where the previous one ended (joined by a travel run inside
    /// the shape), so no trim, jump or tie stitches are needed between them.
    public var joined:Bool
    public init(_ points:[Point],underlay:Bool=false,joined:Bool=false){self.points=points;self.underlay=underlay;self.joined=joined}
}
public struct ObjectStitches: Sendable {public var sections:[StitchSection]=[];public var warnings:[String]=[]}

public enum AreaEngine {
    /// Fill rows are split into monotone sections at interval splits and merges.
    /// Every sewn connector is checked against the compensated region, including holes.
    public static func fill(_ object:RunObject) throws -> ObjectStitches {
        let s=object.settings
        let original=([object.nodes]+(object.holes ?? [])).map{AreaGeometry.ring($0)}
        try AreaGeometry.validate(original)
        let expanded=try AreaGeometry.offset(original,by:s.expansion)
        guard !expanded.isEmpty else{throw DesignError.invalid("Fill compensation collapses this region.")}
        var result=ObjectStitches()
        // Travel between sections follows rings just inside the shape's edge (the edge itself if that inset collapses).
        let edges=(try? AreaGeometry.offset(original,by:-0.25)).flatMap{$0.count==original.count ? $0:nil} ?? original
        /// Where the needle can actually start or end for a start or end point: the point itself when it's inside the
        /// shape, otherwise (off the shape, or in a hole) the nearest place just inside the edge.
        func reachable(_ point:Point?)->Point? {
            guard let point else{return nil}
            if AreaGeometry.contains(point,rings:edges){return point}
            return edges.flatMap{ring in ring.indices.map{AreaGeometry.projection(point,ring[$0],ring[($0+1)%ring.count])}}.min{$0.distance(to:point)<$1.distance(to:point)}
        }
        let entry=reachable(object.entry),exit=reachable(object.exit)
        let style=s.fillStyle ?? .tatami
        // Stipple, motif and cross stitch fills are open, decorative stitches, sewn without underlay.
        if s.underlay != .none && ![.stipple,.motif,.crossStitch].contains(style) {
            // Underlay is inset from the source, never expanded a second time.
            let inset=try AreaGeometry.offset(original,by:-s.inset)
            if inset.isEmpty {result.warnings.append("Underlay collapsed at the chosen inset; no underlay was generated.")}
            else {
                // With a start point, each underlay outline begins at its corner nearest that point.
                func startNearEntry(_ ring:[Point])->[Point] {
                    guard let entry,let k=ring.indices.min(by:{ring[$0].distance(to:entry)<ring[$1].distance(to:entry)}) else{return ring}
                    return Array(ring[k...]+ring[..<k])
                }
                result.sections += inset.map{startNearEntry($0)}.map{StitchSection(AreaGeometry.sampled($0+Array($0.prefix(1)),length:2.5),underlay:true)}
                if s.underlay == .edgeAndSparse {
                    result.sections += try rows(in:inset,angle:s.angle+90,spacing:s.underlaySpacing,length:2.5).filter(isLongEnough).map{StitchSection($0,underlay:true)}
                }
            }
        }
        // The top rows, in parts sewn one after another (tatami and wave fills with an end point come in two).
        var parts:[[[Point]]]
        // Without a start point, contour and radial fills begin where the underlay finished, so no long travel is needed.
        let start=entry ?? result.sections.last?.points.last
        switch style {
        case .tatami where !(s.angleLines ?? []).isEmpty:
            parts=try turningParts(in:expanded,angleLines:s.angleLines!,entry:entry,exit:exit,start:start){region,lines,from,to in
                try TurningFill.rows(in:region,angleLines:lines,spacing:s.rowGap,length:object.stitchLength,start:from,end:to)}
            guard !parts[0].isEmpty else{throw DesignError.invalid("The stitch angle lines don't cross this fill. Draw them across it, or remove them.")}
        case .satin where !(s.angleLines ?? []).isEmpty:
            // A turning satin: the same rows, re-stitched so each is one stitch from edge to edge (see `asSatin`).
            let maximum=s.satinSplit ?? DigitizingSettings.defaultSatinSplit
            parts=try turningParts(in:expanded,angleLines:s.angleLines!,entry:entry,exit:exit,start:start){region,lines,from,to in
                try asSatin(try TurningFill.rows(in:region,angleLines:lines,spacing:s.spacing,length:maximum,start:from,end:to),maximum:maximum,split:s.autoSplit != false)}
            guard !parts[0].isEmpty else{throw DesignError.invalid("The stitch angle lines don't cross this fill. Draw them across it, or remove them.")}
        case .tatami,.wave,.gradient:parts=try topRows(in:expanded,object,entry:entry,exit:exit)
        case .contour:parts=[try FillStyles.contour(in:expanded,spacing:s.spacing,length:object.stitchLength,start:start)]
        case .motif:parts=[try Motifs.fill(in:expanded,motif:s.motif ?? .heart,size:s.patternSize ?? DigitizingSettings.defaultPatternSize(.motif),gap:s.patternGap ?? DigitizingSettings.defaultPatternGap,angle:s.angle,length:object.stitchLength)]
        case .crossStitch:parts=[try Motifs.crossStitch(in:expanded,size:s.patternSize ?? DigitizingSettings.defaultPatternSize(.crossStitch))]
        case .stipple:parts=[try FillStyles.stipple(in:expanded,spacing:s.stippleSpacing ?? DigitizingSettings.defaultStippleSpacing,length:object.stitchLength,start:start)]
        case .guided:
            guard let guide=s.guideLine else{throw DesignError.invalid("This guided fill has no guide line. Draw a line over it, select both and choose Use Line as Fill Guide.")}
            parts=[try GuidedFill.rows(in:expanded,guide:guide,spacing:s.rowGap,length:object.stitchLength)]
        case .satin:parts=[try SatinFill.stitches(in:expanded,angle:s.angle,spacing:s.spacing,maximum:s.satinSplit ?? DigitizingSettings.defaultSatinSplit,split:s.autoSplit != false)]
        case .radial:parts=[try FillStyles.radial(in:expanded,center:s.radialCenter ?? AreaGeometry.centroid(original[0]),spacing:s.spacing,length:object.stitchLength,start:start)]
        }
        parts=parts.map{$0.filter(isLongEnough)}.filter{!$0.isEmpty}
        guard !parts.isEmpty else{throw DesignError.invalid(tooSmall(style))}
        // A 0.01 mm margin keeps row ends, which lie exactly on the edge, reliably "inside" for routing. Wave row ends
        // can sit a few thousandths of a millimeter further out (the edge is bent back in short pieces), so they get 0.05 mm.
        let bounds=(try? AreaGeometry.offset(expanded,by:style == .wave ? 0.05:0.01)) ?? expanded
        // Contour, radial and turning stitches run every which way, so travel across them is priced like satin (no
        // row angle); contour and radial rows already come in sewing order.
        let rowStyle=((style == .tatami || style == .satin) && (s.angleLines ?? []).isEmpty) || style == .wave || style == .gradient
        let router=TravelRouter(edges:edges,bounds:bounds,rowAngle:rowStyle ? s.angle:nil)
        // Guided rows bend, so travel across them is priced like satin too, but they're put in sewing order like straight rows.
        // Turning fills come already in sewing order: each branch of the shape is sewn so its travel is covered.
        let reorders=rowStyle || style == .guided
        // Sew each part's sections in the order (and from the ends) that keep travel shortest. Its first section stays
        // first (it honors the start point); with an end point, the last part's last stays last. Contour and radial
        // sections already come in sewing order.
        // A later part is sewn from its far end back toward the part before, so the travel out to that end crosses
        // the part itself, which then sews over it: that travel may be long.
        var coveredStarts:Set<Int>=[]
        for (index,part) in parts.enumerated() {
            if index>0 {coveredStarts.insert(result.sections.count)}
            let sections=part.map{StitchSection($0)}
            result.sections += reorders ? router?.ordered(sections,keepingLast:exit != nil && index==parts.count-1) ?? sections : sections
        }
        result.sections=router?.join(result.sections,coveredStarts:coveredStarts) ?? result.sections
        // The needle goes in exactly at the start point and runs inside the shape to where the stitching begins (under
        // everything sewn after it), and finishes exactly at the end point, which the last row runs beside.
        if let router,let entry,let first=result.sections.first?.points.first,first.distance(to:entry)>0.01,let path=router.route(from:entry,to:first) {
            let travel=router.travelStitches(path)
            if travel.count>1 {result.sections[0].joined=true;result.sections.insert(StitchSection(travel),at:0)}
        }
        if let router,let exit,let last=result.sections.last?.points.last,last.distance(to:exit)>0.01,let path=router.route(from:last,to:exit) {
            let travel=router.travelStitches(path)
            if travel.count>1 {result.sections.append(StitchSection(travel,joined:true))}
        }
        let trims=result.sections.dropFirst().filter{!$0.joined}.count
        if trims>0 {result.warnings.append("Fill needs \(trims) trim\(trims==1 ? "":"s") between sections that no short path inside the shape connects.")}
        return result
    }
    /// Why a fill came out empty, in the terms of its style.
    static func tooSmall(_ style:FillStyle)->String {
        switch style {
        case .motif:return "This fill is too small for its motifs. Make the motifs smaller or the shape bigger."
        case .crossStitch:return "This fill is too small for its cross-stitch squares. Make the squares smaller or the shape bigger."
        case .stipple:return "This fill is too small for its stipple spacing. Make the spacing smaller or the shape bigger."
        default:return "This fill is too small for the selected row spacing."
        }
    }
    /// False for a scrap of a row (clipped at a sharp corner) too short to make one stitch: it would sew as a single
    /// stitch under 0.3 mm and hold nothing, so it's left out.
    private static func isLongEnough(_ row:[Point])->Bool {AreaGeometry.pathLength(row)>=StitchEngine.smallestStitch}
    /// Rows from the turning engine sewn as satin. The engine puts needle holes along each row the way tatami
    /// does (on a grid, a quarter stitch further on each row), which would break even a short satin stitch; so
    /// every point lying on the straight line between its neighbours is dropped, leaving each row as one stitch
    /// from edge to edge. Then a stitch longer than `maximum` is broken as a straight satin fill's is (`split`),
    /// or refused.
    private static func asSatin(_ sections:[[Point]],maximum:Double,split:Bool) throws ->[[Point]] {
        var shifted=false
        return try sections.map{section in
            var ends:[Point]=[]
            for p in section {
                if ends.count>=2,AreaGeometry.projection(ends[ends.count-1],ends[ends.count-2],p).distance(to:ends[ends.count-1])<0.01 {ends[ends.count-1]=p;continue}
                ends.append(p)
            }
            guard let first=ends.first else{return []}
            var sewn=[first]
            for (a,b) in zip(ends,ends.dropFirst()) {
                if a.distance(to:b)>maximum+0.0001 {
                    guard split else{throw DesignError.invalid("Satin fill stitches would be longer than \(String(format:"%.1f",maximum)) mm. Turn on Auto split, or make the shape narrower.")}
                    sewn+=SatinFill.breaks(a,b,maximum:maximum,shifted:shifted);shifted.toggle()
                }
                sewn.append(b)
            }
            return sewn
        }
    }
    /// A turning fill's rows (each piece sewn by `sew`), in parts sewn one after another. Without an end point, one
    /// part. With one, the shape is split along the row through the end point, as a straight fill is (see
    /// `topRows`): the piece holding the start point (without one, the biggest) is sewn first, finishing at that
    /// row, then each other piece from its far end back to the row, so the fill ends beside the end point and the
    /// travel out to a piece's far end is covered by the piece sewn over it. Each piece takes the cut as one more
    /// angle line, so its rows keep turning right up to it.
    private static func turningParts(in region:[[Point]],angleLines:[[Point]],entry:Point?,exit:Point?,start:Point?,
                                     sew:(_ region:[[Point]],_ lines:[[Point]],_ start:Point?,_ end:Point?) throws -> [[Point]]) throws -> [[[Point]]] {
        let whole=try sew(region,angleLines,start,nil)
        guard let exit,!whole.isEmpty else{return [whole]}
        // The row through the end point runs the way the stitch nearest it does.
        let stitches=whole.flatMap{zip($0,$0.dropFirst()).map{(a:$0,b:$1)}}.filter{$0.a.distance(to:$0.b)>=1}
        func gap(_ stitch:(a:Point,b:Point))->Double {AreaGeometry.projection(exit,stitch.a,stitch.b).distance(to:exit)}
        guard let nearest=stitches.min(by:{gap($0)<gap($1)}) else{return [whole]}
        let along=TurningFill.unit((a:nearest.a,b:nearest.b)),far=TurningFill.reach(across:region)
        guard let cut=TurningFill.stretches(in:region,angleLines:[[exit-along*far,exit+along*far]]).first?.first else{return [whole]}
        let pieces=try AreaGeometry.subtracting([TurningFill.slit(cut)],from:region).filter{abs(AreaGeometry.area($0[0]))>0.1}
        guard pieces.count>=2 else{return [whole]}
        let first=entry.flatMap{point in pieces.firstIndex{AreaGeometry.contains(point,rings:$0)}}
            ?? pieces.indices.max{abs(AreaGeometry.area(pieces[$0][0]))<abs(AreaGeometry.area(pieces[$1][0]))}!
        var parts:[[[Point]]]=[]
        for index in [first]+pieces.indices.filter({$0 != first}) {
            let piece=pieces[index]
            // The cut lies along this piece's edge, so it's nudged a touch inward to read as a line across the piece.
            let sideways=Point(-along.y,along.x)*0.02
            let inward=AreaGeometry.contains(TurningFill.mid(cut)+sideways,rings:piece) ? sideways:sideways*(-1)
            // The first piece sweeps from the start point; every other from its far end: all toward the cut.
            let farthest=piece[0].max{$0.distance(to:exit)<$1.distance(to:exit)}
            let rows=try sew(piece,angleLines+[[cut.a+inward,cut.b+inward]],index==first ? (entry ?? farthest):farthest,exit)
            if !rows.isEmpty {parts.append(rows)}
        }
        return parts.isEmpty ? [whole]:parts
    }
    /// The top-layer fill rows, in parts sewn one after another. Without start or end points: one part in the default
    /// order. With only a start point: the rows begin at the end nearest it. With an end point, the fill is split along
    /// the line through it that runs the way the rows do, and each side is sewn toward that line, so the last row lies
    /// right beside the end point and no travel crosses rows already sewn. The side holding the start point goes first.
    private static func topRows(in region:[[Point]],_ object:RunObject,entry:Point?,exit:Point?) throws -> [[[Point]]] {
        let s=object.settings
        let wave=s.fillStyle == .wave ? (height:s.waveHeight ?? DigitizingSettings.defaultWaveHeight,length:s.waveLength ?? DigitizingSettings.defaultWaveLength) : nil
        // Gradient fills: the rows' spacing grows from start to end across the whole shape, measured once here, so a
        // fill split in two by its end point still shades smoothly from one side to the other.
        let heightsAcross=region.flatMap{$0}.map{AreaGeometry.rotate($0,degrees:-s.angle).y}
        let gradient=s.fillStyle == .gradient ? (from:s.gradientStart ?? DigitizingSettings.defaultGradientStart,to:s.gradientEnd ?? DigitizingSettings.defaultGradientEnd,low:heightsAcross.min() ?? 0,high:heightsAcross.max() ?? 0) : nil
        /// Of the ways to sew `part` (from the sides in `fromTop`, the first row either way), the one with the lowest score.
        func best(_ part:[[Point]],fromTop:[Bool],_ score:([[Point]])->Double) throws -> [[Point]] {
            var best:(score:Double,rows:[[Point]])?
            for top in fromTop {
                for reversed in [false,true] {
                    let candidate=try rows(in:part,angle:s.angle,spacing:s.rowGap,length:object.stitchLength,fromTop:top,startReversed:reversed,wave:wave,gradient:gradient)
                    guard !candidate.isEmpty else{continue}
                    let value=score(candidate)
                    if best==nil || value<best!.score {best=(value,candidate)}
                }
            }
            return best?.rows ?? []
        }
        guard entry != nil || exit != nil else{return [try rows(in:region,angle:s.angle,spacing:s.rowGap,length:object.stitchLength,wave:wave,gradient:gradient)]}
        guard let exit else{return [try best(region,fromTop:[false,true]){$0[0][0].distance(to:entry!)}]}
        // The two sides of the line through the end point. Rows sew upward (fromTop false) on the side below it.
        // `far` is longer than any line across the shape, so each half covers the whole of its side.
        let points=region.flatMap{$0},far=2*(points.map{$0.distance(to:exit)}.max() ?? 1)+1
        let a=s.angle * .pi/180,along=Point(cos(a),sin(a)),across=Point(-sin(a),cos(a))
        func halfPlane(_ side:Double)->[Point] {[exit-along*far,exit+along*far,exit+along*far+across*(side*far),exit-along*far+across*(side*far)]}
        let below=try AreaGeometry.subtracting([halfPlane(1)],from:region).flatMap{$0}
        let above=try AreaGeometry.subtracting([halfPlane(-1)],from:region).flatMap{$0}
        var sides=[(region:below,fromTop:false),(region:above,fromTop:true)].filter{!$0.region.isEmpty}
        if let entry,sides.count==2,AreaGeometry.cross(along,entry-exit)>0 {sides.reverse()}   // the start point is above the line
        var parts:[[[Point]]]=[]
        for (index,side) in sides.enumerated() {
            let isLast=index==sides.count-1
            let part=try best(side.region,fromTop:[side.fromTop]){rows in
                (isLast ? rows.last!.last!.distance(to:exit):0)+(index==0 ? entry.map{rows[0][0].distance(to:$0)} ?? 0:0)
            }
            if !part.isEmpty {parts.append(part)}
        }
        return parts
    }
    struct Interval {var left:Double;var right:Double;var section:Int}
    /// `fromTop` sews rows from the far side of the fill angle first; `startReversed` flips which way the first row runs.
    /// With `wave`, each row ripples: the shape is first bent the opposite way (y − ripple(x), after turning the rows
    /// level), straight rows are laid in the bent shape, and bending them back turns them into waves that still fill
    /// the real shape edge to edge. The shape's edges are cut into short pieces first so they bend smoothly.
    /// `gradient`: rows from `low` to `high` (across the rows, after turning by `angle`) whose spacing grows steadily
    /// from `from` to `to`, instead of all `spacing` apart.
    public static func rows(in region:[[Point]],angle:Double,spacing:Double,length:Double,fromTop:Bool=false,startReversed:Bool=false,wave:(height:Double,length:Double)?=nil,
                            gradient:(from:Double,to:Double,low:Double,high:Double)?=nil) throws -> [[Point]] {
        var rings=region.map{$0.map{AreaGeometry.rotate($0,degrees:-angle)}}
        var ripple:(Double)->Double={_ in 0}
        if let wave,wave.height>0,wave.length>0 {
            ripple={x in wave.height/2*sin(2 * .pi*x/wave.length)}
            let piece=min(0.25,wave.length/40)
            rings=rings.map{ring in AreaGeometry.densified(ring,step:piece).map{Point($0.x,$0.y-ripple($0.x))}}
        }
        let points=rings.flatMap{$0}
        guard let minY=points.map(\.y).min(),let maxY=points.map(\.y).max(),let minX=points.map(\.x).min(),let maxX=points.map(\.x).max(),maxY-minY>0.0001 else{return []}
        // Where each row runs: evenly `spacing` apart, or for a gradient further apart the further across it is.
        var heights:[Double]=[]
        if let gradient,gradient.high>gradient.low {
            var y=gradient.low+gradient.from/2
            while y<gradient.high && heights.count<=20000 {
                if y>minY && y<maxY {heights.append(y)}
                let t=min(1,max(0,(y-gradient.low)/(gradient.high-gradient.low)))
                y+=gradient.from+(gradient.to-gradient.from)*t
            }
            if heights.isEmpty {heights=[(minY+maxY)/2]}
            if fromTop {heights.reverse()}
        } else {
            let count=max(1,Int(ceil((maxY-minY)/spacing))),step=(maxY-minY)/Double(count)
            heights=(0..<count).map{fromTop ? maxY-(Double($0)+0.5)*step : minY+(Double($0)+0.5)*step}
        }
        let rowCount=heights.count
        guard rowCount<=20000,Double(rowCount)*ceil((maxX-minX)/length+2)<1_000_000 else{throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.")}
        var sections:[[Point]]=[],previous:[Interval]=[],total=0
        for row in 0..<rowCount {
            try Task.checkCancellation()
            let y=heights[row]
            var intersections:[Double]=[]
            for ring in rings {for i in ring.indices {
                let a=ring[i],b=ring[(i+1)%ring.count]
                if (a.y<=y && b.y>y)||(b.y<=y && a.y>y) {intersections.append(a.x+(y-a.y)*(b.x-a.x)/(b.y-a.y))}
            }}
            intersections.sort()
            guard intersections.count%2==0 else{throw DesignError.invalid("Fill scanline could not resolve the outline.")}
            var current:[Interval]=[]
            for i in stride(from:0,to:intersections.count,by:2) where intersections[i+1]-intersections[i]>0.0001 {current.append(Interval(left:intersections[i],right:intersections[i+1],section:-1))}
            func overlaps(_ a:Interval,_ b:Interval)->Bool {min(a.right,b.right)-max(a.left,b.left)>0.0001}
            for index in current.indices {
                let interval=current[index],lo=interval.left,hi=interval.right
                // Stagger consecutive rows by quarters of a stitch length.
                var xs=[lo];var x=floor(lo/length)*length+Double(row%4)*length/4
                while x<=lo+0.00001{x+=length}
                while x<hi-0.00001{xs.append(x);x+=length};xs.append(hi)
                // No sliver under 0.3 mm at a row's ends: the grid point next to it moves halfway between its
                // neighbors, so the two end stitches share the length (neither tiny, neither over the stitch length).
                if xs.count>=3,xs[1]-xs[0]<0.3 {xs[1]=(xs[0]+xs[2])/2}
                if xs.count>=3,xs[xs.count-1]-xs[xs.count-2]<0.3 {xs[xs.count-2]=(xs[xs.count-3]+xs[xs.count-1])/2}
                if (row%2==1) != startReversed {xs.reverse()}
                let sewing=xs.map{Point($0,y)}
                let parents=previous.indices.filter{overlaps(previous[$0],interval)}
                var destination:Int?
                if parents.count==1 {
                    let parent=previous[parents[0]]
                    if current.filter({overlaps(parent,$0)}).count==1,
                       let end=sections[parent.section].last,
                       let route=AreaGeometry.boundaryRoute(end,sewing[0],rings:rings,longest:max(10,length*4)) {
                        // A wave's edge is cut into 0.25 mm pieces; skip corners closer than 0.3 mm so the step to the
                        // next row isn't a string of tiny stitches.
                        var corners=route
                        if wave != nil {corners=[route[0]];for p in route.dropFirst().dropLast() where p.distance(to:corners.last!)>=0.3 {corners.append(p)};corners.append(route.last!)}
                        let connection=AreaGeometry.sampled(corners,length:length)
                        sections[parent.section]+=connection.dropFirst();total+=connection.count-1
                        destination=parent.section
                    }
                }
                if destination==nil {destination=sections.count;sections.append([])}
                let section=destination!;current[index].section=section
                if sections[section].last==sewing.first {sections[section]+=sewing.dropFirst()} else {sections[section]+=sewing}
                total+=sewing.count
                guard total<=1_000_000 else{throw DesignError.invalid("Fill exceeds the one-million-stitch limit.")}
            }
            previous=current
        }
        return sections.filter{$0.count>=2}.map{$0.map{AreaGeometry.rotate(Point($0.x,$0.y+ripple($0.x)),degrees:angle)}}
    }

    private struct Arc {
        var points:[Point];var lengths:[Double];var length:Double{lengths.last ?? 0}
        init(_ points:[Point]) {self.points=points;lengths=[0];for (a,b) in zip(points,points.dropFirst()){lengths.append(lengths.last!+a.distance(to:b))}}
        func at(_ fraction:Double)->Point {
            let target=length*max(0,min(1,fraction));var low=0,high=lengths.count-1
            while low+1<high {let m=(low+high)/2;if lengths[m]<target{low=m}else{high=m}}
            let span=lengths[high]-lengths[low]
            return points[low]+(points[high]-points[low])*(span>0 ? (target-lengths[low])/span:0)
        }
    }
    /// Short stitches: on the inside of a curve the stitch ends crowd together, which piles thread into a hard
    /// ridge. Where one rail's ends are less than 60% as far apart as the other's, every other stitch stops a third
    /// of the way short of the crowded edge. Returns the rungs with those ends moved; the first and last never move.
    static func shortened(_ pairs:[(Point,Point)])->[(Point,Point)] {
        var result=pairs
        guard pairs.count>2 else{return result}
        for i in stride(from:1,to:pairs.count-1,by:2) {
            let leftGap=pairs[i-1].0.distance(to:pairs[i].0)+pairs[i].0.distance(to:pairs[i+1].0)
            let rightGap=pairs[i-1].1.distance(to:pairs[i].1)+pairs[i].1.distance(to:pairs[i+1].1)
            guard max(leftGap,rightGap)>0, min(leftGap,rightGap)<0.6*max(leftGap,rightGap) else{continue}
            let (l,r)=pairs[i]
            result[i]=leftGap<rightGap ? (l+(r-l)*(1.0/3),r) : (l,r+(l-r)*(1.0/3))
        }
        return result
    }
    /// Split satin: any stitch longer than `maximum` is broken into equal shorter stitches along the same line.
    /// Each long stitch shifts its break points half a step from the one before, so the breaks don't line up into
    /// a visible groove (they sit staggered, like bricks). Stitches already short enough are left alone.
    static func splitLong(_ points:[Point],maximum:Double)->[Point] {
        guard let first=points.first else{return points}
        var result=[first],stagger=false
        for (a,b) in zip(points,points.dropFirst()) {
            let length=a.distance(to:b)
            if length>maximum+0.0001 {
                let parts=Int(ceil(length/maximum))
                // Brick pattern: plain breaks at 1/n, 2/n …; staggered ones at 0.5/n, 1.5/n … (one more, shorter part).
                let fractions=stagger ? (0..<parts).map{(Double($0)+0.5)/Double(parts)} : (1..<parts).map{Double($0)/Double(parts)}
                result += fractions.map{a+(b-a)*$0}
                stagger.toggle()
            }
            result.append(b)
        }
        return result
    }
    /// True when two stitches cross in the middle half of both (between a quarter and three quarters of the way
    /// across each), as neighbouring stitches do where a satin column twists. Stitches that cross nearer an end, as
    /// they fan round a sharp corner, or don't cross at all, aren't a twist.
    /// How far (mm) a satin stitch may stray outside its column before it's refused. At a sharp turn, the stitches
    /// round the corner pass its tip by a few thousandths of a millimeter, which is nothing on fabric.
    static let strayAllowance=0.05
    static func crossInMiddle(_ a:(Point,Point),_ b:(Point,Point))->Bool {
        let u=a.1-a.0,v=b.1-b.0,den=AreaGeometry.cross(u,v)
        guard abs(den)>1e-12 else{return false}   // parallel
        let t=AreaGeometry.cross(b.0-a.0,v)/den,s=AreaGeometry.cross(b.0-a.0,u)/den   // how far across each the crossing is
        return (0.25...0.75).contains(t) && (0.25...0.75).contains(s)
    }
    public static func satin(_ object:RunObject) throws -> ObjectStitches {
        guard object.nodes.count>=(object.closed ? 6:4),object.nodes.count%2==0 else{throw DesignError.invalid(object.closed ? "A closed satin needs at least three complete left/right edge pairs." : "Satin needs at least two complete left/right edge pairs.")}
        let s=object.settings
        let left=object.nodes.enumerated().filter{$0.offset%2==0}.map(\.element),right=object.nodes.enumerated().filter{$0.offset%2==1}.map(\.element)
        // A closed satin (such as a border) goes all the way round: its last span joins the last pair back to the first.
        let leftSegments=RunningEngine.flatten(left,closed:object.closed),rightSegments=RunningEngine.flatten(right,closed:object.closed)
        func deduplicated(_ points:[Point])->[Point] {
            var ring:[Point]=[];for p in points where ring.last.map({$0.distance(to:p)>0.00001}) ?? true {ring.append(p)}
            if ring.count>1,ring.first!.distance(to:ring.last!)<0.00001 {ring.removeLast()}
            return ring
        }
        // The area the column covers. An open column is one outline: down the left rail and back up the right.
        // A closed column is a ring: the larger rail loop is the outside and the other is its hole.
        // Validate the actual curved rails, not a polygon that cuts their corners.
        let regionRings:[[Point]]
        if object.closed {
            regionRings=[deduplicated(leftSegments.flatMap{$0}),deduplicated(rightSegments.flatMap{$0})].sorted{abs(AreaGeometry.area($0))>abs(AreaGeometry.area($1))}
        } else {
            regionRings=[deduplicated(leftSegments.flatMap{$0}+rightSegments.flatMap{$0}.reversed())]
        }
        // Satins from embroidery fonts relax the checks meant for hand-drawn columns: font designers deliberately fan
        // stitches at column ends and let neighboring stitches overlap at tight turns. The stitch-length limit stays.
        let relaxed=s.relaxedChecks==true
        if !relaxed {try AreaGeometry.validate(regionRings)}
        // Stitches may stray a hair outside the column: at a sharp turn, the first stitches round it pass the inner
        // corner's tip by a few thousandths of a millimeter, which is nothing on fabric.
        let allowed=(try? AreaGeometry.offset(regionRings,by:strayAllowance)) ?? regionRings
        let usableArea=abs(AreaGeometry.area(regionRings[0]))-regionRings.dropFirst().reduce(0){$0+abs(AreaGeometry.area($1))}
        guard usableArea>0.01 else{throw DesignError.invalid("Satin rails have no usable area.")}
        var pairs:[(Point,Point)]=[],underPairs:[(Point,Point)]=[],warningNarrow=false,warningWide=false,warningCrowded=false
        var lastRung:(Point,Point)?   // the stitch before, rail to rail, without compensation
        var widthTotal=0.0,widthCount=0   // for the column's average width
        for span in leftSegments.indices {
            try Task.checkCancellation()
            let a=Arc(leftSegments[span]),b=Arc(rightSegments[span]),advance=(a.length+b.length)/2
            if relaxed && max(a.length,b.length)<0.000001 {continue}   // both rails stand still here: nothing to sew
            guard relaxed || min(a.length,b.length)>0.05 else{throw DesignError.invalid("Satin has a zero-length rail span. Move or remove that edge pair.")}
            let count=max(1,Int(ceil(advance/s.spacing)))
            guard pairs.count+count<5000 else{throw DesignError.invalid("This satin column exceeds 5,000 edge pairs. Split it into shorter columns.")}
            for i in 0...count where span==0 || i>0 {
                if i%32==0 {try Task.checkCancellation()}
                let l=a.at(Double(i)/Double(count)),r=b.at(Double(i)/Double(count)),width=l.distance(to:r)
                if relaxed && width<=0.05 {continue}   // where a fan's rails meet, there's no stitch to make
                guard width>0.05,relaxed || AreaGeometry.segmentInside(l,r,rings:allowed) else{throw DesignError.invalid("A satin direction rung crosses a rail. Reshape or split the column.")}
                warningNarrow = warningNarrow || width<1;warningWide = warningWide || width>7
                widthTotal+=width;widthCount+=1
                // Compensation: the base amount plus (with a percentage) a share of this stitch's own width.
                let pull=s.expansion+width*(s.pullPercent ?? 0)/100
                let direction=(r-l)*(1/width),cl=l-direction*pull,cr=r+direction*pull
                // A twisted column (left and right points swapped somewhere) makes neighbouring stitches cross in its
                // middle. Round a sharp corner they cross near the inner edge instead, fanning like a hand of cards,
                // which sews fine, so only a crossing in the middle is refused.
                if let previous=lastRung {
                    guard relaxed || !crossInMiddle(previous,(l,r)) else{throw DesignError.invalid("Satin rungs cross or reverse. Use consistent left/right pairs and split tight corners.")}
                }
                if let prior=pairs.last {warningCrowded = warningCrowded || min(prior.0.distance(to:cl),prior.1.distance(to:cr))<0.15}
                lastRung=(l,r)
                pairs.append((cl,cr))
            }
            let underCount=max(1,Int(ceil(advance/s.underlaySpacing)))
            for i in 0...underCount where span==0 || i>0 {underPairs.append((a.at(Double(i)/Double(underCount)),b.at(Double(i)/Double(underCount))))}
        }
        guard pairs.count>=2 else{throw DesignError.invalid("Satin rails have no usable area.")}
        // A closed column (a border) starts at the stitch pair nearest its start point (or its end point, when that's
        // the only one), and so does its underlay, wherever that falls between the border's corners.
        if object.closed,let start=object.entry ?? object.exit {
            pairs=rotatedRing(pairs,toward:start);underPairs=rotatedRing(underPairs,toward:start)
        }
        // The compensated column, which every top stitch must stay inside (give or take the same hair as above).
        let compensated=object.closed ? [deduplicated(pairs.map{$0.0}),deduplicated(pairs.map{$0.1})] : [pairs.map{$0.0}+pairs.reversed().map{$0.1}]
        let allowedCompensated=(try? AreaGeometry.offset(compensated,by:strayAllowance)) ?? compensated
        // Font satins always get short stitches (as Ink/Stitch, which the fonts were made for, does by default): on
        // their tight curves and fanned ends the needle holes otherwise pile up. Measured over every bundled font,
        // this cut needle-hole pile-ups by about a quarter.
        if s.shortStitches == true || relaxed {pairs=shortened(pairs)}
        // An end point part way along an open column: a single pass can only finish at an end, so the column is sewn
        // in two halves that meet there. The first runs from the start up to the end point; then the needle runs
        // hidden through the unsewn half to the far end, and the second half sews back to meet the first.
        var halves=[pairs]
        if !object.closed,object.satinEndsPartWay,let exit=object.exit,let k=meetingRung(exit,pairs) {halves=[Array(pairs[...k]),Array(pairs[(k+1)...].reversed())]}
        // A closed column with both points set ends at its end point the same way: first the longer way round from the
        // start to the end point, then (after a hidden run back through the shorter, unsewn way) the shorter way.
        if object.closed,object.entry != nil,let exit=object.exit,let split=ringHalves(exit,pairs) {halves=split}
        var tops:[[Point]]=[]
        for half in halves {
            var top:[Point]=[]
            for pair in half {top += [pair.0,pair.1]}
            if s.autoSplit == true {top=splitLong(top,maximum:s.maximumSatin)}
            guard zip(top,top.dropFirst()).allSatisfy({$0.distance(to:$1)<=s.maximumSatin+0.0001}) else{throw DesignError.invalid("Satin exceeds the \(String(format:"%.1f",s.maximumSatin)) mm stitch limit after compensation. Narrow or split the column, turn on Split wide satin, or use fill.")}
            for (index,segment) in zip(top,top.dropFirst()).enumerated() {
                if index%32==0 {try Task.checkCancellation()}
                guard relaxed || AreaGeometry.segmentInside(segment.0,segment.1,rings:allowedCompensated) else{throw DesignError.invalid("Satin stitches leave the column at a tight corner. Reshape or split it.")}
            }
            tops.append(top)
        }
        var result=ObjectStitches()
        if warningNarrow{result.warnings.append("Satin is narrower than 1 mm in places; check crowding during sew-out.")}
        if warningWide{result.warnings.append("Satin is wider than 7 mm in places; check loose or snag-prone stitches.")}
        if warningCrowded{result.warnings.append("Satin inner-edge points are crowded. Reshape or split tight corners.")}
        // The first underlay, then the second (if any), then the top stitches. The second sews backwards, so the
        // needle goes along the column, back, and along again for the top, with no long travel in between.
        // Auto picks them from the column's average width.
        let underlays=s.underlay == .auto ? DigitizingSettings.autoUnderlay(width:widthTotal/Double(max(1,widthCount)),stretchy:s.stretchyFabric == true) : (first:s.underlay,second:s.secondUnderlay)
        for (layer,style) in [underlays.first,underlays.second ?? UnderlayStyle.none].enumerated() {
            let sectionsBefore=result.sections.count
            switch style {
            case .center:
                let center=AreaGeometry.sampled(underPairs.map{($0.0+$0.1)*0.5},length:2.5)
                if relaxed || zip(center,center.dropFirst()).allSatisfy({AreaGeometry.segmentInside($0,$1,rings:regionRings)}) {result.sections.append(StitchSection(center,underlay:true))}
                else{result.warnings.append("Center underlay could not stay inside the column and was omitted.")}
            case .edge:
                let inset=try AreaGeometry.offset(regionRings,by:-s.inset)
                if inset.isEmpty{result.warnings.append("Inset edge underlay collapsed and was omitted.")}
                // Each ring starts at its point nearest the needle: the start of the column, or where the first
                // underlay ended (so the edge run begins at the end the satin sews from).
                let needle=result.sections.last?.points.last ?? underPairs.first.map{($0.0+$0.1)*0.5}
                func startNearNeedle(_ ring:[Point])->[Point] {
                    guard let needle,let k=ring.indices.min(by:{ring[$0].distance(to:needle)<ring[$1].distance(to:needle)}) else{return ring}
                    // A border's ring can have points only at its corners, so with a start point it starts at the
                    // nearest place along the ring, between them, to begin beside that point.
                    if object.closed && object.entry != nil {
                        var best=(index:0,point:ring[0],distance:Double.infinity)
                        for i in ring.indices {let q=AreaGeometry.projection(needle,ring[i],ring[(i+1)%ring.count]),d=q.distance(to:needle);if d<best.distance{best=(i,q,d)}}
                        return [best.point]+Array(ring[(best.index+1)...]+ring[...best.index])
                    }
                    return Array(ring[k...]+ring[..<k])
                }
                result.sections += inset.map{startNearNeedle($0)}.map{StitchSection(AreaGeometry.sampled($0+Array($0.prefix(1)),length:2.5),underlay:true)}
            case .zigzag:
                let inset=try AreaGeometry.offset(regionRings,by:-s.inset)
                var zig:[Point]=[],skippedInterior=false,pendingGap=false
                for pair in underPairs {
                    try Task.checkCancellation()
                    let intervals=AreaGeometry.clippedSegment(pair.0,pair.1,rings:inset)
                    // End rungs may lie outside the inset. A split rung is ambiguous;
                    // omit this underlay rather than sew across disconnected regions.
                    if intervals.isEmpty {if !zig.isEmpty{pendingGap=true};continue}
                    if pendingGap {skippedInterior=true;pendingGap=false}
                    guard intervals.count==1 else{zig=[];break}
                    let clipped=intervals[0]
                    zig.append(zig.count%2==0 ? clipped.0:clipped.1)
                }
                if skippedInterior {result.warnings.append("Zigzag underlay skips a narrow interior region; inspect coverage or split the column.")}
                if zig.count>=2,zip(zig,zig.dropFirst()).allSatisfy({AreaGeometry.segmentInside($0,$1,rings:inset)}) {result.sections.append(StitchSection(AreaGeometry.sampled(zig,length:2.5),underlay:true))}
                else{result.warnings.append("Inset zigzag underlay collapsed or left the column and was omitted.")}
            default:break
            }
            if layer==1 {for i in sectionsBefore..<result.sections.count {result.sections[i].points.reverse()}}
        }
        // Raised satin: padding under the top stitches, lanes of running stitch along the column about 0.7 mm apart
        // (inside its middle 80%), sewn back and forth, so the satin stands up over them.
        if s.raised == true {
            let lanes=max(2,Int((widthTotal/Double(max(1,widthCount)))/0.7))
            for lane in 0..<lanes {
                let share=0.1+0.8*Double(lane)/Double(lanes-1)
                var path=underPairs.map{$0.0+($0.1-$0.0)*share}
                if lane%2==1 {path.reverse()}
                result.sections.append(StitchSection(AreaGeometry.sampled(path,length:2.5),underlay:true))
            }
        }
        // The edges travel follows and the area it stays inside: the column, just inside its edge.
        let edges=(try? AreaGeometry.offset(regionRings,by:-0.25)).flatMap{$0.count==regionRings.count ? $0:nil} ?? regionRings
        let bounds=(try? AreaGeometry.offset(compensated,by:0.01)) ?? compensated
        let router=TravelRouter(edges:edges,bounds:bounds)
        for (index,top) in tops.enumerated() {
            // Between two halves the needle runs through the part not sewn yet, which the second half then covers, so
            // the run stays hidden however long it is (joining below only allows short runs once the top has begun).
            if index>0,let router,let from=tops[index-1].last,let to=top.first,let path=router.route(from:from,to:to) {
                let travel=router.travelStitches(path)
                if travel.count>1 {result.sections.append(StitchSection(travel,joined:true))}
            }
            result.sections.append(StitchSection(top))
        }
        // A start point part way along an open column: the needle starts there and runs along the column's middle to
        // the end it sews from, hidden under the stitches that follow.
        if !object.closed,let entry=object.entry,let lead=satinLeadIn(from:entry,center:underPairs.map{($0.0+$0.1)*0.5},region:regionRings) {
            result.sections.insert(StitchSection(lead,underlay:true),at:0)
        }
        // A closed column starts on its start point when that's inside it: one hidden stitch from there to where its
        // first stitches begin (the underlay runs beside the middle, not on it).
        if object.closed,let entry=object.entry,let first=result.sections.first?.points.first,entry.distance(to:first)>StitchEngine.smallestStitch,
           AreaGeometry.segmentInside(entry,first,rings:regionRings) {result.sections[0].points.insert(entry,at:0)}
        // The top layer starts back at the beginning of the column; travel there inside the column (the satin covers it).
        result.sections=router?.join(result.sections) ?? result.sections
        return result
    }
}

extension AreaEngine {
    /// The hidden run from a satin's start point to the start of its column: from `entry` (or, when that's outside
    /// the column, the nearest point on its middle line) along the middle line `center` back to its first point.
    /// Returns nil when the start point is within 1 mm of the column's start, measured along the middle line: the
    /// column then simply starts at its end, as it always did.
    /// A closed column's stitch pairs (its last pair repeats its first, closing the ring) turned to begin at the pair
    /// whose middle is nearest `point`, and still closed.
    static func rotatedRing(_ pairs:[(Point,Point)],toward point:Point) -> [(Point,Point)] {
        let closes=pairs.count>2 && pairs[0].0.distance(to:pairs.last!.0)<1e-6 && pairs[0].1.distance(to:pairs.last!.1)<1e-6
        let ring=closes ? Array(pairs.dropLast()):pairs
        guard let k=ring.indices.min(by:{((ring[$0].0+ring[$0].1)*0.5).distance(to:point)<((ring[$1].0+ring[$1].1)*0.5).distance(to:point)}),k>0 else{return pairs}
        let turned=Array(ring[k...]+ring[..<k])
        return closes ? turned+[turned[0]]:turned
    }
    /// A closed column (its pairs starting at the start point and closing back there) split into two halves that both
    /// finish beside `exit`: the longer way round first, then the shorter way. Nil when the end point is within 1 mm
    /// of the start, measured round the column's middle, or the ring is too small to split.
    static func ringHalves(_ exit:Point,_ pairs:[(Point,Point)]) -> [[(Point,Point)]]? {
        guard pairs.count>=6 else{return nil}
        let place=AreaGeometry.alongPath(exit,pairs.map{($0.0+$0.1)*0.5})
        guard place.along>1,place.total-place.along>1 else{return nil}
        let k=min(max(2,place.index),pairs.count-3)
        // Forward is pairs 0…k; backward runs from the last pair (the start again) down to k.
        return place.along>=place.total-place.along ? [Array(pairs[...k]),Array(pairs[(k+1)...].reversed())] : [Array(pairs[k...].reversed()),Array(pairs[..<k])]
    }
    /// Where a satin sewn in two halves meets: the index of the last stitch pair of the first half, the one nearest
    /// `exit` along the column's middle. Both halves keep at least two pairs; nil when the column is too short.
    static func meetingRung(_ exit:Point,_ pairs:[(Point,Point)]) -> Int? {
        guard pairs.count>=4 else{return nil}
        let along=AreaGeometry.alongPath(exit,pairs.map{($0.0+$0.1)*0.5})
        return min(max(1,along.index),pairs.count-3)
    }
    static func satinLeadIn(from entry:Point,center:[Point],region:[[Point]]) -> [Point]? {
        guard center.count>=2 else{return nil}
        // The nearest point on the middle line, and which piece of the line it's on.
        var nearest=(index:0,point:center[0],distance:Double.infinity)
        for i in center.indices.dropLast() {
            let q=AreaGeometry.projection(entry,center[i],center[i+1]),d=q.distance(to:entry)
            if d<nearest.distance {nearest=(i,q,d)}
        }
        let back=[nearest.point]+center[...nearest.index].reversed()
        guard zip(back,back.dropFirst()).reduce(0,{$0+$1.0.distance(to:$1.1)})>1 else{return nil}
        // Start right on the point when it's inside the column (and can step straight onto the middle line).
        let onPoint=AreaGeometry.segmentInside(entry,nearest.point,rings:region)
        return AreaGeometry.sampled((onPoint ? [entry]:[])+back,length:2.5)
    }
}

public enum StitchEngine {
    /// Stitches shorter than this (mm) break thread and tangle under the fabric, so they're merged into the next
    /// stitch, as most digitizing software does. Imported machine stitches are never changed.
    static let smallestStitch=0.3
    /// `points` without stitches shorter than `smallestStitch`: a point too close to the last one kept is left out.
    /// The first and last points always stay, so the stitches still start and end exactly where they did.
    static func withoutSmallStitches(_ points:[Point])->[Point] {
        guard points.count>2 else{return points}
        var kept=[points[0]]
        for p in points.dropFirst().dropLast() where p.distance(to:kept.last!)>=smallestStitch {kept.append(p)}
        // The end can't move, so if the point before it is too close, that point goes instead.
        if kept.count>1,points.last!.distance(to:kept.last!)<smallestStitch {kept.removeLast()}
        kept.append(points.last!)
        return kept
    }
    /// Total distance (mm) the needle travels without sewing: jumps between parts of the design.
    public static func travelLength(_ plan:StitchPlan) -> Double {
        var total=0.0,previous:Point?
        for command in plan.commands {
            if command.op == .jump,let p=previous{total+=p.distance(to:command.point)}
            if command.op == .stitch || command.op == .jump{previous=command.point}
        }
        return total
    }
    /// Auto Start & End: gives each sewable object (after the first) a start point where the previous object
    /// finishes sewing, so the needle travels less between parts. Objects are handled in sewing order, because
    /// moving one object's start changes where it ends. Locked, imported and unstitched objects are left alone,
    /// and only start points are set (end points you chose are kept). Returns the updated design.
    public static func autoStartPoints(_ design:Design) throws -> Design {
        var result=design
        for index in result.objects.indices.dropFirst() {
            try Task.checkCancellation()
            let object=result.objects[index]
            guard !object.locked,[.run,.satin,.fill].contains(object.kind) else{continue}
            // Where did sewing stand just before this object? (The last stitch of the objects before it.)
            var before=result;before.objects=Array(result.objects[..<index])
            guard let end=try compile(before).commands.last(where:{$0.op == .stitch})?.point else{continue}
            // Lettering is one object: only its first letter gets a start point (the whole word's start).
            if let id=object.lettering?.id {
                if result.objects.firstIndex(where:{$0.lettering?.id == id})==index {result.setLetteringStart(id,end)}
                continue
            }
            result.objects[index].entry=end
        }
        return result
    }
    /// An object's stitches worked out from its shape and settings, ignoring any edited by hand. `later` are the
    /// objects sewn after it (a fill set to cut out overlaps leaves out what they cover).
    public static func fresh(_ object:RunObject,under later:[RunObject]) throws -> ObjectStitches {
        switch object.kind {
        case .raw:throw DesignError.invalid("Imported stitch data is missing.")
        case .vector:return ObjectStitches()
        // sewingOrder() reorders nodes to honor a chosen start point; without one it returns the object unchanged.
        case .run:
            let ordered=object.sewingOrder(),s=object.settings,style=s.runStyle ?? .running
            // A line stitch style (zigzag, blanket…) is built along the line's path; plain running stitch (and bean
            // stitch, its repeated form) along the line's stitches.
            let path=RunningEngine.flatten(ordered.nodes,closed:ordered.closed).flatMap{$0}
            let styled=RunningStyles.stitches(style,along:path,closed:ordered.closed,width:s.runWidth ?? DigitizingSettings.defaultRunWidth(style),
                                              spacing:s.runSpacing ?? DigitizingSettings.defaultRunSpacing(style),length:object.stitchLength,motif:s.motif ?? .heart,
                                              target:s.radialCenter,lines:s.rippleLines ?? DigitizingSettings.defaultRippleLines)
            let line=try styled ?? RunningEngine.stitches(for:ordered)
            let sewn=styled != nil ? line : try RunningEngine.repeated(line,passes:s.runPasses ?? 1)
            var points=sewn
            // A start point part way along an open line: start there and run back along the line to its first end.
            if !object.closed,let entry=object.entry,let lead=RunningEngine.leadIn(along:line,from:entry) {points=lead+points.dropFirst()}
            // An end point part way along: after the line, come back along it through its own needle holes to the end
            // point (round a closed outline, whichever way is shorter).
            if let exit=object.exit,object.closed ? object.entry != nil : true,let tail=RunningEngine.tail(along:line,to:exit,closed:object.closed) {points+=tail}
            return ObjectStitches(sections:[StitchSection(points)])
        case .satin:return try AreaEngine.satin(object.sewingOrder())
        case .fill:
            guard object.settings.cutOutOverlaps == true else{return try AreaEngine.fill(object)}
            // Leave out what's sewn on top. If the cut can't be worked out, sew the whole fill and say so.
            do { return try OverlapCutout.fill(object,under:later) ?? AreaEngine.fill(object) }
            catch is CancellationError {throw CancellationError()}
            catch {var whole=try AreaEngine.fill(object);whole.warnings.append("\(object.name): overlaps couldn't be cut out (\(error.localizedDescription)); the whole fill sews.");return whole}
        }
    }
    public static func compile(_ design:Design) throws -> StitchPlan {
        try design.validate()
        var design=design
        if let box=design.bastingBox{design.objects.insert(box,at:0)}   // the basting box sews first, in the first thread
        var plan=StitchPlan(),last=Point(0,0);var previous:RunObject?
        /// True when the object at `index` hands straight on to the next one in its branch (Branching.swift): the
        /// next object is in the same branch and thread, and nothing stops the machine in between.
        func handsOn(_ index:Int)->Bool {
            guard let branch=design.objects[index].branchID,index+1<design.objects.count else{return false}
            let a=design.objects[index],b=design.objects[index+1]
            return b.branchID==branch && b.color==a.color && !a.stopAfter && b.rawStitches==nil && b.kind != .vector
        }
        var routers:[UUID:TravelRouter?]=[:]   // each branch's route finder, made the first time it's needed
        /// Where a lock stitch at the start of `path` goes: 0.6 mm along it (then the needle comes back to its start).
        /// The 0.6 mm is measured along the stitches (not just the first one), so a short first stitch doesn't shrink
        /// the lock into a sliver.
        func lockPoint(_ path:[Point])->Point {
            var anchor=path.last!,remaining=0.6
            for (a,b) in zip(path,path.dropFirst()) {let d=a.distance(to:b);if d>=remaining{anchor=a+(b-a)*(remaining/d);break};remaining-=d}
            return anchor
        }
        /// After an object whose trim is "When far": where its tie-off and trim begin in the plan, where its thread
        /// ended, and its thread. If the next object starts close by in the same thread, they're taken back off.
        var trimToReview:(from:Int,end:Point,color:ThreadColor)?
        let trimDistance=design.trimDistance ?? Design.defaultTrimDistance
        for (objectIndex,object) in design.objects.enumerated() {
            try Task.checkCancellation()
            if let raw=object.rawStitches {
                trimToReview=nil   // imported stitches start with their own jump, so the trim before them stays
                let thread:Int
                if let index=plan.threads.firstIndex(of:object.color){thread=index}else{thread=plan.threads.count;plan.threads.append(object.color)}
                func emit(_ op:StitchOperation,_ point:Point){plan.commands.append(StitchCommand(op,point,thread:thread,objectID:object.id))}
                guard plan.commands.count+raw.commands.count+5<=1_000_000 else{throw DesignError.invalid("This design exceeds the one-million-command limit.")}
                if let prior=previous,prior.color != object.color || raw.colorChangeBefore{emit(.colorChange,last)}
                // Anchor the source's incoming needle position so moving a block cannot
                // create a new sewn connection to an unrelated preceding object.
                if previous==nil || last.distance(to:raw.start)>0.00001 {emit(.jump,raw.start)}
                last=raw.start
                var longStitch=false
                for (index,c) in raw.commands.enumerated() {
                    if index%256==0{try Task.checkCancellation()}
                    if c.op == .stitch && last.distance(to:c.point)>10{longStitch=true}
                    emit(c.op,c.point);last=c.point
                }
                if longStitch{plan.warnings.append("\(object.name): imported stitches exceed 10 mm. Inspect length before export; imported stitches are never resampled.")}
                if object.trimAfter{
                    let from=plan.commands.count
                    emit(.trim,last)
                    if object.trimRule == .whenFar && !object.stopAfter{trimToReview=(from,last,object.color)}
                }
                if object.stopAfter{emit(.stop,last)}
                previous=object;continue
            }
            let generated:ObjectStitches
            // A guide line steers a guided fill and sews nothing itself.
            if object.kind == .vector {if object.guideFor == nil {plan.warnings.append("\(object.name): vector outline is unstitched and excluded from export.")};continue}
            do {
                // Stitches edited by hand sew instead, while they still match the object.
                if let edits=object.stitchEdits,object.hasCurrentStitchEdits {generated=edits.stitches}
                else {
                    // Remembered stitches are reused while the object is unchanged (StitchCache.swift).
                    let later=Array(design.objects[(objectIndex+1)...])
                    generated=try StitchCache.shared.stitches(for:object,under:later){try fresh(object,under:later)}
                }
            } catch is CancellationError {throw CancellationError()}
            catch {throw DesignError.invalid("\(object.name): \(error.localizedDescription)")}
            plan.warnings += generated.warnings.map{"\(object.name): \($0)"}
            // Stitches under 0.3 mm are merged away, including where a joined section (such as a travel run) begins
            // right next to where the one before it ended. A joined section left with one point joins the one before.
            var sections:[StitchSection]=[]
            for section in generated.sections where section.points.count>=2 {
                var s=section
                guard s.joined,let end=sections.last?.points.last else{s.points=withoutSmallStitches(s.points);sections.append(s);continue}
                s.points=Array(withoutSmallStitches([end]+s.points).dropFirst())
                if s.points.count>=2 {sections.append(s)} else {sections[sections.count-1].points=withoutSmallStitches(sections[sections.count-1].points+s.points)}
            }
            if sections.contains(where: { section in zip(section.points,section.points.dropFirst()).contains { $0.distance(to:$1)<0.3 } }) {
                plan.warnings.append("\(object.name): stitches shorter than 0.3 mm. Inspect corners and row ends before sewing.")
            }
            guard !sections.isEmpty else{
                // Nothing to sew, though the object before handed straight on to this one in a branch, leaving its
                // thread uncut. Unless this hands on in turn, tie off and trim after the object before.
                if objectIndex>0,handsOn(objectIndex-1),!handsOn(objectIndex),var end=plan.commands.last,end.op == .stitch {
                    let recent=Array(plan.commands.suffix(12).filter{$0.op == .stitch}.map(\.point).reversed())
                    if recent.count>=2{var lock=end;lock.point=lockPoint(recent);plan.commands+=[lock,end]}
                    end.op = .trim;plan.commands.append(end)
                    trimToReview=nil
                }
                continue
            }
            let thread:Int
            if let index=plan.threads.firstIndex(of:object.color){thread=index}else{thread=plan.threads.count;plan.threads.append(object.color)}
            func command(_ op:StitchOperation,_ p:Point,underlay:Bool=false)->StitchCommand{var c=StitchCommand(op,p,thread:thread,objectID:object.id);c.underlay=underlay ? true:nil;return c}
            if let prior=previous,prior.color != object.color{plan.commands.append(command(.colorChange,last))}
            var endFrom=plan.commands.count   // where the last section's tie-off begins
            for (index,section) in sections.enumerated() {
                let points=section.points
                guard plan.commands.count+points.count+10<=1_000_000 else{throw DesignError.invalid("This design exceeds the one-million-command limit.")}
                /// Lock stitches at the start of `path`: a stitch 0.6 mm along it and back.
                func tie(_ path:[Point]) {
                    plan.commands.append(command(.stitch,lockPoint(path),underlay:section.underlay));plan.commands.append(command(.stitch,path[0],underlay:section.underlay))
                }
                // A joined section carries straight on from the needle's position: no trim, jump or tie-in.
                let joined=index>0 && section.joined
                var travelled=false
                if index==0,objectIndex>0,handsOn(objectIndex-1),let branch=object.branchID {
                    // Carrying on from the object before in this branch: travel here inside the branch's shapes. With
                    // no route (or a long one), tie off and trim after all.
                    if routers[branch]==nil{routers[branch]=design.branchRouter(branch)}
                    if let router=routers[branch] ?? nil,let path=router.route(from:last,to:points[0]),AreaGeometry.pathLength(path)<=TravelRouter.maximumVisibleLength {
                        for p in router.travelStitches(path).dropFirst(){plan.commands.append(command(.stitch,p))}
                        travelled=true
                    } else {
                        let recent=Array(plan.commands.suffix(12).filter{$0.op == .stitch}.map(\.point).reversed())
                        if recent.count>=2{tie(recent)}
                        plan.commands.append(command(.trim,last))
                    }
                }
                if travelled {
                    if last.distance(to:points[0])>0.00001 && plan.commands.last?.point != points[0]{plan.commands.append(command(.stitch,points[0]))}
                } else if joined {
                    if last.distance(to:points[0])>0.00001{plan.commands.append(command(.stitch,points[0],underlay:section.underlay))}
                } else if index==0,let review=trimToReview,review.color==object.color,review.end.distance(to:points[0])<trimDistance {
                    // The object before ends close by in this thread, so the thread isn't cut: its tie-off and trim
                    // come off, a plain stitch carries the thread across, and no tie-in is needed.
                    plan.commands.removeSubrange(review.from...)
                    last=review.end
                    if last.distance(to:points[0])>0.00001{plan.commands.append(command(.stitch,points[0],underlay:section.underlay))}
                } else {
                    if index>0{plan.commands.append(command(.trim,last))}
                    if previous==nil || index>0 || last.distance(to:points[0])>0.00001{plan.commands.append(command(.jump,points[0]))}
                    plan.commands.append(command(.stitch,points[0],underlay:section.underlay))
                    if object.tieIn{tie(points)}
                }
                for (i,p) in points.dropFirst().enumerated(){if i%256==0{try Task.checkCancellation()};plan.commands.append(command(.stitch,p,underlay:section.underlay))}
                last=points.last!
                // Tie off only where the thread will be cut: before a trim, or at the end of the object.
                let continues=index+1<sections.count && sections[index+1].joined
                trimToReview=nil
                if index==sections.count-1{endFrom=plan.commands.count}
                if object.tieOut && !continues && !(index==sections.count-1 && handsOn(objectIndex)){tie(points.reversed())}
            }
            if object.trimAfter && !handsOn(objectIndex){
                plan.commands.append(command(.trim,last))
                if object.trimRule == .whenFar && !object.stopAfter{trimToReview=(endFrom,last,object.color)}
            }
            if object.stopAfter{plan.commands.append(command(.stop,last))}
            previous=object
        }
        plan.commands.append(.init(.end,last,thread:max(0,plan.threads.count-1)))
        if plan.outsidePoints.contains(where:{!design.hoop.contains($0)}){plan.warnings.append("The design extends beyond the sewing area after compensation. Resize or reposition it before export.")}
        return plan
    }
}
