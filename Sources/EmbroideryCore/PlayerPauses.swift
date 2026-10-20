// Where the stitch player pauses when "Pause at trims" is on: everywhere the machine cuts the thread, stops, or
// changes thread, so a preview can be stepped through the way the design sews out.
import Foundation

extension StitchPlan {
    /// The places the player pauses, as how many commands are shown at that moment (each pause comes right after a
    /// trim, stop or thread change). Several in a row, such as a trim then a thread change, pause once, after the
    /// last of them; those after the final stitch are left out, since the player stops at the end anyway.
    public var machinePauses: [Int] {
        guard let lastStitch = commands.lastIndex(where: { $0.op == .stitch }) else { return [] }
        func isPause(_ command: StitchCommand) -> Bool { [.trim, .stop, .colorChange].contains(command.op) }
        var pauses: [Int] = []
        for index in commands.indices where index < lastStitch {
            // Skip this one if the next command pauses too: the run pauses once, after its last command.
            if isPause(commands[index]) && !isPause(commands[index + 1]) { pauses.append(index + 1) }
        }
        return pauses
    }
}
