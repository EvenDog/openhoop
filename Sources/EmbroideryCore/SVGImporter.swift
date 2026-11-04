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
        // Read the whole file into a tree first: <use>, gradients and <style> rules can point anywhere in it.
        let builder=SVGTreeBuilder(),parser=XMLParser(data:data)
        parser.shouldResolveExternalEntities=false;parser.shouldProcessNamespaces=true;parser.delegate=builder
        guard parser.parse(),builder.failure==nil,let root=builder.root else{throw builder.failure ?? DesignError.invalid("SVG XML could not be read: \(parser.parserError?.localizedDescription ?? "invalid document")")}
        let reader=try SVGReader(root:root)
        try reader.walk(root)
        if reader.styles.skippedRules>0 {reader.warn("Some SVG style rules use selectors this importer can't match (such as g > path, :hover or @media) and were skipped; check the imported colors.")}
        guard !reader.objects.isEmpty else{throw DesignError.invalid("No supported visible vector geometry was found. \(reader.warnings.joined(separator:" "))")}
        var objects=reader.objects
        // Measure the flattened curves: a curve can bulge beyond its nodes.
        let points=objects.flatMap{$0.outlinePaths.flatMap{$0}}
        let minX=points.map(\.x).min()!,maxX=points.map(\.x).max()!,minY=points.map(\.y).min()!,maxY=points.map(\.y).max()!
        let center=Point((minX+maxX)/2,(minY+maxY)/2)
        for i in objects.indices{objects[i].transform{p in let q=p-center;return Point(q.x,-q.y)}}
        var check=Design();check.objects=objects;try check.validate()
        return SVGImportResult(objects:objects,warnings:reader.warnings,width:maxX-minX,height:maxY-minY)
    }
}

/// One element of an SVG file: its tag, attributes and children (and, for <style>, its text).
final class SVGNode {
    let name:String,namespace:String?,attributes:[String:String]
    var children:[SVGNode]=[],text=""
    init(name:String,namespace:String?,attributes:[String:String]){self.name=name;self.namespace=namespace;self.attributes=attributes}
}

/// Reads an SVG file into a tree of `SVGNode`s, refusing anything that would load other files.
final class SVGTreeBuilder:NSObject,XMLParserDelegate {
    var root:SVGNode?,stack:[SVGNode]=[],failure:Error?,elements=0
    func fail(_ parser:XMLParser,_ error:Error){failure=error;parser.abortParsing()}
    func parser(_ parser:XMLParser,foundProcessingInstructionWithTarget target:String,data:String?){if target=="xml-stylesheet"{fail(parser,DesignError.invalid("External SVG stylesheets are not supported. Export SVG with inline styles or presentation attributes."))}}
    func parser(_ parser:XMLParser,resolveExternalEntityName name:String,systemID:String?)->Data?{fail(parser,DesignError.invalid("External SVG entities are not supported."));return nil}
    func parser(_ parser:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        elements+=1
        guard elements<=10000,stack.count<64 else{fail(parser,DesignError.invalid("SVG has too many elements or nested groups."));return}
        let node=SVGNode(name:name,namespace:namespaceURI,attributes:attributes)
        if let parent=stack.last{parent.children.append(node)} else if root==nil{root=node}
        stack.append(node)
    }
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName:String?){if !stack.isEmpty{stack.removeLast()}}
    func parser(_ parser:XMLParser,foundCharacters string:String){if stack.last?.name=="style"{stack.last?.text+=string}}
    func parser(_ parser:XMLParser,foundCDATA block:Data){if stack.last?.name=="style"{stack.last?.text+=String(decoding:block,as:UTF8.self)}}
}

