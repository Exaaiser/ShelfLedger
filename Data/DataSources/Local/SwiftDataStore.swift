import Foundation
import SwiftData

@Model
final class CachedSnapshotRecord {
    @Attribute(.unique) var key: String
    var payload: Data
    var updatedAt: Date
    init(key: String, payload: Data, updatedAt: Date) { self.key = key; self.payload = payload; self.updatedAt = updatedAt }
}

@Model
final class PersonalObservationRecord {
    @Attribute(.unique) var observationID: String
    var barcode: String
    var payload: Data
    init(observationID: String, barcode: String, payload: Data) {
        self.observationID = observationID; self.barcode = barcode; self.payload = payload
    }
}

@MainActor
final class SwiftDataStore {
    let container: ModelContainer
    private let context: ModelContext
    init(inMemory: Bool = false, url: URL? = nil) throws {
        let schema = Schema([CachedSnapshotRecord.self, PersonalObservationRecord.self])
        // Keep development data isolated from the original app.
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration("ShelfLedgerVerifiedV2", schema: schema, url: url) }
        else { configuration = ModelConfiguration("ShelfLedgerVerifiedV2", schema: schema, isStoredInMemoryOnly: inMemory) }
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }
    func snapshot(key: String) throws -> ProductSnapshot? {
        let query = FetchDescriptor<CachedSnapshotRecord>(predicate: #Predicate { $0.key == key })
        guard let row = try context.fetch(query).first else { return nil }
        return try JSONDecoder().decode(ProductSnapshot.self, from: row.payload)
    }
    func saveSnapshot(_ snapshot: ProductSnapshot, key: String) throws {
        let payload = try JSONEncoder().encode(snapshot)
        let query = FetchDescriptor<CachedSnapshotRecord>(predicate: #Predicate { $0.key == key })
        if let row = try context.fetch(query).first { row.payload = payload; row.updatedAt = snapshot.fetchedAt }
        else { context.insert(CachedSnapshotRecord(key: key, payload: payload, updatedAt: snapshot.fetchedAt)) }
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func onlinePriceHistory(barcode: Barcode) throws -> [OnlineOffer] {
        let key = "online-history-v1:\(barcode.identity)"
        let query = FetchDescriptor<CachedSnapshotRecord>(predicate: #Predicate { $0.key == key })
        guard let row = try context.fetch(query).first else { return [] }
        return try JSONDecoder().decode([OnlineOffer].self, from: row.payload)
    }
    func saveOnlinePriceHistory(_ offers: [OnlineOffer], barcode: Barcode) throws -> [OnlineOffer] {
        let key = "online-history-v1:\(barcode.identity)"
        let existing = try onlinePriceHistory(barcode: barcode)
        let merged = OnlinePriceHistoryUseCase().merge(existing, offers, barcode: barcode)
        guard merged != existing else { return existing }
        let payload = try JSONEncoder().encode(merged)
        let query = FetchDescriptor<CachedSnapshotRecord>(predicate: #Predicate { $0.key == key })
        if let row = try context.fetch(query).first { row.payload = payload; row.updatedAt = Date() }
        else { context.insert(CachedSnapshotRecord(key: key, payload: payload, updatedAt: Date())) }
        do { try context.save() } catch { context.rollback(); throw error }
        return merged
    }
    func recentProducts() throws -> [Product] {
        var query = FetchDescriptor<CachedSnapshotRecord>(predicate: #Predicate { !$0.key.starts(with: "online-history-v1:") }, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        query.fetchLimit = 100
        var seen = Set<String>()
        return try context.fetch(query).compactMap {
            guard let snapshot = try? JSONDecoder().decode(ProductSnapshot.self, from: $0.payload), seen.insert(snapshot.product.id).inserted else { return nil }
            return snapshot.product
        }
    }
    func personalObservations(barcode: Barcode) throws -> [PriceObservation] {
        let identity = barcode.identity
        let query = FetchDescriptor<PersonalObservationRecord>(predicate: #Predicate { $0.barcode == identity })
        return try context.fetch(query).map { try JSONDecoder().decode(PriceObservation.self, from: $0.payload) }
    }
    func saveObservation(_ observation: PriceObservation) throws {
        let id = observation.id
        let query = FetchDescriptor<PersonalObservationRecord>(predicate: #Predicate { $0.observationID == id })
        guard try context.fetch(query).isEmpty else { return } // Stable submission ID makes retries idempotent.
        let payload = try JSONEncoder().encode(observation)
        context.insert(PersonalObservationRecord(observationID: id, barcode: observation.barcode.identity, payload: payload))
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
