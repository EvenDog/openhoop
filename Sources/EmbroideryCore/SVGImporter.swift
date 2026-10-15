import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct SVGImportResult:Sendable {
    public var objects:[RunObject]
    public var warnings:[String]
    public var width:Double
    public var height:Double
}

/// A deliberately bounded geometry importer, not a browser or SVG renderer.
public enum SVGImporter {
    public static func load(_ data:Data)throws->SVGImportResult {
        guard data.count<=5_000_000,let text=String(data:data,encoding:.utf8) else{throw DesignError.invalid("Choose a UTF-8 SVG under 5 MB.")}
        guard !text.contains("<!DOCTYPE"),!text.contains("<!ENTITY") else{throw DesignError.invalid("SVG document types and entities are not supported. Save a plain SVG without a DTD.")}
        let delegate=SVGReader(),parser=XMLParser(data:data)
        parser.shouldResolveExternalEntities=false;parser.shouldProcessNamespaces=true;parser.delegate=delegate
        guard parser.parse(),delegate.failure==nil else{throw delegate.failure ?? DesignError.invalid("SVG XML could not be read: \(parser.parserError?.localizedDescription ?? "invalid document")")}
        guard delegate.rootSeen,!delegate.objects.isEmpty else{throw DesignError.invalid("No supported visible vector geometry was found. \(delegate.warnings.joined(separator:" "))")}
        var objects=delegate.objects
        // Measure the flattened curves: a curve can bulge beyond its nodes.
        let points=objects.flatMap{$0.outlinePaths.flatMap{$0}}
        let minX=points.map(\.x).min()!,maxX=points.map(\.x).max()!,minY=points.map(\.y).min()!,maxY=points.map(\.y).max()!
        let center=Point((minX+maxX)/2,(minY+maxY)/2)
        for i in objects.indices{objects[i].transform{p in let q=p-center;return Point(q.x,-q.y)}}
        var check=Design();check.objects=objects;try check.validate()
        return SVGImportResult(objects:objects,warnings:delegate.warnings,width:maxX-minX,height:maxY-minY)
    }
}