/// Turns an SVG tree into outlines, walking it the way a renderer would: each element inherits colors and
/// transforms from the elements around it.
final class SVGReader {
    struct Context {var matrix=SVGMatrix();var style:[String:String]=["fill":"black","stroke":"none","fill-rule":"nonzero"];var skip=false}
    /// What a fill or stroke paints with: nothing, one color, or a two-color gradient whose start color's rows run
    /// at `angle` (see `gradientAngle`).
    enum Paint {case none,flat(ThreadColor),blend(ThreadColor,ThreadColor,angle:Double)}
    var styles=SVGStyles(),stack:[Context]=[],objects:[RunObject]=[],warnings:[String]=[],elements=0,totalNodes=0
    /// Every element with an id, for <use href="#id"> and fill="url(#id)".
    var byID:[String:SVGNode]=[:]
    /// The <use> targets being drawn right now, so a <use> inside its own target is caught instead of looping forever.
    var drawing:Set<ObjectIdentifier>=[]

    /// A reader with no file, for its unit, viewport and shape helpers (the embroidery fonts use these).
    init() {}
    /// A reader for the SVG tree under `root`, with its ids indexed and its <style> rules read.
    init(root:SVGNode)throws {
        var css=""
        collect(root,css:&css)
        styles=try SVGStyles(css:css)
    }
    /// Indexes `node` and everything in it by id, and gathers the text of <style> blocks, in file order.
    private func collect(_ node:SVGNode,css:inout String) {
        if let id=node.attributes["id"],byID[id]==nil{byID[id]=node}
        if node.name=="style"{css+="\n"+node.text}
        for child in node.children{collect(child,css:&css)}
    }
    func warn(_ text:String){if warnings.count<50 && !warnings.contains(text){warnings.append(text)}}

