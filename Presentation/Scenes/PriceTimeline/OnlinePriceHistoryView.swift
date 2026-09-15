import SwiftUI
import Charts

struct OnlinePriceHistoryView: View {
    let records: [OnlineOffer]
    let listing: OnlineOffer
    @Environment(\.dismiss) private var dismiss
    @State private var start = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
    @State private var end = Date()
    @State private var policy: ObservationDatePolicy = .lastRecorded
    private let history = OnlinePriceHistoryUseCase()
    private var series: [OnlineOffer] {
        records.filter { history.seriesID($0) == history.seriesID(listing) }.sorted { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
    }
    private var before: OnlineOffer? { history.observation(on: start, in: series, policy: policy) }
    private var after: OnlineOffer? { history.observation(on: end, in: series, policy: policy) }
    private var visibleRecords: [OnlineOffer] {
        let calendar = Calendar.current
        return series.filter {
            guard let date = $0.updatedAt else { return false }
            return calendar.startOfDay(for: date) >= calendar.startOfDay(for: start) && calendar.startOfDay(for: date) <= calendar.startOfDay(for: end)
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(listing.merchant).font(.title2.bold())
                        Text(listing.title).font(.subheadline)
                        Text("\(listing.sourceName) · online prices").font(.caption).foregroundStyle(.secondary)
                        if let qualifier = listing.priceQualifier { Text(qualifier).font(.caption).foregroundStyle(.secondary) }
                    }
                    if let latest = series.last {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Latest dated listing").font(.headline)
                            Text(latest.money.formatted).font(.largeTitle.bold())
                            if let previous = series.last(where: { $0.updatedAt! < latest.updatedAt! && $0.money.amount != latest.money.amount }) {
                                OnlinePriceChangeView(before: previous, after: latest)
                            } else { Text("One price so far. Check again later to track changes.").font(.subheadline).foregroundStyle(.secondary) }
                            if let date = latest.updatedAt { Text("Source date: \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        InfoCard(title: "No dated online history yet", message: "This listing has no usable source date. It remains available in the price list.")
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Compare dates").font(.title3.bold())
                        DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
                        DatePicker("To", selection: $end, in: start...Date(), displayedComponents: .date)
                        Picker("Date matching", selection: $policy) {
                            ForEach(ObservationDatePolicy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Text(policy == .exactDay ? "Use only records dated on each selected day." : "Use the latest source record on or before each selected day. Actual record dates appear below.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let before, let after { OnlinePriceChangeView(before: before, after: after) }
                        else { Text("No matching record for one or both dates.").foregroundStyle(.secondary) }
                        Button("Show all recorded dates") {
                            start = series.first?.updatedAt ?? start
                            end = max(start, series.last?.updatedAt ?? Date())
                        }.font(.subheadline.weight(.semibold))
                    }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
                    if !visibleRecords.isEmpty {
                        Chart(visibleRecords) { record in
                            PointMark(x: .value("Source date", record.updatedAt!), y: .value("USD", record.money.chartValue))
                                .foregroundStyle(AppTheme.accent)
                        }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 210)
                        Text("Points show dated source records. This device keeps records from lookups; prices aren't checked continuously.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recorded online prices").font(.title3.bold())
                        ForEach(visibleRecords.reversed()) { record in
                            HStack {
                                Text(record.updatedAt!.formatted(date: .abbreviated, time: .omitted))
                                Spacer()
                                Text(record.money.formatted).fontWeight(.semibold)
                            }.font(.subheadline)
                            Divider()
                        }
                    }
                    Link("Open source website", destination: listing.url)
                    Text("Compare the same package and seller. Shipping, taxes and membership conditions may differ. These are online records, not nearby shelf prices.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.background(AppTheme.background)
                .navigationTitle("Online price history").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct OnlinePriceChangeView: View {
    let before: OnlineOffer
    let after: OnlineOffer
    private var difference: Decimal { after.money.amount - before.money.amount }
    private var percentage: Decimal { difference / before.money.amount * 100 }
    private var color: Color { difference > 0 ? .red : difference < 0 ? AppTheme.accent : .secondary }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(before.money.formatted) → \(after.money.formatted)").font(.headline)
            Label("\(difference > 0 ? "+" : "")\(Money(amount: difference, currency: after.money.currency).formatted) (\(percentage > 0 ? "+" : "")\(percentage.formatted(.number.precision(.fractionLength(1))))%)",
                systemImage: difference > 0 ? "arrow.up.right" : difference < 0 ? "arrow.down.right" : "minus")
                .font(.subheadline.weight(.semibold)).foregroundStyle(color)
            if let first = before.updatedAt, let last = after.updatedAt {
                Text("\(first.formatted(date: .abbreviated, time: .omitted)) → \(last.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
