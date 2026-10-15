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
        if s.underlay != .none {
            // Underlay is inset from the source, never expanded a second time.
            let inset=try AreaGeometry.offset(original,by:-s.inset)
            if inset.isEmpty {result.warnings.append("Underlay collapsed at the chosen inset; no underlay was generated.")}
            else {
                // With a start point, each underlay outline begins at its corner nearest that point.
                func startNearEntry(_ ring:[Point])->[Point] {
                    guard let entry=object.entry,let k=ring.indices.min(by:{ring[$0].distance(to:entry)<ring[$1].distance(to:entry)}) else{return ring}
                    return Array(ring[k...]+ring[..<k])
                }
                result.sections += inset.map{startNearEntry($0)}.map{StitchSection(AreaGeometry.sampled($0+Array($0.prefix(1)),length:2.5),underlay:true)}
                if s.underlay == .edgeAndSparse {
                    result.sections += try rows(in:inset,angle:s.angle+90,spacing:s.underlaySpacing,length:2.5).filter(isLongEnough).map{StitchSection($0,underlay:true)}
                }
            }
        }
        let style=s.fillStyle ?? .tatami
        var top:[[Point]]
        // Without a start point, contour and radial fills begin where the underlay finished, so no long travel is needed.
        let start=object.entry ?? result.sections.last?.points.last
        switch style {
        case .tatami where !(s.angleLines ?? []).isEmpty:
            top=try TurningFill.rows(in:expanded,angleLines:s.angleLines!,spacing:s.spacing,length:object.stitchLength,start:start)
            guard !top.isEmpty else{throw DesignError.invalid("The stitch angle lines don't cross this fill. Draw them across it, or remove them.")}
        case .tatami,.wave:top=try topRows(in:expanded,object)
        case .contour:top=try FillStyles.contour(in:expanded,spacing:s.spacing,length:object.stitchLength,start:start)
        case .radial:top=try FillStyles.radial(in:expanded,center:s.radialCenter ?? AreaGeometry.centroid(original[0]),spacing:s.spacing,length:object.stitchLength,start:start)
        }
        top=top.filter(isLongEnough)
        guard !top.isEmpty else{throw DesignError.invalid("This fill is too small for the selected row spacing.")}
        // Travel between sections follows rings just inside the shape's edge (the edge itself if that inset collapses).
        let edges=(try? AreaGeometry.offset(original,by:-0.25)).flatMap{$0.count==original.count ? $0:nil} ?? original
        // A 0.01 mm margin keeps row ends, which lie exactly on the edge, reliably "inside" for routing. Wave row ends
        // can sit a few thousandths of a millimeter further out (the edge is bent back in short pieces), so they get 0.05 mm.
        let bounds=(try? AreaGeometry.offset(expanded,by:style == .wave ? 0.05:0.01)) ?? expanded
        // Contour, radial and turning stitches run every which way, so travel across them is priced like satin (no
        // row angle), and their rows already come in sewing order.
        let rowStyle=(style == .tatami && (s.angleLines ?? []).isEmpty) || style == .wave
        let router=TravelRouter(edges:edges,bounds:bounds,rowAngle:rowStyle ? s.angle:nil)
        // Sew the top sections in the order (and from the ends) that keep travel shortest. The first section stays
        // first (it honors the start point); with an end point, the last stays last. Contour and radial sections
        // already come in sewing order.
        let topSections=top.map{StitchSection($0)}
        result.sections += rowStyle ? router?.ordered(topSections,keepingLast:object.exit != nil) ?? topSections : topSections
        result.sections=router?.join(result.sections) ?? result.sections
        let trims=result.sections.dropFirst().filter{!$0.joined}.count
        if trims>0 {result.warnings.append("Fill needs \(trims) trim\(trims==1 ? "":"s") between sections that no short path inside the shape connects.")}
        return result
    }
    /// False for a scrap of a row (clipped at a sharp corner) too short to make one stitch: it would sew as a single
    /// stitch under 0.3 mm and hold nothing, so it's left out.
    private static func isLongEnough(_ row:[Point])->Bool {AreaGeometry.pathLength(row)>=StitchEngine.smallestStitch}
    /// The top-layer fill rows in the default order, or, when the object has a start or end point, the one of four
    /// orders (rows from the bottom or top, first row left-to-right or right-to-left) whose first and last
    /// stitches land closest to those points.
    private static func topRows(in region:[[Point]],_ object:RunObject) throws -> [[Point]] {
        let s=object.settings
        let wave=s.fillStyle == .wave ? (height:s.waveHeight ?? DigitizingSettings.defaultWaveHeight,length:s.waveLength ?? DigitizingSettings.defaultWaveLength) : nil
        guard object.entry != nil || object.exit != nil else{return try rows(in:region,angle:s.angle,spacing:s.spacing,length:object.stitchLength,wave:wave)}
        var best:(score:Double,rows:[[Point]])?
        for fromTop in [false,true] {
            for startReversed in [false,true] {
                let candidate=try rows(in:region,angle:s.angle,spacing:s.spacing,length:object.stitchLength,fromTop:fromTop,startReversed:startReversed,wave:wave)
                guard let first=candidate.first?.first,let last=candidate.last?.last else{continue}
                let score=(object.entry.map{first.distance(to:$0)} ?? 0)+(object.exit.map{last.distance(to:$0)} ?? 0)
                if best==nil || score<best!.score {best=(score,candidate)}
            }
        }
        return best?.rows ?? []
    }
    struct Interval {var left:Double;var right:Double;var section:Int}
    /// `fromTop` sews rows from the far side of the fill angle first; `startReversed` flips which way the first row runs.
    /// With `wave`, each row ripples: the shape is first bent the opposite way (y − ripple(x), after turning the rows
    /// level), straight rows are laid in the bent shape, and bending them back turns them into waves that still fill
    /// the real shape edge to edge. The shape's edges are cut into short pieces first so they bend smoothly.
    public static func rows(in region:[[Point]],angle:Double,spacing:Double,length:Double,fromTop:Bool=false,startReversed:Bool=false,wave:(height:Double,length:Double)?=nil) throws -> [[Point]] {
        var rings=region.map{$0.map{AreaGeometry.rotate($0,degrees:-angle)}}
        var ripple:(Double)->Double={_ in 0}
        if let wave,wave.height>0,wave.length>0 {
            ripple={x in wave.height/2*sin(2 * .pi*x/wave.length)}
            let piece=min(0.25,wave.length/40)
            rings=rings.map{ring in AreaGeometry.densified(ring,step:piece).map{Point($0.x,$0.y-ripple($0.x))}}
        }
        let points=rings.flatMap{$0}
        guard let minY=points.map(\.y).min(),let maxY=points.map(\.y).max(),let minX=points.map(\.x).min(),let maxX=points.map(\.x).max(),maxY-minY>0.0001 else{return []}
        let rowCount=max(1,Int(ceil((maxY-minY)/spacing)))
        guard rowCount<=20000,Double(rowCount)*ceil((maxX-minX)/length+2)<1_000_000 else{throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.")}
        let step=(maxY-minY)/Double(rowCount)
        var sections:[[Point]]=[],previous:[Interval]=[],total=0
        for row in 0..<rowCount {
            try Task.checkCancellation()
            let y=fromTop ? maxY-(Double(row)+0.5)*step : minY+(Double(row)+0.5)*step
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
        // The compensated column, which every top stitch must stay inside (give or take the same hair as above).
        let compensated=object.closed ? [deduplicated(pairs.map{$0.0}),deduplicated(pairs.map{$0.1})] : [pairs.map{$0.0}+pairs.reversed().map{$0.1}]
        let allowedCompensated=(try? AreaGeometry.offset(compensated,by:strayAllowance)) ?? compensated
        // Font satins always get short stitches (as Ink/Stitch, which the fonts were made for, does by default): on
        // their tight curves and fanned ends the needle holes otherwise pile up. Measured over every bundled font,
        // this cut needle-hole pile-ups by about a quarter.
        if s.shortStitches == true || relaxed {pairs=shortened(pairs)}
        var top:[Point]=[]
        for pair in pairs {top += [pair.0,pair.1]}
        if s.autoSplit == true {top=splitLong(top,maximum:s.maximumSatin)}
        guard zip(top,top.dropFirst()).allSatisfy({$0.distance(to:$1)<=s.maximumSatin+0.0001}) else{throw DesignError.invalid("Satin exceeds the \(String(format:"%.1f",s.maximumSatin)) mm stitch limit after compensation. Narrow or split the column, turn on Split wide satin, or use fill.")}
        for (index,segment) in zip(top,top.dropFirst()).enumerated() {
            if index%32==0 {try Task.checkCancellation()}
            guard relaxed || AreaGeometry.segmentInside(segment.0,segment.1,rings:allowedCompensated) else{throw DesignError.invalid("Satin stitches leave the column at a tight corner. Reshape or split it.")}
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
        result.sections.append(StitchSection(top))
        // The top layer starts back at the beginning of the column; travel there inside the column (the satin covers it).
        let edges=(try? AreaGeometry.offset(regionRings,by:-0.25)).flatMap{$0.count==regionRings.count ? $0:nil} ?? regionRings
        let bounds=(try? AreaGeometry.offset(compensated,by:0.01)) ?? compensated
        result.sections=TravelRouter(edges:edges,bounds:bounds)?.join(result.sections) ?? result.sections
        return result
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
        case .run:return ObjectStitches(sections:[StitchSection(try RunningEngine.repeated(RunningEngine.stitches(for:object.sewingOrder()),passes:object.settings.runPasses ?? 1))])
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
        for (objectIndex,object) in design.objects.enumerated() {
            try Task.checkCancellation()
            if let raw=object.rawStitches {
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
                if object.trimAfter{emit(.trim,last)}
                if object.stopAfter{emit(.stop,last)}
                previous=object;continue
            }
            let generated:ObjectStitches
            if object.kind == .vector {plan.warnings.append("\(object.name): vector outline is unstitched and excluded from export.");continue}
            do {
                // Stitches edited by hand sew instead, while they still match the object.
                if let edits=object.stitchEdits,object.hasCurrentStitchEdits {generated=edits.stitches}
                else {generated=try fresh(object,under:Array(design.objects[(objectIndex+1)...]))}
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
                }
                continue
            }
            let thread:Int
            if let index=plan.threads.firstIndex(of:object.color){thread=index}else{thread=plan.threads.count;plan.threads.append(object.color)}
            func command(_ op:StitchOperation,_ p:Point,underlay:Bool=false)->StitchCommand{var c=StitchCommand(op,p,thread:thread,objectID:object.id);c.underlay=underlay ? true:nil;return c}
            if let prior=previous,prior.color != object.color{plan.commands.append(command(.colorChange,last))}
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
                if object.tieOut && !continues && !(index==sections.count-1 && handsOn(objectIndex)){tie(points.reversed())}
            }
            if object.trimAfter && !handsOn(objectIndex){plan.commands.append(command(.trim,last))}
            if object.stopAfter{plan.commands.append(command(.stop,last))}
            previous=object
        }
        plan.commands.append(.init(.end,last,thread:max(0,plan.threads.count-1)))
        if plan.outsidePoints.contains(where:{!design.hoop.contains($0)}){plan.warnings.append("The design extends beyond the sewing area after compensation. Resize or reposition it before export.")}
        return plan
    }
}
