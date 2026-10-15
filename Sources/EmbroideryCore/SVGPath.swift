import Foundation

struct SVGMatrix {
    var a=1.0,b=0.0,c=0.0,d=1.0,e=0.0,f=0.0
    func apply(_ p:Point)->Point {Point(a*p.x+c*p.y+e,b*p.x+d*p.y+f)}
    func joined(_ r:Self)->Self {Self(a:a*r.a+c*r.b,b:b*r.a+d*r.b,c:a*r.c+c*r.d,d:b*r.c+d*r.d,e:a*r.e+c*r.f+e,f:b*r.e+d*r.f+f)}
    // Largest singular value bounds distance under anisotropic scale and shear.
    var scale:Double {
        let x=a*a+b*b,y=c*c+d*d,z=a*c+b*d
        return sqrt(max(0,(x+y+hypot(x-y,2*z))/2))
    }
    static func translate(_ x:Double,_ y:Double)->Self {Self(e:x,f:y)}
}

struct SVGScanner {
    var bytes:[UInt8];var index=0
    init(_ text:String){bytes=Array(text.utf8)}
    mutating func skip(){while index<bytes.count && [9,10,13,32,44].contains(bytes[index]){index+=1}}
    mutating func peek()->UInt8?{skip();return index<bytes.count ? bytes[index]:nil}
    mutating func number() throws -> Double {
        skip();let start=index
        if index<bytes.count && [43,45].contains(bytes[index]){index+=1}
        var digits=0
        while index<bytes.count && (48...57).contains(bytes[index]){index+=1;digits+=1}
        if index<bytes.count && bytes[index]==46 {index+=1;while index<bytes.count && (48...57).contains(bytes[index]){index+=1;digits+=1}}
        guard digits>0 else{throw DesignError.invalid("SVG contains an invalid number.")}
        if index<bytes.count && [69,101].contains(bytes[index]) {
            index+=1;if index<bytes.count && [43,45].contains(bytes[index]){index+=1}
            let exponent=index
            while index<bytes.count && (48...57).contains(bytes[index]){index+=1}
            guard index>exponent else{throw DesignError.invalid("SVG exponent is incomplete.")}
        }
        guard let value=Double(String(decoding:bytes[start..<index],as:UTF8.self)),value.isFinite,abs(value)<=1e7 else{throw DesignError.invalid("SVG number is out of range.")}
        return value
    }
    mutating func flag()throws->Bool {skip();guard index<bytes.count,[48,49].contains(bytes[index]) else{throw DesignError.invalid("SVG arc flags must be 0 or 1.")};defer{index+=1};return bytes[index]==49}
    static func numbers(_ text:String)throws->[Double]{var scan=Self(text),out:[Double]=[];while scan.peek() != nil{out.append(try scan.number());if out.count>100000{throw DesignError.invalid("SVG number list is too large.")}};return out}
}

