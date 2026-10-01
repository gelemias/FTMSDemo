import Combine
import Foundation

enum TrainingPlanSaveResult {
    case saved
    case duplicate(TrainingPlanTemplate)
}

@MainActor
final class TrainingPlanViewModel: ObservableObject {
    @Published var blocks: [TrainingPlanBlock] = TrainingPlan.todayBlocks
    @Published var name = "Speed builder"
    @Published private(set) var savedPlans: [TrainingPlanTemplate] = []

    private let store: TrainingPlanStore
    private var didLoad = false

    init(store: TrainingPlanStore? = nil) {
        self.store = store ?? TrainingPlanStore()
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        savedPlans = store.loadSavedPlans()
        blocks = store.loadBlocks()
    }

    func saveBlocks() { store.saveBlocks(blocks) }

    @discardableResult
    func saveNamedPlan() -> TrainingPlanSaveResult? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        if let duplicate = savedPlans.first(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            return .duplicate(duplicate)
        }
        savedPlans.insert(TrainingPlanTemplate(name: trimmedName, blocks: blocks), at: 0)
        store.saveSavedPlans(savedPlans)
        return .saved
    }

    func updateNamedPlan(_ plan: TrainingPlanTemplate) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = savedPlans.firstIndex(where: { $0.id == plan.id }) else { return }
        savedPlans[index] = TrainingPlanTemplate(
            id: plan.id,
            name: trimmedName,
            blocks: blocks,
            createdAt: plan.createdAt
        )
        let updatedPlan = savedPlans.remove(at: index)
        savedPlans.insert(updatedPlan, at: 0)
        store.saveSavedPlans(savedPlans)
    }

    func deletePlan(_ plan: TrainingPlanTemplate) {
        savedPlans.removeAll { $0.id == plan.id }
        store.saveSavedPlans(savedPlans)
    }
}
