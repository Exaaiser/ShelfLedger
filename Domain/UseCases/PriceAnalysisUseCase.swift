import Foundation

enum ObservationDatePolicy: String, CaseIterable {
    case exactDay = "Exact day"
    case lastRecorded = "On or before"
}

struct PriceChange: Equatable {
    let before: PriceObservation
    let after: PriceObservation
    var amount: Decimal { after.money.amount - before.money.amount }
    var percentage: Decimal { amount / before.money.amount * 100 }
}

struct MonthlyObservation: Identifiable {
    var id: Date { month }
    let month: Date
    let observation: PriceObservation?
    let previous: PriceObservation?
    var change: PriceChange? { PriceAnalysisUseCase().change(from: previous, to: observation) }
    var difference: Decimal? { change?.amount }
}

struct PriceAnalysisUseCase {
    func ordered(_ values: [PriceObservation]) -> [PriceObservation] {
        values.sorted { $0.observedAt == $1.observedAt ? $0.id > $1.id : $0.observedAt > $1.observedAt }
    }
    func observation(on date: Date, in values: [PriceObservation], policy: ObservationDatePolicy, calendar: Calendar = .current) -> PriceObservation? {
        ordered(values).first {
            policy == .exactDay ? calendar.isDate($0.observedAt, inSameDayAs: date) :
                calendar.startOfDay(for: $0.observedAt) <= calendar.startOfDay(for: date)
        }
    }
    func change(from before: PriceObservation?, to after: PriceObservation?) -> PriceChange? {
        guard let before, let after, before.money.amount > 0, after.money.amount > 0,
              before.barcode.identity == after.barcode.identity, before.store.id == after.store.id,
              before.money.currency == after.money.currency, before.observedAt <= after.observedAt else { return nil }
        return PriceChange(before: before, after: after)
    }
    func previousDifferentPrice(before latest: PriceObservation, in values: [PriceObservation]) -> PriceObservation? {
        ordered(values).first {
            $0.observedAt < latest.observedAt && $0.store.id == latest.store.id &&
            $0.barcode.identity == latest.barcode.identity && $0.money.currency == latest.money.currency &&
            $0.money.amount > 0 && $0.money.amount != latest.money.amount
        }
    }
    func months(from start: Date, through end: Date, in values: [PriceObservation], calendar: Calendar = .current) -> [MonthlyObservation] {
        guard start <= end, let first = calendar.dateInterval(of: .month, for: start)?.start,
              var month = calendar.dateInterval(of: .month, for: end)?.start else { return [] }
        let ordered = ordered(values)
        let endDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
        var rows: [MonthlyObservation] = []
        while month >= first {
            let interval = calendar.dateInterval(of: .month, for: month)!
            let priorMonth = calendar.date(byAdding: .month, value: -1, to: month)!
            let priorInterval = calendar.dateInterval(of: .month, for: priorMonth)!
            let current = ordered.first { interval.contains($0.observedAt) && $0.observedAt >= calendar.startOfDay(for: start) && $0.observedAt < endDay }
            let previous = ordered.first { priorInterval.contains($0.observedAt) }
            rows.append(MonthlyObservation(month: month, observation: current, previous: previous))
            month = priorMonth
        }
        return rows
    }
}
