import Foundation
import GeometryBridge

public enum AreaGeometry {
    public static func cross(_ a: Point, _ b: Point) -> Double { a.x*b.y-a.y*b.x }
    public static func rotate(_ p: Point, degrees: Double) -> Point {
        let r=degrees * .pi/180; return Point(p.x*cos(r)-p.y*sin(r),p.x*sin(r)+p.y*cos(r))
    }
    public static func ring(_ nodes: [PathNode]) -> [Point] {
        var result: [Point]=[]
        for p in RunningEngine.flatten(nodes,closed:true).flatMap({$0}) where result.last.map({$0.distance(to:p)>0.00001}) ?? true { result.append(p) }
        if result.count>1, result.first!.distance(to:result.last!)<0.00001 { result.removeLast() }
        return result
    }
    public static func area(_ ring: [Point]) -> Double {
        guard ring.count>=3 else{return 0}; return ring.indices.reduce(0){$0+cross(ring[$1],ring[($1+1)%ring.count])}/2
    }
    /// The point on the open polyline `path` nearest `p`: which piece it's on (the index of the piece's first point),
    /// how far along the path it is, and the path's whole length (mm).
    public static func alongPath(_ p: Point, _ path: [Point]) -> (index: Int, along: Double, total: Double) {
        var best = (index: 0, along: 0.0, distance: Double.infinity), walked = 0.0
        for i in path.indices.dropLast() {
            let q = projection(p, path[i], path[i + 1]), d = q.distance(to: p)
            if d < best.distance { best = (i, walked + path[i].distance(to: q), d) }
            walked += path[i].distance(to: path[i + 1])
        }
        return (best.index, best.along, walked)
    }
    public static func projection(_ p: Point, _ a: Point, _ b: Point) -> Point {
        let v=b-a, d=v.x*v.x+v.y*v.y
        let t=d>0 ? max(0,min(1,((p-a).x*v.x+(p-a).y*v.y)/d)):0
        return a+v*t
    }
    public static func contains(_ p: Point, rings: [[Point]]) -> Bool {
        var inside=false
        for ring in rings where ring.count>=3 {
            for i in ring.indices {
                let a=ring[i],b=ring[(i+1)%ring.count]
                if p.distance(to:projection(p,a,b))<0.00001{return true}
                if (a.y>p.y) != (b.y>p.y), p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x {inside.toggle()}
            }
        }
        return inside
    }
    public static func intersects(_ a: Point,_ b: Point,_ c: Point,_ d: Point) -> Bool {
        let u=b-a,v=d-c,den=cross(u,v)
        if abs(den)<1e-10 {return a.distance(to:projection(a,c,d))<1e-7 || b.distance(to:projection(b,c,d))<1e-7 || c.distance(to:projection(c,a,b))<1e-7 || d.distance(to:projection(d,a,b))<1e-7}
        let t=cross(c-a,v)/den,s=cross(c-a,u)/den
        return t>=(-1e-8) && t<=1+1e-8 && s>=(-1e-8) && s<=1+1e-8
    }
    public static func validate(_ rings: [[Point]]) throws {
        guard !rings.isEmpty, rings.flatMap({$0}).count<=4000 else {throw DesignError.invalid("Area geometry is too complex. Use fewer curve points or split the object.")}
        for ring in rings {
            guard ring.count>=3,abs(area(ring))>0.01 else {throw DesignError.invalid("The outline collapses to a line or is too small.")}
            for i in ring.indices {
                if i%32==0 {try Task.checkCancellation()}
                for j in (i+1)..<ring.count where j != i+1 && !(i==0 && j==ring.count-1) {
                    if intersects(ring[i],ring[(i+1)%ring.count],ring[j],ring[(j+1)%ring.count]) {throw DesignError.invalid("Outline edges cross or touch. Reshape the nodes before sewing.")}
                }
            }
        }
        for i in rings.indices.dropFirst() {
            guard contains(rings[i][0],rings:[rings[0]]) else {throw DesignError.invalid("A hole lies outside its fill outline.")}
            for j in 0..<i {
                if j>0 && (contains(rings[i][0],rings:[rings[j]]) || contains(rings[j][0],rings:[rings[i]])) {throw DesignError.invalid("Holes overlap or nest. Use separate, non-overlapping holes.")}
                for a in rings[i].indices {
                    try Task.checkCancellation()
                    for b in rings[j].indices where intersects(rings[i][a],rings[i][(a+1)%rings[i].count],rings[j][b],rings[j][(b+1)%rings[j].count]) {throw DesignError.invalid("A hole touches or crosses another boundary.")}
                }
            }
        }
    }
    /// `rings` grown by `amount` mm (shrunk when it's below zero), with rounded corners, or pointed ones when `sharp`
    /// (very narrow corners are flattened rather than making long spikes). The geometry library
    /// offsets at most 10 mm at a time; offsetting in steps that add up to `amount` gives the same shape (a
    /// flattened sharp tip may come out a little different), so larger amounts go in steps.
    public static func offset(_ rings: [[Point]], by amount: Double, sharp: Bool = false) throws -> [[Point]] {
        let steps = max(1, Int(ceil(abs(amount) / 10)))
        var result = rings
        for _ in 0..<steps where !result.isEmpty { result = try resolvedPaths(result,by:amount/Double(steps),nonzero:nil,sharp:sharp).rings }
        return result
    }
    /// Preserve Clipper's topology rather than infer containment from boundary vertices.
    static func svgRegions(_ rings:[[Point]],nonzero:Bool)throws->[[[Point]]] {
        let result=try resolvedPaths(rings,by:0,nonzero:nonzero)
        var depths=[Int](repeating:0,count:result.rings.count),regions:[[[Point]]]=[]
        for i in result.rings.indices {
            let parent=result.parents[i]
            if parent>=0 {depths[i]=depths[parent]+1}
            if depths[i]%2==0 {
                regions.append([result.rings[i]]+result.rings.indices.filter{result.parents[$0]==i}.map{result.rings[$0]})
            }
        }
        return regions
    }
    /// `rings` (an outline and its holes) with the area of `cut` (another outline and its holes) taken away. Returns
    /// the pieces left, each as its outer ring followed by its holes; empty if nothing is left.
    public static func subtracting(_ cut:[[Point]],from rings:[[Point]]) throws -> [[[Point]]] {
        try Task.checkCancellation()
        guard !rings.isEmpty else{return []}
        guard !cut.isEmpty else{return [rings]}
        let a=rings.flatMap{$0.flatMap{[$0.x,$0.y]}},aCounts=rings.map{Int32($0.count)}
        let b=cut.flatMap{$0.flatMap{[$0.x,$0.y]}},bCounts=cut.map{Int32($0.count)}
        let output=a.withUnsafeBufferPointer{ax in aCounts.withUnsafeBufferPointer{an in b.withUnsafeBufferPointer{bx in bCounts.withUnsafeBufferPointer{bn in
            eg_difference(ax.baseAddress,an.baseAddress,Int32(aCounts.count),bx.baseAddress,bn.baseAddress,Int32(bCounts.count))}}}}
        defer{eg_free_paths(output)}
        guard output.error==0 else{throw DesignError.invalid("The overlap cut-out could not be worked out (\(output.error)). Simplify the shapes.")}
        guard output.path_count>0,let coordinates=output.xy,let sizes=output.counts,let parents=output.parents else{return []}
        var result:[[Point]]=[],cursor=0
        for i in 0..<Int(output.path_count) {
            var ring:[Point]=[]
            for _ in 0..<Int(sizes[i]) {ring.append(Point(coordinates[cursor],coordinates[cursor+1]));cursor+=2}
            result.append(ring)
        }
        // Rings at even depth are outlines; each takes its direct children (odd depth) as its holes.
        var depths=[Int](repeating:0,count:result.count),pieces:[[[Point]]]=[]
        for i in result.indices {
            let parent=Int(parents[i])
            if parent>=0 {depths[i]=depths[parent]+1}
            if depths[i]%2==0 {pieces.append([result[i]]+result.indices.filter{Int(parents[$0])==i}.map{result[$0]})}
        }
        return pieces
    }
    private static func resolvedPaths(_ rings:[[Point]],by amount:Double,nonzero:Bool?,sharp:Bool=false)throws->(rings:[[Point]],parents:[Int]) {
        try Task.checkCancellation()
        guard !rings.isEmpty else{return ([],[])}
        guard rings.count<=1024 else{throw DesignError.invalid("A compound outline has more than 1,024 subpaths. Split it into smaller objects before importing.")}
        let xy=rings.flatMap{$0.flatMap{[$0.x,$0.y]}},counts=rings.map{Int32($0.count)}
        let output=xy.withUnsafeBufferPointer{x in counts.withUnsafeBufferPointer{n in (nonzero.map{eg_resolve(x.baseAddress,n.baseAddress,Int32(counts.count),$0 ? 1:0)} ?? (sharp ? eg_offset_sharp : eg_offset)(x.baseAddress,n.baseAddress,Int32(counts.count),amount))}}
        defer{eg_free_paths(output)}
        guard output.error==0 else{throw DesignError.invalid("The polygon geometry could not be generated (\(output.error)). Simplify or split the outline.")}
        try Task.checkCancellation()
        guard output.path_count>0,let coordinates=output.xy,let sizes=output.counts else{return ([],[])}
        var result:[[Point]]=[],parents:[Int]=[],cursor=0
        for i in 0..<Int(output.path_count) {
            var ring:[Point]=[]
            for _ in 0..<Int(sizes[i]) {ring.append(Point(coordinates[cursor],coordinates[cursor+1]));cursor+=2}
            result.append(ring);parents.append(output.parents.map{Int($0[i])} ?? -1)
        }
        return (result,parents)
    }
    /// Split at every boundary intersection and test each interval, not just the midpoint.
    public static func segmentInside(_ a:Point,_ b:Point,rings:[[Point]]) -> Bool {
        guard contains(a,rings:rings),contains(b,rings:rings) else{return false}
        let u=b-a; var cuts=[0.0,1.0]
        let squared=u.x*u.x+u.y*u.y
        if squared<1e-16{return true}
        for ring in rings {for i in ring.indices {
            let c=ring[i],d=ring[(i+1)%ring.count],v=d-c,den=cross(u,v)
            if abs(den)>1e-10 {
                let t=cross(c-a,v)/den,s=cross(c-a,u)/den
                if t>0 && t<1 && s>=0 && s<=1 {cuts.append(t)}
            } else if abs(cross(c-a,u))<1e-8 {
                for p in [c,d] {let t=((p-a).x*u.x+(p-a).y*u.y)/squared;if t>0 && t<1 {cuts.append(t)}}
            }
        }}
        cuts.sort()
        return zip(cuts,cuts.dropFirst()).allSatisfy{contains(a+u*(($0+$1)/2),rings:rings)}
    }
    /// Intersect a direction rung with an inset region, retaining each interior interval.
    public static func clippedSegment(_ a:Point,_ b:Point,rings:[[Point]]) -> [(Point,Point)] {
        let u=b-a,squared=u.x*u.x+u.y*u.y
        guard squared>1e-16 else{return []}
        var cuts=[0.0,1.0]
        for ring in rings {for i in ring.indices {
            let c=ring[i],d=ring[(i+1)%ring.count],v=d-c,den=cross(u,v)
            if abs(den)>1e-10 {
                let t=cross(c-a,v)/den,s=cross(c-a,u)/den
                if t>0 && t<1 && s>=(-1e-8) && s<=1+1e-8 {cuts.append(t)}
            } else if abs(cross(c-a,u))<1e-8 {
                for p in [c,d] {let t=((p-a).x*u.x+(p-a).y*u.y)/squared;if t>0 && t<1{cuts.append(t)}}
            }
        }}
        cuts.sort()
        var intervals:[(Double,Double)]=[]
        for (lo,hi) in zip(cuts,cuts.dropFirst()) where hi-lo>1e-8 {
            if contains(a+u*((lo+hi)/2),rings:rings) {
                if let last=intervals.last,abs(last.1-lo)<1e-8 {intervals[intervals.count-1].1=hi}
                else {intervals.append((lo,hi))}
            }
        }
        return intervals.map{(a+u*$0.0,a+u*$0.1)}
    }
    public static func sampled(_ points:[Point],length:Double) -> [Point] {
        guard let first=points.first else{return []};var result=[first]
        for (a,b) in zip(points,points.dropFirst()) {
            let n=max(1,Int(ceil(a.distance(to:b)/length)))
            for i in 1...n {let p=a+(b-a)*(Double(i)/Double(n));if result.last!.distance(to:p)>0.00001{result.append(p)}}
        }
        return result
    }
    /// The shortest way from `a` to `b` (both on the same ring's edge) that stays inside the shape: straight across,
    /// or along the edge one way round or the other. A way longer than `longest` mm is given up on as soon as it's
    /// that long, so a caller that only wants short routes doesn't pay for checking ones all the way round.
    public static func boundaryRoute(_ a:Point,_ b:Point,rings:[[Point]],longest:Double = .infinity) -> [Point]? {
        if segmentInside(a,b,rings:rings){return a.distance(to:b)<=longest ? [a,b]:nil}
        for ring in rings {
            guard let ai=ring.indices.first(where:{a.distance(to:projection(a,ring[$0],ring[($0+1)%ring.count]))<0.001}),
                  let bi=ring.indices.first(where:{b.distance(to:projection(b,ring[$0],ring[($0+1)%ring.count]))<0.001}) else{continue}
            // Each way round, unless it gets longer than `longest` on the way (then it's left out altogether).
            var ways:[[Point]]=[]
            for (start,end,step) in [((ai+1)%ring.count,(bi+1)%ring.count,1),(ai,bi,ring.count-1)] {
                var path=[a],index=start,length=0.0
                while index != end, length<=longest {length+=path.last!.distance(to:ring[index]);path.append(ring[index]);index=(index+step)%ring.count}
                path.append(b)
                if index==end, pathLength(path)<=longest {ways.append(path)}
            }
            let valid=ways.filter{path in zip(path,path.dropFirst()).allSatisfy{segmentInside($0,$1,rings:rings)}}
            return valid.min{pathLength($0)<pathLength($1)}
        }
        return nil
    }
    /// A closed ring with extra points added so no edge is longer than `step`.
    public static func densified(_ ring:[Point],step:Double) -> [Point] {
        var result:[Point]=[]
        for i in ring.indices {
            let a=ring[i],b=ring[(i+1)%ring.count],n=max(1,Int(ceil(a.distance(to:b)/step)))
            for k in 0..<n {result.append(a+(b-a)*(Double(k)/Double(n)))}
        }
        return result
    }
    /// The balance point of a ring's area (where a cut-out of it would balance on a pin).
    public static func centroid(_ ring:[Point]) -> Point {
        var x=0.0,y=0.0,twiceArea=0.0
        for i in ring.indices {
            let a=ring[i],b=ring[(i+1)%ring.count],c=cross(a,b)
            x+=(a.x+b.x)*c;y+=(a.y+b.y)*c;twiceArea+=c
        }
        guard abs(twiceArea)>1e-12 else{return ring.reduce(Point(0,0),+)*(1/Double(max(1,ring.count)))}
        return Point(x/(3*twiceArea),y/(3*twiceArea))
    }
    public static func pathLength(_ path:[Point]) -> Double {zip(path,path.dropFirst()).reduce(0){$0+$1.0.distance(to:$1.1)}}
}