final class SVGReader:NSObject,XMLParserDelegate {
    struct Context {var matrix=SVGMatrix();var style:[String:String]=["fill":"black","stroke":"none","fill-rule":"nonzero"];var skip=false}
    var stack:[Context]=[],objects:[RunObject]=[],warnings:[String]=[],failure:Error?,rootSeen=false,elements=0,totalNodes=0
    func warn(_ text:String){if warnings.count<50 && !warnings.contains(text){warnings.append(text)}}
    func parser(_ parser:XMLParser,foundProcessingInstructionWithTarget target:String,data:String?){if target=="xml-stylesheet"{fail(parser,DesignError.invalid("External SVG stylesheets are not supported. Export SVG with inline styles or presentation attributes."))}}
    func fail(_ parser:XMLParser,_ error:Error){failure=error;parser.abortParsing()}
    func parser(_ parser:XMLParser,resolveExternalEntityName name:String,systemID:String?)->Data?{fail(parser,DesignError.invalid("External SVG entities are not supported."));return nil}
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes a:[String:String]) {
        do {
            try Task.checkCancellation();elements+=1
            guard elements<=10000,stack.count<64 else{throw DesignError.invalid("SVG has too many elements or nested groups.")}
            var ctx=stack.last ?? Context()
            if stack.isEmpty {
                guard name=="svg",namespaceURI==nil || namespaceURI=="" || namespaceURI=="http://www.w3.org/2000/svg" else{throw DesignError.invalid("The file is not an SVG document.")}
                rootSeen=true;ctx.matrix=try viewport(a)
            } else if name=="svg" {ctx.skip=true;warn("Nested SVG viewports were skipped; flatten them before importing.")}
            if let namespaceURI,!namespaceURI.isEmpty,namespaceURI != "http://www.w3.org/2000/svg" {ctx.skip=true;warn("Non-SVG metadata or elements were skipped.")}
            if name=="style" || a["class"] != nil {throw DesignError.invalid("SVG stylesheets and CSS classes are not supported. Export SVG with inline styles or presentation attributes to preserve its appearance.")}
            if ctx.skip {stack.append(ctx);return}
            let supported=["svg","g","a","path","rect","circle","ellipse","line","polyline","polygon"]
            if !supported.contains(name) {ctx.skip=true;if !["title","desc","metadata","defs"].contains(name){warn("Unsupported <\(name)> content was skipped.")};stack.append(ctx);return}
            let inherited=["fill","stroke","fill-rule","visibility","fill-opacity","stroke-opacity","stroke-width","stroke-dasharray","color"]
            var local=a
            if let inline=a["style"] {
                for entry in inline.split(separator:";") {
                    let parts=entry.split(separator:":",maxSplits:1).map{String($0).trimmingCharacters(in:.whitespacesAndNewlines)}
                    if parts.count==2{local[parts[0]]=parts[1]}
                }
            }
            for key in inherited {if let value=local[key],value != "inherit"{ctx.style[key]=value}}
            if local["display"]=="none" || Double(local["opacity"] ?? "1")==0 {ctx.skip=true}
            for key in ["clip-path","mask","filter","marker-start","marker-mid","marker-end"] where local[key] != nil && local[key] != "none" {ctx.skip=true;warn("Elements using \(key) were skipped.")}
            if let transform=a["transform"]{ctx.matrix=ctx.matrix.joined(try Self.transform(transform))}
            stack.append(ctx)
            if ctx.skip || ["svg","g","a"].contains(name) || ["hidden","collapse"].contains(ctx.style["visibility"] ?? ""){return}
            let paths=try geometry(name,a,matrix:ctx.matrix)
            let label=a["id"] ?? "SVG \(name) \(objects.count+1)"
            let fill=ctx.style["fill"] ?? "black",stroke=ctx.style["stroke"] ?? "none"
            let fillColor=try color(fill,current:ctx.style["color"]),strokeColor=try color(stroke,current:ctx.style["color"])
            if local["opacity"] != nil || ctx.style["fill-opacity"] != nil || ctx.style["stroke-opacity"] != nil {warn("SVG opacity is not converted into stitch density; imported thread colors are opaque.")}
            if let fillColor,Double(ctx.style["fill-opacity"] ?? "1") != 0 {
                let outlines=paths.filter{$0.points.count>=3}
                if !outlines.isEmpty {
                    let rule=ctx.style["fill-rule"] ?? "nonzero"
                    guard ["evenodd","nonzero"].contains(rule) else{throw DesignError.invalid("Unsupported SVG fill rule.")}
                    if let curved=try Self.curvedRegions(outlines,nonzero:rule=="nonzero") {try addCurvedRegions(curved,name:label,color:fillColor)}
                    else {
                        if outlines.contains(where:{$0.nodes.contains(where:\.hasHandles)}) {warn("Overlapping or touching shapes in ‘\(label)’ were merged as points, so their curves can't be kept as Bézier handles.")}
                        let resolved=try AreaGeometry.svgRegions(outlines.map(\.points),nonzero:rule=="nonzero")
                        try addRegions(resolved,name:label,color:fillColor)
                    }
                }
            }
            if let strokeColor,Double(ctx.style["stroke-opacity"] ?? "1") != 0,try length(ctx.style["stroke-width"] ?? "1")>0 {
                warn("SVG strokes import as centerlines. Stroke width, dashes and end caps are not digitized automatically.")
                for path in paths {try add(path.nodes,closed:path.closed,name:label+" stroke",color:strokeColor)}
            }
        } catch{fail(parser,error)}
    }
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName:String?){if !stack.isEmpty{stack.removeLast()}}
    func add(_ nodes:[PathNode],closed:Bool,name:String,color:ThreadColor,holes:[[PathNode]]=[] )throws {
        let count=nodes.count+holes.reduce(0){$0+$1.count};totalNodes+=count
        guard count<=2000,totalNodes<=100000,objects.count<1000 else{throw DesignError.invalid("SVG has too many vector nodes. Simplify paths before importing.")}
        guard nodes.count>=2 else{return}
        var object=RunObject(name:name,nodes:nodes,color:color)
        object.closed=closed;object.holes=holes.isEmpty ? nil:holes;object.digitizing=DigitizingSettings(kind:.vector)
        objects.append(object)
    }
    func addCurvedRegions(_ regions:[[[PathNode]]],name:String,color:ThreadColor)throws {
        for rings in regions {
            try Task.checkCancellation()
            try AreaGeometry.validate(rings.map{AreaGeometry.ring($0)})
            try add(rings[0],closed:true,name:name,color:color,holes:Array(rings.dropFirst()))
        }
    }
    /// Outer shapes and holes for simple compound fills, keeping each outline's original curves.
    /// Returns nil, so the caller uses the polygon resolver instead, when any outlines cross or touch, or when an
    /// outline doesn't switch between filled and empty under the fill rule (such as a same-direction ring inside
    /// a nonzero fill).
    static func curvedRegions(_ paths:[SVGSubpath],nonzero:Bool)throws->[[[PathNode]]]? {
        let rings=paths.map(\.points)   // flattened outlines, used only to work out which shape is inside which
        guard rings.count<=64,rings.reduce(0,{$0+$1.count})<=20000,rings.allSatisfy({$0.count>=3 && abs(AreaGeometry.area($0))>0.01}),try !edgesTouch(rings) else{return nil}
        // Each outline's parent is the smallest other outline that contains it.
        let areas=rings.map{abs(AreaGeometry.area($0))}
        let parent:[Int?]=rings.indices.map{i in rings.indices.filter{$0 != i && areas[$0]>areas[i] && AreaGeometry.contains(rings[i][0],rings:[rings[$0]])}.min{areas[$0]<areas[$1]}}
        func ancestors(_ i:Int)->[Int]{var list=[i],p=parent[i];while let q=p{list.append(q);p=parent[q]};return list}
        // Whether the area just inside each outline is filled: winding count (nonzero) or nesting depth (evenodd).
        let filled=rings.indices.map{i in nonzero ? ancestors(i).reduce(0){$0+(AreaGeometry.area(rings[$1])>0 ? 1:-1)} != 0 : ancestors(i).count%2==1}
        for i in rings.indices where filled[i]==(parent[i].map{filled[$0]} ?? false) {return nil}
        let closedNodes=paths.map{SVGPathParser.tidy($0.nodes,closed:true)}
        return rings.indices.filter{filled[$0]}.map{outer in [closedNodes[outer]]+rings.indices.filter{parent[$0]==outer}.map{closedNodes[$0]}}
    }
    /// True if any two edges cross or touch, within one outline or between outlines.
    static func edgesTouch(_ rings:[[Point]])throws->Bool {
        func box(_ ring:[Point])->(Double,Double,Double,Double){(ring.map(\.x).min()!,ring.map(\.y).min()!,ring.map(\.x).max()!,ring.map(\.y).max()!)}
        let boxes=rings.map(box)
        for (r,ring) in rings.enumerated() {
            try Task.checkCancellation()
            for i in ring.indices {
                for j in (i+1)..<ring.count where j != i+1 && !(i==0 && j==ring.count-1) {
                    if AreaGeometry.intersects(ring[i],ring[(i+1)%ring.count],ring[j],ring[(j+1)%ring.count]){return true}
                }
            }
            for o in rings.indices where o>r {
                let a=boxes[r],b=boxes[o]
                guard a.0<=b.2,b.0<=a.2,a.1<=b.3,b.1<=a.3 else{continue}   // bounding boxes apart: no contact possible
                let other=rings[o]
                for i in ring.indices {for j in other.indices where AreaGeometry.intersects(ring[i],ring[(i+1)%ring.count],other[j],other[(j+1)%other.count]){return true}}
            }
        }
        return false
    }
    func addRegions(_ regions:[[[Point]]],name:String,color:ThreadColor)throws {
        for rings in regions {
            try Task.checkCancellation()
            // Reject unassignable touching boundaries before committing any imported objects.
            try AreaGeometry.validate(rings)
            try add(rings[0].map{PathNode($0)},closed:true,name:name,color:color,holes:rings.dropFirst().map{$0.map{PathNode($0)}})
        }
    }
    func color(_ value:String,current:String?)throws->ThreadColor? {
        let s=value.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        if s=="none" || s=="transparent"{return nil}
        if s=="currentcolor"{return try color(current?.lowercased()=="currentcolor" ? "black":current ?? "black",current:nil)}
        let named:[String:Int]=["black":0,"white":0xffffff,"red":0xff0000,"green":0x008000,"blue":0x0000ff,"yellow":0xffff00,"gray":0x808080,"grey":0x808080,"orange":0xffa500,"purple":0x800080,"navy":0x000080,"teal":0x008080,"aqua":0x00ffff,"fuchsia":0xff00ff,"lime":0x00ff00,"maroon":0x800000,"olive":0x808000,"silver":0xc0c0c0]
        if let hex=named[s]{return ThreadColor(value,hex)}
        if s.hasPrefix("#") {
            var digits=String(s.dropFirst());if digits.count==3{digits=digits.map{String(repeating:String($0),count:2)}.joined()}
            if digits.count==6,let hex=Int(digits,radix:16){return ThreadColor(value,hex)}
        }
        if s.hasPrefix("rgb("),s.hasSuffix(")") {
            let parts=s.dropFirst(4).dropLast().split(whereSeparator:{$0=="," || $0.isWhitespace})
            if parts.count==3 {var hex=0;for part in parts {let percent=part.hasSuffix("%"),text=percent ? String(part.dropLast()):String(part);guard let value=Double(text),value.isFinite else{throw DesignError.invalid("Invalid SVG color.")};let n=Int(max(0,min(255,(percent ? value*2.55:value).rounded())));hex=(hex<<8)|n};return ThreadColor(value,hex)}
        }
        throw DesignError.invalid("Unsupported SVG paint ‘\(value)’. Convert colors to six-digit #RRGGBB or rgb(r,g,b) before importing. Gradients and paint servers are not supported.")
    }
    static func transform(_ text:String)throws->SVGMatrix {
        var scan=SVGScanner(text),result=SVGMatrix()
        while scan.peek() != nil {
            let start=scan.index
            while scan.index<scan.bytes.count,((65...90).contains(scan.bytes[scan.index]) || (97...122).contains(scan.bytes[scan.index])){scan.index+=1}
            let name=String(decoding:scan.bytes[start..<scan.index],as:UTF8.self)
            guard scan.peek()==40 else{throw DesignError.invalid("Malformed SVG transform.")};scan.index+=1
            var values:[Double]=[]
            while let p=scan.peek(),p != 41 {values.append(try scan.number());guard values.count<=6 else{throw DesignError.invalid("Too many SVG transform values.")}}
            guard scan.peek()==41 else{throw DesignError.invalid("Unclosed SVG transform.")};scan.index+=1
            let m:SVGMatrix
            switch (name,values.count) {
            case ("matrix",6):m=SVGMatrix(a:values[0],b:values[1],c:values[2],d:values[3],e:values[4],f:values[5])
            case ("translate",1),("translate",2):m = .translate(values[0],values.count==2 ? values[1]:0)
            case ("scale",1),("scale",2):m=SVGMatrix(a:values[0],d:values.count==2 ? values[1]:values[0])
            case ("rotate",1),("rotate",3):let r=values[0] * .pi/180,rotation=SVGMatrix(a:cos(r),b:sin(r),c:-sin(r),d:cos(r));m=values.count==1 ? rotation:SVGMatrix.translate(values[1],values[2]).joined(rotation).joined(.translate(-values[1],-values[2]))
            case ("skewX",1):m=SVGMatrix(c:tan(values[0] * .pi/180))
            case ("skewY",1):m=SVGMatrix(b:tan(values[0] * .pi/180))
            default:throw DesignError.invalid("Unsupported SVG transform ‘\(name)’.")
            }
            result=result.joined(m)
        }
        return result
    }
    func length(_ text:String)throws->Double {
        var scan=SVGScanner(text);let value=try scan.number();scan.skip();let unit=String(decoding:scan.bytes[scan.index...],as:UTF8.self)
        let factors=["":1.0,"px":1,"mm":96/25.4,"cm":96/2.54,"in":96,"pt":96/72.0,"pc":16]
        guard let factor=factors[unit] else{throw DesignError.invalid("Unsupported SVG length unit ‘\(unit)’. Use px, mm, cm, in, pt or pc.")}
        return value*factor
    }
    func viewport(_ a:[String:String])throws->SVGMatrix {
        let box=try a["viewBox"].map{try SVGScanner.numbers($0)}
        if let box {guard box.count==4,box[2]>0,box[3]>0 else{throw DesignError.invalid("Invalid SVG viewBox.")}}
        func dimension(_ key:String,_ fallback:Double)throws->Double {
            guard let value=a[key] else{return fallback}
            if value.trimmingCharacters(in:.whitespacesAndNewlines)=="auto" || value.hasSuffix("%") {
                warn("SVG percentage/auto dimensions have no fixed physical size. The viewBox or default viewport is interpreted at 96 dpi; check the imported size before digitizing.")
                return fallback
            }
            return try length(value)
        }
        let w=try dimension("width",box?[2] ?? 300),h=try dimension("height",box?[3] ?? 150)
        guard w>0,h>0 else{throw DesignError.invalid("SVG viewport dimensions must be positive.")}
        let unit=25.4/96
        guard let box else{return SVGMatrix(a:unit,d:unit)}
        var sx=w/box[2],sy=h/box[3],dx=0.0,dy=0.0
        let aspect=(a["preserveAspectRatio"] ?? "xMidYMid meet").split(separator:" ").map(String.init)
        if aspect.first != "none" {
            guard let align=aspect.first,["xMinYMin","xMidYMin","xMaxYMin","xMinYMid","xMidYMid","xMaxYMid","xMinYMax","xMidYMax","xMaxYMax"].contains(align),aspect.count<=2,aspect.count==1 || aspect[1]=="meet" else{throw DesignError.invalid("Only preserveAspectRatio meet or none is supported; slice requires clipping.")}
            sx=min(sx,sy);sy=sx
            dx=(w-box[2]*sx)*(align.contains("xMid") ? 0.5:align.contains("xMax") ? 1:0)
            dy=(h-box[3]*sy)*(align.contains("YMid") ? 0.5:align.contains("YMax") ? 1:0)
        }
        return SVGMatrix(a:unit*sx,d:unit*sy,e:unit*(dx-box[0]*sx),f:unit*(dy-box[1]*sy))
    }
    func geometry(_ name:String,_ a:[String:String],matrix:SVGMatrix)throws->[SVGSubpath] {
        func n(_ key:String,_ fallback:Double=0)throws->Double {try a[key].map{try length($0)} ?? fallback}
        var path:String
        switch name {
        case "path":path=a["d"] ?? ""
        case "line":path="M \(try n("x1")) \(try n("y1")) L \(try n("x2")) \(try n("y2"))"
        case "polyline","polygon":let values=try SVGScanner.numbers(a["points"] ?? "");guard values.count%2==0 else{throw DesignError.invalid("SVG points need x/y pairs.")};path=values.isEmpty ? "":"M "+values.map(String.init(describing:)).joined(separator:" ")+(name=="polygon" ? " Z":"")
        case "rect":
            let x=try n("x"),y=try n("y"),w=try n("width"),h=try n("height")
            guard w>=0,h>=0 else{throw DesignError.invalid("SVG rectangle has negative size.")};if w==0 || h==0{return []}
            let rx=min(w/2,max(0,try n("rx",n("ry")))),ry=min(h/2,max(0,try n("ry",n("rx"))))
            if rx==0 || ry==0 {path="M \(x) \(y) h \(w) v \(h) h \(-w) Z"}
            else{path="M \(x+rx) \(y) H \(x+w-rx) A \(rx) \(ry) 0 0 1 \(x+w) \(y+ry) V \(y+h-ry) A \(rx) \(ry) 0 0 1 \(x+w-rx) \(y+h) H \(x+rx) A \(rx) \(ry) 0 0 1 \(x) \(y+h-ry) V \(y+ry) A \(rx) \(ry) 0 0 1 \(x+rx) \(y) Z"}
        case "circle","ellipse":
            let x=try n("cx"),y=try n("cy"),rx=try n(name=="circle" ? "r":"rx"),ry=try n(name=="circle" ? "r":"ry")
            guard rx>=0,ry>=0 else{throw DesignError.invalid("SVG ellipse has negative radius.")};if rx==0 || ry==0{return []}
            path="M \(x-rx) \(y) A \(rx) \(ry) 0 1 0 \(x+rx) \(y) A \(rx) \(ry) 0 1 0 \(x-rx) \(y) Z"
        default:return []
        }
        var parser=SVGPathParser(path,matrix:matrix);return try parser.parse()
    }
}
