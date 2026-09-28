import Combine
import Foundation

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

    func saveNamedPlan() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        savedPlans.removeAll { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
        savedPlans.insert(TrainingPlanTemplate(name: trimmedName, blocks: blocks), at: 0)
        store.saveSavedPlans(savedPlans)
    }

    func deletePlan(_ plan: TrainingPlanTemplate) {
        savedPlans.removeAll { $0.id == plan.id }
        store.saveSavedPlans(savedPlans)
    }
}
