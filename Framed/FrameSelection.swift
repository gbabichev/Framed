import Foundation

/// Grid selection is independent of the canvas frame until Use Frame is pressed.
nonisolated struct FrameSelection: Equatable {
    private(set) var ids: Set<UUID> = []
    private var anchor: UUID?

    mutating func select(_ id: UUID, visible: [UUID], toggle: Bool, extend: Bool) {
        if extend, let anchor, let start = visible.firstIndex(of: anchor), let end = visible.firstIndex(of: id) {
            let range = Set(visible[min(start, end)...max(start, end)])
            ids = toggle ? ids.union(range) : range
        } else if toggle {
            if !ids.insert(id).inserted { ids.remove(id) }
            anchor = id
        } else {
            ids = [id]
            anchor = id
        }
    }

    mutating func selectAll(_ ids: [UUID]) { self.ids = Set(ids); anchor = ids.first }
    mutating func clear() { ids = []; anchor = nil }
    mutating func retain(_ existing: Set<UUID>) {
        ids.formIntersection(existing)
        if let anchor, !existing.contains(anchor) { self.anchor = nil }
    }
}