/// One SVG subpath, both as flattened points (used to work out fill topology) and as editable nodes whose
/// Bézier handles keep the original curves.
struct SVGSubpath {var points:[Point];var closed:Bool;var nodes:[PathNode]=[]}
struct SVGPathParser {
    var scan:SVGScanner;var matrix:SVGMatrix
    var result:[SVGSubpath]=[],points:[Point]=[]
    var nodes:[PathNode]=[]   // the current subpath as editable nodes, in millimeters
    var current=Point(0,0),start=Point(0,0),cubicControl:Point?,quadControl:Point?
    var count=0
    init(_ text:String,matrix:SVGMatrix){scan=SVGScanner(text);self.matrix=matrix}
    mutating func append(_ p:Point)throws {
        guard p.finite,abs(p.x)<=10000,abs(p.y)<=10000,count<100000 else{throw DesignError.invalid("SVG geometry is too large or too complex.")}
        if points.last.map({$0.distance(to:p)>1e-8}) ?? true{points.append(p);count+=1}
    }
    mutating func finish(_ closed:Bool){
        if points.count>1{if closed,points.first==points.last{points.removeLast()};result.append(SVGSubpath(points:points,closed:closed,nodes:Self.tidy(nodes,closed:closed)))}
        points=[];nodes=[]
    }
    /// Adds a straight-line node (or the subpath's first node).
    mutating func node(_ p:Point){if nodes.last.map({$0.point.distance(to:p)>1e-8}) ?? true{nodes.append(PathNode(p))}}
    /// Adds a cubic Bézier segment from the last node to `end`; all points are already in millimeters.
    mutating func curveNode(_ c1:Point,_ c2:Point,_ end:Point){
        guard let last=nodes.last else{nodes.append(PathNode(end));return}
        if last.point.distance(to:end)<1e-8 && last.point.distance(to:c1)<1e-8 && last.point.distance(to:c2)<1e-8 {return}
        nodes[nodes.count-1].outHandle=c1;nodes.append(PathNode(end,inHandle:c2))
    }
    /// Merges a closing node that repeats the first one, then marks nodes smooth where their two handles
    /// line up (within about 2°). Nodes with one handle, or bent handles, stay corners.
    static func tidy(_ input:[PathNode],closed:Bool)->[PathNode] {
        var nodes=input
        if closed,nodes.count>2,let last=nodes.last,last.point.distance(to:nodes[0].point)<1e-6 {nodes[0].inHandle=last.inHandle;nodes.removeLast()}
        for i in nodes.indices {
            guard let a=nodes[i].inHandle,let b=nodes[i].outHandle else{continue}
            let u=nodes[i].point-a,v=b-nodes[i].point,lu=hypot(u.x,u.y),lv=hypot(v.x,v.y)
            nodes[i].smooth=lu>1e-6 && lv>1e-6 && u.x*v.x+u.y*v.y>0 && abs(AreaGeometry.cross(u,v))/(lu*lv)<0.035
        }
        return nodes
    }
    mutating func point(relative:Bool)throws->Point {let p=Point(try scan.number(),try scan.number());return relative ? p+current:p}
    mutating func curve(_ a:Point,_ b:Point,_ c:Point,_ d:Point,depth:Int=0)throws {
        let deviation=max(b.distance(to:AreaGeometry.projection(b,a,d)),c.distance(to:AreaGeometry.projection(c,a,d)))
        if deviation<=0.025 {try append(d);return}
        guard depth<18 else{throw DesignError.invalid("SVG curve needs too many subdivisions.")}
        let ab=(a+b)*0.5,bc=(b+c)*0.5,cd=(c+d)*0.5,abc=(ab+bc)*0.5,bcd=(bc+cd)*0.5,mid=(abc+bcd)*0.5
        try curve(a,ab,abc,mid,depth:depth+1);try curve(mid,bcd,cd,d,depth:depth+1)
    }
    mutating func arc(rx inputRX:Double,ry inputRY:Double,angle:Double,large:Bool,sweep:Bool,to end:Point)throws {
        var rx=abs(inputRX),ry=abs(inputRY)
        if end==current{return};if rx==0 || ry==0{try append(matrix.apply(end));node(matrix.apply(end));return}
        let phi=angle.truncatingRemainder(dividingBy:360) * .pi/180,co=cos(phi),si=sin(phi),half=(current-end)*0.5
        let xp=co*half.x+si*half.y,yp = -si*half.x+co*half.y
        let ratio=xp*xp/(rx*rx)+yp*yp/(ry*ry)
        if ratio>1{rx*=sqrt(ratio);ry*=sqrt(ratio)}
        let numerator=max(0,rx*rx*ry*ry-rx*rx*yp*yp-ry*ry*xp*xp),denominator=rx*rx*yp*yp+ry*ry*xp*xp
        let factor=(large==sweep ? -1.0:1.0)*sqrt(numerator/denominator)
        let cxp=factor*rx*yp/ry,cyp = -factor*ry*xp/rx
        let center=Point(co*cxp-si*cyp+(current.x+end.x)/2,si*cxp+co*cyp+(current.y+end.y)/2)
        let u=Point((xp-cxp)/rx,(yp-cyp)/ry),v=Point((-xp-cxp)/rx,(-yp-cyp)/ry)
        let theta=atan2(u.y,u.x);var delta=atan2(AreaGeometry.cross(u,v),u.x*v.x+u.y*v.y)
        if !sweep && delta>0{delta-=2 * .pi};if sweep && delta<0{delta+=2 * .pi}
        let radius=max(rx,ry)*matrix.scale
        let step=min(.pi/8,2*acos(max(-1,min(1,1-0.025/max(radius,0.025)))))
        guard step.isFinite,step>0,abs(delta)/step<10000 else{throw DesignError.invalid("SVG arc is too large or complex.")}
        let n=max(1,Int(ceil(abs(delta)/step)))
        for i in 1...n {let t=theta+delta*Double(i)/Double(n);try append(i==n ? matrix.apply(end):matrix.apply(center+Point(co*rx*cos(t)-si*ry*sin(t),si*rx*cos(t)+co*ry*sin(t))))}
        // The same arc as cubic Béziers for editable nodes: one curve per quarter turn or less. Each curve's
        // handles point along the ellipse's tangent, k = 4/3·tan(angle/4) of the way (the standard approximation).
        func at(_ t:Double)->Point{center+Point(co*rx*cos(t)-si*ry*sin(t),si*rx*cos(t)+co*ry*sin(t))}
        func tangent(_ t:Double)->Point{Point(-co*rx*sin(t)-si*ry*cos(t),-si*rx*sin(t)+co*ry*cos(t))}
        let pieces=max(1,Int(ceil(abs(delta)/(Double.pi/2)-1e-9)))
        for i in 0..<pieces {
            let t0=theta+delta*Double(i)/Double(pieces),t1=theta+delta*Double(i+1)/Double(pieces),k=4.0/3*tan((t1-t0)/4)
            curveNode(matrix.apply(at(t0)+tangent(t0)*k),matrix.apply(at(t1)-tangent(t1)*k),i==pieces-1 ? matrix.apply(end):matrix.apply(at(t1)))
        }
    }
    mutating func parse()throws->[SVGSubpath] {
        var command:UInt8=0,seenMove=false
        while let next=scan.peek() {
            try Task.checkCancellation()
            if (65...90).contains(next)||(97...122).contains(next){command=next;scan.index+=1}
            guard command != 0 else{throw DesignError.invalid("SVG path is missing a command.")}
            let upper=command>=97 ? command-32:command,relative=command>=97
            guard seenMove || upper==77 else{throw DesignError.invalid("SVG paths must start with M.")}
            if upper==90 {finish(true);current=start;cubicControl=nil;quadControl=nil;command=0;continue}
            if points.isEmpty && upper != 77{try append(matrix.apply(current));node(matrix.apply(current))}
            let old=current,oldC=cubicControl,oldQ=quadControl;cubicControl=nil;quadControl=nil
            switch upper {
            case 77:
                let p=try point(relative:relative);finish(false);current=p;start=p;seenMove=true;try append(matrix.apply(p));node(matrix.apply(p));command=relative ? 108:76
            case 76:current=try point(relative:relative);try append(matrix.apply(current));node(matrix.apply(current))
            case 72:let x=try scan.number();current.x=relative ? current.x+x:x;try append(matrix.apply(current));node(matrix.apply(current))
            case 86:let y=try scan.number();current.y=relative ? current.y+y:y;try append(matrix.apply(current));node(matrix.apply(current))
            case 67,83:
                let c1=upper==67 ? try point(relative:relative):(oldC.map{old*2-$0} ?? old)
                let c2=try point(relative:relative),end=try point(relative:relative)
                try curve(matrix.apply(old),matrix.apply(c1),matrix.apply(c2),matrix.apply(end));curveNode(matrix.apply(c1),matrix.apply(c2),matrix.apply(end));current=end;cubicControl=c2
            case 81,84:
                let c=upper==81 ? try point(relative:relative):(oldQ.map{old*2-$0} ?? old),end=try point(relative:relative)
                // A quadratic curve is exactly a cubic whose handles sit two thirds of the way to its control point.
                let q1=matrix.apply(old+(c-old)*(2.0/3)),q2=matrix.apply(end+(c-end)*(2.0/3))
                try curve(matrix.apply(old),q1,q2,matrix.apply(end));curveNode(q1,q2,matrix.apply(end));current=end;quadControl=c
            case 65:
                let rx=try scan.number(),ry=try scan.number(),angle=try scan.number(),large=try scan.flag(),sweep=try scan.flag(),end=try point(relative:relative)
                try arc(rx:rx,ry:ry,angle:angle,large:large,sweep:sweep,to:end);current=end
            default:throw DesignError.invalid("Unsupported SVG path command.")
            }
        }
        finish(false);return result
    }
}
