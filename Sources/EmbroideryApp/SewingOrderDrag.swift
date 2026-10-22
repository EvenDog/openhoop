// Dragging rows of the sewing order table to a new place in the order. While
// objects are dragged, a line shows above the row they'd sew before (or at the end, below the last row); letting go
// moves them there as one undo step (Design.moveInSewingOrder).
import SwiftUI
import EmbroideryCore

@MainActor enum SewingOrderDrag {
    /// The objects being dragged, from when the drag starts until it's dropped.
    static var ids: Set<UUID>?
    /// The drag's contents. Like a panel drag (PanelDrag), only a marker travels: the objects wait in `ids`.
    static func provider(for ids: Set<UUID>) -> NSItemProvider {
        Self.ids = ids
        return NSItemProvider(object: "embroidery-objects" as NSString)
    }
    /// What dragging a row moves: the whole selection when the row is part of it, otherwise the row's own objects.
    static func dragged(_ row: Set<UUID>, state: EditorState) -> Set<UUID> {
        row.isSubset(of: state.selection) ? state.selection : row
    }
}

/// Takes dragged objects on a row of the sewing order list (or the space after the last one). `place` is where they'd
/// land: the sewing order index of the row's first object (or the object count, for the end). `target` is where the
/// line shows, shared by every row of the list.
struct SewingOrderDrop: DropDelegate {
    let state: EditorState
    let place: Int
    @Binding var target: Int?

    /// Where the objects really land: a place inside a group, lettering or branch moves to that unit's end.
    private var landing: Int {
        state.design.sewingUnits.first { $0.lowerBound < place && place < $0.upperBound }?.upperBound ?? place
    }
    func validateDrop(info: DropInfo) -> Bool { SewingOrderDrag.ids != nil }
    func dropEntered(info: DropInfo) { target = landing }
    func dropUpdated(info: DropInfo) -> DropProposal? { target = landing; return DropProposal(operation: .move) }
    func dropExited(info: DropInfo) { if target == landing { target = nil } }
    func performDrop(info: DropInfo) -> Bool {
        defer { target = nil; SewingOrderDrag.ids = nil }
        guard let ids = SewingOrderDrag.ids else { return false }
        var next = state.design
        guard next.moveInSewingOrder(ids, to: landing) else { return false }
        guard state.edit("Move in Sewing Order", { $0 = next }) else { return false }
        state.selection = ids   // what moved stays selected, so it's easy to see where it went
        return true
    }
}

extension View {
    /// Lets a sewing order row be dragged (moving `ids`, or the selection they're part of), and dropped on: a line
    /// shows above it when objects would land at `place`.
    func sewingOrderRow(state: EditorState, ids: Set<UUID>, place: Int, target: Binding<Int?>) -> some View {
        self
            .overlay(alignment: .top) { if target.wrappedValue == place { Capsule().fill(Theme.accent).frame(height: 3).offset(y: -1.5) } }
            .onDrag { SewingOrderDrag.provider(for: SewingOrderDrag.dragged(ids, state: state)) }
            .onDrop(of: [.plainText], delegate: SewingOrderDrop(state: state, place: place, target: target))
    }

    /// The space after the last row: dropping there moves the objects to the end of the sewing order.
    func sewingOrderEnd(state: EditorState, target: Binding<Int?>) -> some View {
        let end = state.design.objects.count
        return self
            .frame(maxWidth: .infinity, minHeight: 28).contentShape(Rectangle())
            .overlay(alignment: .top) { if target.wrappedValue == end { Capsule().fill(Theme.accent).frame(height: 3).offset(y: -1.5) } }
            .onDrop(of: [.plainText], delegate: SewingOrderDrop(state: state, place: end, target: target))
    }
}
