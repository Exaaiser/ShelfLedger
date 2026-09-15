import XCTest
@testable import ShelfLedger

final class PriceAnalysisTests: XCTestCase {
    private let analysis = PriceAnalysisUseCase()
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    private func date(_ day: String) -> Date { ISO8601DateFormatter().date(from: day + "T12:00:00Z")! }
    private func record(_ day: String, _ price: Decimal, store: String = "branch", currency: String = "USD") -> PriceObservation {
        PriceObservation(id: day + store, barcode: try! Barcode("070847811169"), money: Money(amount: price, currency: currency), observedAt: date(day),
            store: Store(id: store, name: "Market", coordinate: GeoPoint(latitude: 40.44, longitude: -79.99), postalCode: nil, address: nil),
            source: .personal, proofURL: nil, isDiscounted: false, priceBasis: nil)
    }
    func testIncreaseDecreaseAndUnchangedPercentages() throws {
        let old = record("2026-01-01", 4)
        let increase = try XCTUnwrap(analysis.change(from: old, to: record("2026-02-01", 5)))
        XCTAssertEqual(increase.amount, 1); XCTAssertEqual(increase.percentage, 25)
        let decrease = try XCTUnwrap(analysis.change(from: old, to: record("2026-02-01", 3)))
        XCTAssertEqual(decrease.amount, -1); XCTAssertEqual(decrease.percentage, -25)
        XCTAssertEqual(analysis.change(from: old, to: record("2026-02-01", 4))?.percentage, 0)
    }
    func testComparisonRejectsDifferentBranchesCurrenciesAndReversedDates() {
        let old = record("2026-01-01", 3)
        XCTAssertNil(analysis.change(from: old, to: record("2026-02-01", 4, store: "other")))
        XCTAssertNil(analysis.change(from: old, to: record("2026-02-01", 4, currency: "EUR")))
        XCTAssertNil(analysis.change(from: old, to: record("2025-01-01", 4)))
        XCTAssertNil(analysis.change(from: record("2026-01-01", 0), to: record("2026-02-01", 4)))
        XCTAssertNil(analysis.change(from: nil, to: old))
    }
    func testLatestTransitionSkipsRepeatedUnchangedObservations() {
        let values = [record("2026-01-01", 3), record("2026-02-01", 4), record("2026-03-01", 4)]
        XCTAssertEqual(analysis.previousDifferentPrice(before: values[2], in: values)?.money.amount, 3)
        XCTAssertEqual(analysis.previousDifferentPrice(before: values[2], in: values)?.observedAt, date("2026-01-01"))
        XCTAssertNil(analysis.previousDifferentPrice(before: values[2], in: Array(values.suffix(2))))
    }
    func testExactDayDoesNotSilentlyBorrowAnEarlierPrice() {
        let values = [record("2026-01-02", 3), record("2026-01-10", 4)]
        XCTAssertNil(analysis.observation(on: date("2026-01-05"), in: values, policy: .exactDay, calendar: calendar))
        XCTAssertEqual(analysis.observation(on: date("2026-01-05"), in: values, policy: .lastRecorded, calendar: calendar)?.money.amount, 3)
        XCTAssertNil(analysis.observation(on: date("2026-01-01"), in: values, policy: .lastRecorded, calendar: calendar))
    }
    func testLastRecordedEndpointsRetainActualDatesAndCanResolveSameRecord() throws {
        let value = record("2026-01-02", 3)
        let before = analysis.observation(on: date("2026-01-05"), in: [value], policy: .lastRecorded, calendar: calendar)
        let after = analysis.observation(on: date("2026-01-20"), in: [value], policy: .lastRecorded, calendar: calendar)
        let change = try XCTUnwrap(analysis.change(from: before, to: after))
        XCTAssertEqual(change.before.id, change.after.id)
        XCTAssertEqual(change.before.observedAt, date("2026-01-02"))
    }
    func testMonthlyAnalysisKeepsMissingMonthsAndNeverSkipsAcrossGap() {
        let values = [record("2025-12-29", 3), record("2026-01-10", 4), record("2026-03-20", 5)]
        let rows = analysis.months(from: date("2026-01-01"), through: date("2026-03-31"), in: values, calendar: calendar)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].observation?.money.amount, 5)
        XCTAssertNil(rows[0].change)
        XCTAssertNil(rows[1].observation)
        XCTAssertEqual(rows[2].change?.percentage, Decimal(100) / 3)
    }
    func testMonthlyClosingRecordRespectsBothCustomBoundaries() {
        let values = [record("2026-01-05", 3), record("2026-01-20", 4), record("2026-02-05", 5), record("2026-02-20", 6)]
        let rows = analysis.months(from: date("2026-01-15"), through: date("2026-02-10"), in: values, calendar: calendar)
        XCTAssertEqual(rows.map { $0.observation?.money.amount }, [5, 4])
        XCTAssertEqual(rows[0].change?.amount, 1)
    }
    func testMonthlyAnalysisSupportsOlderYearsAndMoreThanThreeMonths() {
        let rows = analysis.months(from: date("2020-01-01"), through: date("2021-12-31"), in: [record("2020-01-15", 2)], calendar: calendar)
        XCTAssertEqual(rows.count, 24)
        XCTAssertEqual(rows.last?.observation?.money.amount, 2)
        XCTAssertNil(rows.first?.observation)
    }
}