    /// Imports `node` and everything inside it. `usedBy` is the <use> drawing it, if any; a <symbol> is only drawn that way.
    func walk(_ node:SVGNode,usedBy:SVGNode?=nil)throws {
        try start(node,usedBy:usedBy)
        defer{stack.removeLast()}
        guard let ctx=stack.last,!ctx.skip else{return}
        switch node.name {
        case "use":try use(node)
        case "svg","g","a","symbol":for child in node.children{try walk(child)}
        default:break
        }
    }
    /// Draws what a <use> points at (href="#id") as if it sat inside the <use>: moved by its x and y, and taking
    /// the <use>'s colors where it has none of its own.
    func use(_ node:SVGNode)throws {
        let a=node.attributes
        guard let ref=a["href"] ?? a["xlink:href"],ref.hasPrefix("#"),let target=byID[String(ref.dropFirst())] else{warn("A <use> that points at nothing in this file was skipped.");return}
        let key=ObjectIdentifier(target)
        guard !drawing.contains(key) else{throw DesignError.invalid("An SVG <use> draws itself, so it would never end. Fix the file in your design app.")}
        drawing.insert(key);defer{drawing.remove(key)}
        stack[stack.count-1].matrix=stack[stack.count-1].matrix.joined(.translate(try length(a["x"] ?? "0"),try length(a["y"] ?? "0")))
        try walk(target,usedBy:node)
    }
    /// An element's own style properties, weakest first: attributes like fill='red', then matching <style> rules,
    /// then style='…' on the element.
    func properties(_ node:SVGNode)->[String:String] {
        var local=node.attributes
        let classes=(node.attributes["class"] ?? "").split(whereSeparator:\.isWhitespace).map(String.init)
        for (key,value) in styles.declarations(tag:node.name,id:node.attributes["id"],classes:classes){local[key]=value}
        if let inline=node.attributes["style"] {
            for entry in inline.split(separator:";") {
                let parts=entry.split(separator:":",maxSplits:1).map{String($0).trimmingCharacters(in:.whitespacesAndNewlines)}
                if parts.count==2{local[parts[0]]=parts[1]}
            }
        }
        return local
    }
    /// Pushes `node`'s context (colors and transform) and adds the outlines it draws, if it's a shape.
    func start(_ node:SVGNode,usedBy:SVGNode?)throws {
        let name=node.name,namespaceURI=node.namespace,a=node.attributes
        try Task.checkCancellation();elements+=1
        guard elements<=10000,stack.count<64 else{throw DesignError.invalid("SVG has too many elements or nested groups.")}
        var ctx=stack.last ?? Context()
        if stack.isEmpty {
            guard name=="svg",namespaceURI==nil || namespaceURI=="" || namespaceURI=="http://www.w3.org/2000/svg" else{throw DesignError.invalid("The file is not an SVG document.")}
            ctx.matrix=try viewport(a)
        } else if name=="svg" {ctx.skip=true;warn("Nested SVG viewports were skipped; flatten them before importing.")}
        if let namespaceURI,!namespaceURI.isEmpty,namespaceURI != "http://www.w3.org/2000/svg" {ctx.skip=true;warn("Non-SVG metadata or elements were skipped.")}
        if ctx.skip {stack.append(ctx);return}
        let supported=["svg","g","a","use","path","rect","circle","ellipse","line","polyline","polygon"]+(usedBy == nil ? []:["symbol"])
        if !supported.contains(name) {ctx.skip=true;if !["title","desc","metadata","defs","style","symbol","linearGradient","radialGradient"].contains(name){warn("Unsupported <\(name)> content was skipped.")};stack.append(ctx);return}
        let inherited=["fill","stroke","fill-rule","visibility","fill-opacity","stroke-opacity","stroke-width","stroke-dasharray","color"]
        let local=properties(node)
        for key in inherited {if let value=local[key],value != "inherit"{ctx.style[key]=value}}
        if local["display"]=="none" || Double(local["opacity"] ?? "1")==0 {ctx.skip=true}
        for key in ["clip-path","mask","filter","marker-start","marker-mid","marker-end"] where local[key] != nil && local[key] != "none" {ctx.skip=true;warn("Elements using \(key) were skipped.")}
        if let transform=a["transform"]{ctx.matrix=ctx.matrix.joined(try Self.transform(transform))}
        // A symbol with a viewBox is scaled to the <use>'s width and height (or drawn at its viewBox size).
        if name=="symbol",let usedBy,let box=try a["viewBox"].map({try SVGScanner.numbers($0)}) {
            guard box.count==4,box[2]>0,box[3]>0 else{throw DesignError.invalid("Invalid SVG viewBox.")}
            let width=try usedBy.attributes["width"].map{try length($0)} ?? box[2],height=try usedBy.attributes["height"].map{try length($0)} ?? box[3]
            ctx.matrix=ctx.matrix.joined(try fit(box,width:width,height:height,aspect:a["preserveAspectRatio"]))
        }
        stack.append(ctx)
        if ctx.skip || ["svg","g","a","use","symbol"].contains(name) || ["hidden","collapse"].contains(ctx.style["visibility"] ?? ""){return}
        let paths=try geometry(name,a,matrix:ctx.matrix)
        let label=a["id"] ?? "SVG \(name) \(objects.count+1)"
        let fill=try paint(ctx.style["fill"] ?? "black",ctx:ctx,shape:node),stroke=try paint(ctx.style["stroke"] ?? "none",ctx:ctx,shape:node)
        if local["opacity"] != nil || ctx.style["fill-opacity"] != nil || ctx.style["stroke-opacity"] != nil {warn("SVG opacity is not converted into stitch density; imported thread colors are opaque.")}
        if Double(ctx.style["fill-opacity"] ?? "1") != 0 {
            let rule=ctx.style["fill-rule"] ?? "nonzero"
            switch fill {
            case .none:break
            case .flat(let color):try addFill(paths,rule:rule,label:label,color:color,gradientAngle:nil)
            case .blend(let first,let last,let angle):
                // Two copies: the start color solid at the start, the end color solid at the end, blending between.
                try addFill(paths,rule:rule,label:label+" start color",color:first,gradientAngle:angle)
                try addFill(paths,rule:rule,label:label+" end color",color:last,gradientAngle:angle+180)
            }
        }
        let strokeColor:ThreadColor?
        switch stroke {
        case .none:strokeColor=nil
        case .flat(let color):strokeColor=color
        case .blend(let first,let last,_):strokeColor=Self.color(at:0.5,[(0,first),(1,last)]);warn("Gradient strokes import as one color, the gradient's middle.")
        }
        if let strokeColor,Double(ctx.style["stroke-opacity"] ?? "1") != 0,try length(ctx.style["stroke-width"] ?? "1")>0 {
            warn("SVG strokes import as centerlines. Stroke width, dashes and end caps are not digitized automatically.")
            for path in paths {try add(path.nodes,closed:path.closed,name:label+" stroke",color:strokeColor)}
        }
    }
    /// Adds the area inside `paths` as outline objects in `color`. With `gradientAngle`, they're set up so Fill makes
    /// them gradient fills at that angle (see `DigitizingSettings.fill(from:)`).
    func addFill(_ paths:[SVGSubpath],rule:String,label:String,color:ThreadColor,gradientAngle:Double?)throws {
        let outlines=paths.filter{$0.points.count>=3}
        guard !outlines.isEmpty else{return}
        guard ["evenodd","nonzero"].contains(rule) else{throw DesignError.invalid("Unsupported SVG fill rule.")}
        let first=objects.count
        if let curved=try Self.curvedRegions(outlines,nonzero:rule=="nonzero") {try addCurvedRegions(curved,name:label,color:color)}
        else {
            if outlines.contains(where:{$0.nodes.contains(where:\.hasHandles)}) {warn("Overlapping or touching shapes in ‘\(label)’ were merged as points, so their curves can't be kept as Bézier handles.")}
            let resolved=try AreaGeometry.svgRegions(outlines.map(\.points),nonzero:rule=="nonzero")
            try addRegions(resolved,name:label,color:color)
        }
        if let gradientAngle {
            // Fill angles run from -180 to 180.
            var angle=gradientAngle.truncatingRemainder(dividingBy:360);if angle>180{angle-=360}else if angle <= -180{angle+=360}
            for i in first..<objects.count {objects[i].digitizing?.fillStyle = .gradient;objects[i].digitizing?.angle=angle}
        }
    }

