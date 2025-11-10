import Foundation

public extension Part {
    var missingQuantity: Int {
        max(quantityNeeded - quantityHave, 0)
    }

    func hasOwnedQuantityInHierarchy() -> Bool {
        if quantityHave > 0 {
            return true
        }

        for child in subparts where child.inventorySection == .regular {
            if child.hasOwnedQuantityInHierarchy() {
                return true
            }
        }

        return false
    }

    func hasUniformMissingSubparts() -> Bool {
        guard !subparts.isEmpty else { return false }
        let parentMissing = missingQuantity
        guard parentMissing > 0 else { return false }
        let parentNeeded = quantityNeeded
        guard parentNeeded > 0 else { return false }

        var consideredChild = false

        for child in subparts where child.inventorySection == .regular {
            consideredChild = true
            let childNeeded = child.quantityNeeded
            let childMissing = child.missingQuantity

            if childNeeded == 0 {
                if childMissing > 0 {
                    return false
                }
                continue
            }

            if childMissing * parentNeeded != parentMissing * childNeeded {
                return false
            }
        }

        return consideredChild
    }
}
