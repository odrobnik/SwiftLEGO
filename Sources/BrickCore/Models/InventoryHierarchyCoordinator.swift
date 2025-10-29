import Foundation

@MainActor
public extension Part {
    func synchronizeSubparts(to parentUnits: Int) {
        guard !subparts.isEmpty else { return }

        let clampedUnits = max(0, min(parentUnits, quantityNeeded))
        let parentTotalNeeded = max(quantityNeeded, 1)

        for child in subparts {
            let desired = desiredQuantity(for: child, parentUnits: clampedUnits, parentTotalNeeded: parentTotalNeeded)
            if child.quantityHave != desired {
                child.quantityHave = desired
            }
            child.synchronizeSubparts(to: desired)
        }
    }

    func propagateCompletionUpwardsIfNeeded() {
        if let parent = parentPart {
            parent.updateCompletionFromSubpartsIfNeeded()
        } else if let owningFigure = minifigure {
            owningFigure.updateCompletionFromPartsIfNeeded()
        }
    }

    func updateCompletionFromSubpartsIfNeeded() {
        guard let completedUnits = completedUnitsFromSubparts(),
              completedUnits > quantityHave else { return }

        quantityHave = completedUnits
        propagateCompletionUpwardsIfNeeded()
    }

    private func desiredQuantity(for child: Part, parentUnits: Int, parentTotalNeeded: Int) -> Int {
        guard parentUnits > 0 else { return 0 }
        let childTotalNeeded = child.quantityNeeded
        guard childTotalNeeded > 0 else { return 0 }

        let numerator = childTotalNeeded * parentUnits
        let denominator = max(parentTotalNeeded, 1)
        let desired = (numerator + denominator - 1) / denominator

        return min(childTotalNeeded, desired)
    }

    private func completedUnitsFromSubparts() -> Int? {
        guard !subparts.isEmpty else { return nil }
        guard quantityNeeded > 0 else { return nil }

        var minUnits = quantityNeeded
        var hasRelevantChild = false

        for child in subparts {
            let totalNeeded = child.quantityNeeded
            guard totalNeeded > 0 else { continue }
            hasRelevantChild = true
            let candidate = (child.quantityHave * quantityNeeded) / totalNeeded
            let clamped = min(quantityNeeded, candidate)
            minUnits = min(minUnits, clamped)
        }

        guard hasRelevantChild else { return nil }
        return minUnits
    }
}

@MainActor
public extension Minifigure {
    func synchronizeParts(to figureUnits: Int) {
        guard !parts.isEmpty else { return }

        let clampedUnits = max(0, min(figureUnits, quantityNeeded))
        let figureTotalNeeded = max(quantityNeeded, 1)

        for part in parts {
            let desired = desiredQuantity(for: part, figureUnits: clampedUnits, figureTotalNeeded: figureTotalNeeded)
            if part.quantityHave != desired {
                part.quantityHave = desired
            }
            part.synchronizeSubparts(to: desired)
        }
    }

    func updateCompletionFromPartsIfNeeded() {
        guard let completedUnits = completedUnitsFromParts(),
              completedUnits > quantityHave else { return }

        quantityHave = completedUnits
    }

    private func desiredQuantity(for part: Part, figureUnits: Int, figureTotalNeeded: Int) -> Int {
        guard figureUnits > 0 else { return 0 }
        let partTotalNeeded = part.quantityNeeded
        guard partTotalNeeded > 0 else { return 0 }

        let numerator = partTotalNeeded * figureUnits
        let denominator = max(figureTotalNeeded, 1)
        let desired = (numerator + denominator - 1) / denominator

        return min(partTotalNeeded, desired)
    }

    private func completedUnitsFromParts() -> Int? {
        guard !parts.isEmpty else { return nil }
        guard quantityNeeded > 0 else { return nil }

        var minUnits = quantityNeeded
        var hasRelevantPart = false

        for part in parts {
            let totalNeeded = part.quantityNeeded
            guard totalNeeded > 0 else { continue }
            hasRelevantPart = true
            let candidate = (part.quantityHave * quantityNeeded) / totalNeeded
            let clamped = min(quantityNeeded, candidate)
            minUnits = min(minUnits, clamped)
        }

        guard hasRelevantPart else { return nil }
        return minUnits
    }
}
