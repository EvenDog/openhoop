// Satin fill: a closed shape sewn as satin. Every stitch runs straight across the shape at the fill angle, from edge
// to edge, and the next comes back, like a satin column with the shape's outline as its rails. Wide parts are split:
// a stitch longer than the split length is broken at steps measured from its left end, so the breaks line up in
// bands that follow the shape's left edge instead of a straight groove.
import Foundation

enum SatinFill {
    /// The sections of a satin fill of `region`, each a zigzag of needle points. A shape that branches (a notch, a
    /// hole) is sewn in several sections, each one running from row to row without leaving the shape.
    /// With `split`, stitches longer than `maximum` are broken up; without it, they're refused.
    static func stitches(in region:[[Point]],angle:Double,spacing:Double,maximum:Double,split:Bool) throws -> [[Point]] {
        // Work with the rows level: turn the shape so the fill angle points along x, and turn the stitches back at the end.
        let rings=region.map{$0.map{AreaGeometry.rotate($0,degrees:-angle)}}
        let allowed=(try? AreaGeometry.offset(rings,by:0.05)) ?? rings   // row ends lie exactly on the edge
        let points=rings.flatMap{$0}
        guard let minY=points.map(\.y).min(),let maxY=points.map(\.y).max(),maxY-minY>0.0001 else{return []}
        let count=max(1,Int(ceil((maxY-minY)/spacing))),step=(maxY-minY)/Double(count)
        guard count<=20000 else{throw DesignError.invalid("Fill would produce too many stitches. Reduce its size or increase spacing.")}
        // Each section is a list of rows; each row is where it crosses the shape, left end then right end.
        var sections:[[(left:Point,right:Point)]]=[]
        var previous:[(left:Double,right:Double,section:Int)]=[]
        for row in 0..<count {
            try Task.checkCancellation()
            let y=minY+(Double(row)+0.5)*step
            var crossings:[Double]=[]
            for ring in rings {for i in ring.indices {
                let a=ring[i],b=ring[(i+1)%ring.count]
                if (a.y<=y && b.y>y)||(b.y<=y && a.y>y) {crossings.append(a.x+(y-a.y)*(b.x-a.x)/(b.y-a.y))}
            }}
            crossings.sort()
            guard crossings.count%2==0 else{throw DesignError.invalid("Fill scanline could not resolve the outline.")}
            var current:[(left:Double,right:Double,section:Int)]=[]
            for i in stride(from:0,to:crossings.count,by:2) where crossings[i+1]-crossings[i]>0.0001 {current.append((crossings[i],crossings[i+1],-1))}
            func overlaps(_ a:(left:Double,right:Double,section:Int),_ b:(left:Double,right:Double,section:Int))->Bool {min(a.right,b.right)-max(a.left,b.left)>0.0001}
            for index in current.indices {
                let span=(left:Point(current[index].left,y),right:Point(current[index].right,y))
                // A row carries on the section of the row below when that's the only row it touches, and the row below
                // touches only this one (where the shape splits or joins, new sections start), and the stitch across
                // from the last row's right end to this row's left end stays inside the shape.
                let parents=previous.filter{overlaps($0,current[index])}
                if parents.count==1,current.filter({overlaps(parents[0],$0)}).count==1,
                   let last=sections[parents[0].section].last,AreaGeometry.segmentInside(last.right,span.left,rings:allowed) {
                    current[index].section=parents[0].section
                    sections[parents[0].section].append(span)
                } else {
                    current[index].section=sections.count
                    sections.append([span])
                }
            }
            previous=current
        }
        // Zigzag: left, right, next left, next right… Then split what's too long, and turn it all back to the fill angle.
        return try sections.map{rows in
            let zigzag=rows.flatMap{[$0.left,$0.right]}
            var sewn=[zigzag[0]]
            for (index,(a,b)) in zip(zigzag,zigzag.dropFirst()).enumerated() {
                if a.distance(to:b)>maximum+0.0001 {
                    guard split else{throw DesignError.invalid("Satin fill stitches would be longer than \(String(format:"%.1f",maximum)) mm. Turn on Auto split, or make the shape narrower.")}
                    sewn+=breaks(a,b,maximum:maximum,shifted:index%2==1)
                }
                sewn.append(b)
            }
            return sewn.map{AreaGeometry.rotate($0,degrees:angle)}
        }
    }
    /// Where a long stitch from `a` to `b` is broken: every (maximum − 1.5 mm) from its left end, with the breaks of
    /// every other stitch moved 0.3 mm along so neighbouring stitches don't share holes. A last piece under 1.2 mm
    /// joins the one before. So every piece is between 0.9 mm and `maximum` long. Returned in sewing order (a to b).
    static func breaks(_ a:Point,_ b:Point,maximum:Double,shifted:Bool)->[Point] {
        let (left,right)=a.x<=b.x ? (a,b):(b,a),length=a.distance(to:b),step=maximum-1.5,shift=shifted ? 0.3:-0.3
        var points:[Point]=[],distance=step
        while distance<length-1.2 {points.append(left+(right-left)*((distance+shift)/length));distance+=step}
        return a.x<=b.x ? points:points.reversed()
    }
}