    // MARK: Gradients

    /// What `value` (a fill or stroke) paints `shape` with. url(#id) can name a gradient; a color after it is the
    /// fallback when the id isn't one.
    func paint(_ value:String,ctx:Context,shape:SVGNode)throws->Paint {
        let s=value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard s.lowercased().hasPrefix("url(") else{return try color(s,current:ctx.style["color"]).map(Paint.flat) ?? Paint.none}
        guard let close=s.firstIndex(of:")") else{throw DesignError.invalid("Malformed SVG paint ‘\(s)’.")}
        let id=s[s.index(s.startIndex,offsetBy:4)..<close].trimmingCharacters(in:CharacterSet.whitespaces.union(CharacterSet(charactersIn:"'\"")))
        let fallback=s[s.index(after:close)...].trimmingCharacters(in:.whitespaces)
        guard id.hasPrefix("#"),let gradient=byID[String(id.dropFirst())],["linearGradient","radialGradient"].contains(gradient.name) else {
            if !fallback.isEmpty{return try paint(fallback,ctx:ctx,shape:shape)}
            warn("Paint ‘\(s)’ isn't a gradient in this file (patterns aren't supported), so that fill or stroke was left out.");return Paint.none
        }
        let stops=try gradientStops(gradient)
        guard let first=stops.first,let last=stops.last else{return Paint.none}   // a gradient with no stops paints nothing
        if gradient.name=="radialGradient" {
            warn("Radial gradients import as their middle color; OpenHoop's gradient fill fades in a straight line.")
            return .flat(Self.color(at:0.5,stops))
        }
        if stops.count>2 {warn("Gradients with more than two colors import as a blend of their end colors; the middle colors were left out.")}
        guard first.color.hex != last.color.hex,let angle=try gradientAngle(gradient,ctx:ctx,shape:shape) else{return .flat(last.color)}
        return .blend(first.color,last.color,angle:angle)
    }
    /// `gradient` and the gradients it borrows from through href, nearest first (at most 10, so a loop can't hang).
    func gradientChain(_ gradient:SVGNode)->[SVGNode] {
        var chain=[gradient]
        while chain.count<10,let ref=chain.last!.attributes["href"] ?? chain.last!.attributes["xlink:href"],ref.hasPrefix("#"),
              let next=byID[String(ref.dropFirst())],["linearGradient","radialGradient"].contains(next.name),!chain.contains(where:{$0 === next}) {chain.append(next)}
        return chain
    }
    /// A gradient's color stops in order, offsets 0–1. They can come from a gradient it points at with href.
    func gradientStops(_ gradient:SVGNode)throws->[(offset:Double,color:ThreadColor)] {
        guard let holder=gradientChain(gradient).first(where:{$0.children.contains{$0.name=="stop"}}) else{return []}
        var stops:[(offset:Double,color:ThreadColor)]=[]
        for stop in holder.children where stop.name=="stop" {
            let p=properties(stop),text=(p["offset"] ?? "0").trimmingCharacters(in:.whitespaces)
            guard let number=Double(text.hasSuffix("%") ? String(text.dropLast()):text) else{throw DesignError.invalid("Invalid SVG gradient stop offset ‘\(text)’.")}
            // An offset below the one before counts as equal to it.
            let offset=max(stops.last?.offset ?? 0,min(1,max(0,text.hasSuffix("%") ? number/100:number)))
            if let color=try color(p["stop-color"] ?? "black",current:p["color"]){stops.append((offset,color))}
        }
        return stops
    }
    /// The color `t` (0–1) of the way along `stops`, mixed from the stops either side.
    static func color(at t:Double,_ stops:[(offset:Double,color:ThreadColor)])->ThreadColor {
        guard let after=stops.firstIndex(where:{$0.offset>=t}) else{return stops.last!.color}
        guard after>0 else{return stops[0].color}
        let a=stops[after-1],b=stops[after],f=b.offset>a.offset ? (t-a.offset)/(b.offset-a.offset):0
        func channel(_ shift:Int)->Int{let x=Double((a.color.hex>>shift)&255),y=Double((b.color.hex>>shift)&255);return Int((x+(y-x)*f).rounded())}
        let hex=channel(16)<<16|channel(8)<<8|channel(0)
        return ThreadColor(String(format:"#%06x",hex),hex)
    }
    /// The fill angle (in degrees, as Properties shows it) that makes the gradient's start color solid where the
    /// gradient starts and sheer toward its end. Only the direction is used: OpenHoop's gradient fill always fades
    /// across the whole shape. nil if the gradient has no direction (its two ends are the same point).
    func gradientAngle(_ gradient:SVGNode,ctx:Context,shape:SVGNode)throws->Double? {
        let chain=gradientChain(gradient)
        func value(_ key:String)->String?{chain.lazy.compactMap{$0.attributes[key]}.first}
        func coordinate(_ key:String,_ fallback:Double)throws->Double {
            guard let text=value(key)?.trimmingCharacters(in:.whitespaces) else{return fallback}
            if text.hasSuffix("%"){guard let n=Double(text.dropLast()) else{throw DesignError.invalid("Invalid SVG gradient position ‘\(text)’.")};return n/100}
            return try length(text)
        }
        let start=Point(try coordinate("x1",0),try coordinate("y1",0)),end=Point(try coordinate("x2",1),try coordinate("y2",0))
        // From the gradient's own space to millimeters: by default its numbers are fractions of the shape's box.
        var matrix=ctx.matrix
        if (value("gradientUnits") ?? "objectBoundingBox") != "userSpaceOnUse" {
            let points=try geometry(shape.name,shape.attributes,matrix:SVGMatrix()).flatMap(\.points)
            guard let minX=points.map(\.x).min(),let maxX=points.map(\.x).max(),let minY=points.map(\.y).min(),let maxY=points.map(\.y).max(),
                  maxX-minX>1e-9,maxY-minY>1e-9 else{return nil}
            matrix=matrix.joined(SVGMatrix(a:maxX-minX,d:maxY-minY,e:minX,f:minY))
        }
        if let transform=value("gradientTransform"){matrix=matrix.joined(try Self.transform(transform))}
        let along=end-start
        guard hypot(along.x,along.y)>1e-12 else{return nil}
        // Lines of one color run square to start→end in the gradient's own space; the matrix can skew them, so map a
        // line's direction and take the square to that. y is flipped: SVG runs down, the canvas up.
        func canvas(_ v:Point)->Point{Point(matrix.a*v.x+matrix.c*v.y,-(matrix.b*v.x+matrix.d*v.y))}
        let row=canvas(Point(-along.y,along.x)),forward=canvas(along)
        var across=Point(-row.y,row.x)
        if across.x*forward.x+across.y*forward.y<0 {across=Point(-across.x,-across.y)}
        guard hypot(across.x,across.y)>1e-12 else{return nil}
        // A fill at angle θ is solid on the side away from (−sin θ, cos θ) and sheer toward it (AreaEngine.sweptRows),
        // so that direction must point from the gradient's start to its end.
        return atan2(-across.x,across.y)*180 / .pi
    }
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
        if let hex=SVGStyles.colorNames[s]{return ThreadColor(value,hex)}
        if s.hasPrefix("#") {
            var digits=String(s.dropFirst());if digits.count==3{digits=digits.map{String(repeating:String($0),count:2)}.joined()}
            if digits.count==6,let hex=Int(digits,radix:16){return ThreadColor(value,hex)}
        }
        if s.hasPrefix("rgb("),s.hasSuffix(")") {
            let parts=s.dropFirst(4).dropLast().split(whereSeparator:{$0=="," || $0.isWhitespace})
            if parts.count==3 {var hex=0;for part in parts {let percent=part.hasSuffix("%"),text=percent ? String(part.dropLast()):String(part);guard let value=Double(text),value.isFinite else{throw DesignError.invalid("Invalid SVG color.")};let n=Int(max(0,min(255,(percent ? value*2.55:value).rounded())));hex=(hex<<8)|n};return ThreadColor(value,hex)}
        }
        throw DesignError.invalid("Unsupported SVG paint ‘\(value)’. Convert colors to six-digit #RRGGBB, rgb(r,g,b) or a CSS color name before importing.")
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
        return SVGMatrix(a:unit,d:unit).joined(try fit(box,width:w,height:h,aspect:a["preserveAspectRatio"]))
    }
    /// Maps viewBox `box` (x, y, width, height) onto a `w` × `h` area as preserveAspectRatio `aspect` says.
    func fit(_ box:[Double],width w:Double,height h:Double,aspect text:String?)throws->SVGMatrix {
        var sx=w/box[2],sy=h/box[3],dx=0.0,dy=0.0
        let aspect=(text ?? "xMidYMid meet").split(separator:" ").map(String.init)
        if aspect.first != "none" {
            guard let align=aspect.first,["xMinYMin","xMidYMin","xMaxYMin","xMinYMid","xMidYMid","xMaxYMid","xMinYMax","xMidYMax","xMaxYMax"].contains(align),aspect.count<=2,aspect.count==1 || aspect[1]=="meet" else{throw DesignError.invalid("Only preserveAspectRatio meet or none is supported; slice requires clipping.")}
            sx=min(sx,sy);sy=sx
            dx=(w-box[2]*sx)*(align.contains("xMid") ? 0.5:align.contains("xMax") ? 1:0)
            dy=(h-box[3]*sy)*(align.contains("YMid") ? 0.5:align.contains("YMax") ? 1:0)
        }
        return SVGMatrix(a:sx,d:sy,e:dx-box[0]*sx,f:dy-box[1]*sy)
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
