import SwiftUI

struct PriceChangeBadge: View {
    let change: PriceChange
    var color: Color { change.amount > 0 ? .red : change.amount < 0 ? AppTheme.accent : .secondary }
    var body: some View {
        Label {
            Text("\(change.amount > 0 ? "+" : "")\(Money(amount: change.amount, currency: change.after.money.currency).formatted) (\(change.percentage > 0 ? "+" : "")\(change.percentage.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US"))))%)")
        } icon: {
            Image(systemName: change.amount > 0 ? "arrow.up.right" : change.amount < 0 ? "arrow.down.right" : "minus")
        }
        .font(.subheadline.weight(.semibold)).foregroundStyle(color)
        .accessibilityLabel("\(change.amount > 0 ? "Increase" : change.amount < 0 ? "Decrease" : "Unchanged"): \(Money(amount: abs(change.amount), currency: change.after.money.currency).formatted), \(abs(change.percentage).formatted(.number.precision(.fractionLength(0...2)))) percent")
    }
}

struct PriceComparisonView: View {
    @ObservedObject var viewModel: PriceTimelineViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if viewModel.referenceStore == nil {
                        InfoCard(title: viewModel.availabilityTitle, message: viewModel.availabilityMessage)
                    }
                    if viewModel.isWiderArea { Text(viewModel.coverageLabel).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent) }
                    if let store = viewModel.referenceStore {
                        Label(store.displayName, systemImage: "mappin.and.ellipse").font(.headline)
                        Text("Both prices come from this store and this exact product.").font(.caption).foregroundStyle(.secondary)
                    }
                    DatePicker("From", selection: $viewModel.comparisonStart, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("comparisonStartDate")
                    DatePicker("To", selection: $viewModel.comparisonEnd, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("comparisonEndDate")
                    Picker("Match dates", selection: $viewModel.comparisonPolicy) {
                        ForEach(ObservationDatePolicy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(viewModel.comparisonPolicy == .exactDay ? "Only observations on the selected days are compared." : "Uses the most recent observation on or before each selected day. The actual record dates are shown below; prices between records are unknown.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !viewModel.comparisonDatesValid {
                        InfoCard(title: "Check the date order", message: "The From date must be on or before the To date.")
                    } else {
                        endpoint("From", requested: viewModel.comparisonStart, observation: viewModel.comparisonBefore)
                        endpoint("To", requested: viewModel.comparisonEnd, observation: viewModel.comparisonAfter)
                        if let change = viewModel.comparisonChange {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Price change").font(.title3.bold())
                                Text("\(change.before.money.formatted) → \(change.after.money.formatted)").font(.title2.bold())
                                PriceChangeBadge(change: change).accessibilityIdentifier("comparisonChange")
                                if change.before.id == change.after.id {
                                    Text("Both dates resolve to the same record. This does not establish that the price stayed unchanged between those dates.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        } else {
                            Text("A price difference needs a matching record at both ends.").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }.padding(24)
            }.background(AppTheme.background)
                .navigationTitle("Compare dates").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func endpoint(_ label: String, requested: Date, observation: PriceObservation?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(label) · \(requested.formatted(date: .abbreviated, time: .omitted))").font(.subheadline.weight(.semibold))
            if let observation {
                Text(observation.money.formatted).font(.system(size: 36, weight: .semibold, design: .rounded))
                Text("Recorded \(observation.observedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                Text(observation.source.label).font(.caption).foregroundStyle(.secondary)
                if observation.isDiscounted {
                    Text("Discounted record\(observation.priceBasis.map { " · " + $0.replacingOccurrences(of: "_", with: " ").lowercased() } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("No matching observation").foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 20))
    }
}
