import Foundation

/// Needle data stays separate from editable outlines and is never resampled.
public struct RawStitch:Codable,Hashable,Sendable {
    public var op:StitchOperation
    public var point:Point
    public init(_ op:StitchOperation,_ point:Point){self.op=op;self.point=point}
}
public struct RawStitchBlock:Codable,Hashable,Sendable {
    public var start:Point
    public var commands:[RawStitch]
    public var colorChangeBefore:Bool
    public var sourceFormat:String
    public init(start:Point,commands:[RawStitch],colorChangeBefore:Bool=false,sourceFormat:String){self.start=start;self.commands=commands;self.colorChangeBefore=colorChangeBefore;self.sourceFormat=sourceFormat}
}
public enum MachineImport {
    /// Keep source placement and all decoded controls. Each color boundary starts a block,
    /// including repeated colors and empty blocks between consecutive color changes.
    public static func objects(from plan:StitchPlan,format:String,name:String)throws->[RunObject] {
        guard MachineFormat(rawValue:format) != nil,plan.commands.count<=100_000,
              !plan.threads.isEmpty,plan.threads.count<=1000,
              plan.commands.last?.op == .end,
              plan.commands.dropLast().allSatisfy({$0.op != .end}),plan.stitchCount>0 else{throw DesignError.invalid("Invalid or oversized imported stitch plan.")}
        guard plan.threads.allSatisfy({(0...0xffffff).contains($0.hex) && $0.name.count<=256}) else{throw DesignError.invalid("Invalid imported thread colors.")}
        var objects:[RunObject]=[],commands:[RawStitch]=[],position=Point(0,0),start=Point(0,0),thread=plan.commands[0].thread,change=false
        func finish() {
            var object=RunObject(name:"\(name) · block \(objects.count+1)",nodes:[],color:plan.threads[thread])
            object.rawStitches=RawStitchBlock(start:start,commands:commands,colorChangeBefore:change,sourceFormat:format)
            object.tieIn=false;object.tieOut=false;object.trimAfter=false
            objects.append(object)
        }
        for command in plan.commands {
            try Task.checkCancellation()
            guard command.point.finite,abs(command.point.x)<=10000,abs(command.point.y)<=10000,plan.threads.indices.contains(command.thread) else{throw DesignError.invalid("Invalid imported stitch coordinate or thread.")}
            if command.op == .colorChange {
                guard command.point.distance(to:position)<0.00001 else{throw DesignError.invalid("A color command moves the needle. This file needs a different decoder.")}
                finish();commands=[];start=position;thread=command.thread;change=true
            } else if command.op == .end {finish()}
            else {
                guard command.thread==thread else{throw DesignError.invalid("Imported thread changes are missing a color boundary.")}
                if command.op == .trim || command.op == .stop {
                    guard command.point.distance(to:position)<0.00001 else{throw DesignError.invalid("A control command moves the needle unexpectedly.")}
                }
                commands.append(RawStitch(command.op,command.point));position=command.point
            }
        }
        var check=Design();check.objects=objects;try check.validate();return objects
    }
}
