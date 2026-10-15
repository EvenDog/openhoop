import Foundation

public enum MachineFormat:String,CaseIterable,Sendable {
    case pes,dst,exp,jef,vp3,xxx,pec
    public var title:String {rawValue.uppercased()}
    public var description:String {
        switch self {
        case .pes:return "PES — Brother / Baby Lock"
        case .dst:return "DST — Tajima"
        case .exp:return "EXP — Melco / Bernina"
        case .jef:return "JEF — Janome"
        case .vp3:return "VP3 — Husqvarna / Pfaff"
        case .xxx:return "XXX — Singer"
        case .pec:return "PEC — Brother"
        }
    }
}
