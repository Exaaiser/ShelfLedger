import SwiftUI
import Charts

struct PriceTimelineView: View {
    @StateObject var viewModel: PriceTimelineViewModel
    var onChangeArea: (() -> Void)? = nil
    @State private var selectedDate: Date?
    @State private var specificDate = Date()
    @State private var showRecordPrice = false
    @State private var showImage = false
    @State private var showComparison = false
    @State private var showAllMonths = false
    @State private var onlineHistoryListing: OnlineOffer?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.isLoading && viewModel.snapshot == nil {
                    ProgressView("Finding this product…").frame(maxWidth: .infinity).padding(.vertical, 80)
                }
                if let error = viewModel.error {
                    InfoCard(title: "Couldn't load this product", message: error)
                    Button("Try again") { Task { await viewModel.load(refresh: true) } }.buttonStyle(PrimaryButtonStyle())
                }
                if let snapshot = viewModel.snapshot {
                    productHeader(snapshot.product)
                    if snapshot.isCached {
                        Label("Saved results · refreshed \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.notices, id: \.self) { notice in
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                    }
                    if viewModel.analysisObservations.isEmpty { onlineSection }
                    priceHighlight
                    HStack {
                        Label(viewModel.location?.label ?? "No area selected", systemImage: "location")
                        Spacer()
                        if let onChangeArea { Button("Change area", action: onChangeArea) }
                    }.font(.caption)
                    if viewModel.isWiderArea && !viewModel.analysisObservations.isEmpty {
                        InfoCard(title: viewModel.coverageLabel, message: "No nearby history was found. These are actual records from stores in the wider area, not a local price or a country average.")
                    }
                    chartSection
                    monthlySection
                    dateSection
                    if !viewModel.markets.isEmpty { marketSection }
                    if !viewModel.analysisObservations.isEmpty { onlineSection }
                    Button { showRecordPrice = true } label: { Label("Record a price", systemImage: "plus") }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("recordPriceButton")
                    Text("Price history · build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("A price observation records a place and date. It doesn't confirm current stock or today's price.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
        .background(AppTheme.background)
        .navigationTitle("Product").navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.location) { await viewModel.load() }
        .refreshable { await viewModel.load(refresh: true) }
        .sheet(item: $onlineHistoryListing) { listing in
            OnlinePriceHistoryView(records: viewModel.snapshot?.onlineHistory ?? [], listing: listing)
        }
        .sheet(isPresented: $showComparison) { PriceComparisonView(viewModel: viewModel) }
        .sheet(isPresented: $showRecordPrice) { RecordPriceView(viewModel: viewModel) }
        .fullScreenCover(isPresented: $showImage) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                AsyncImage(url: viewModel.snapshot?.product.imageURL) { image in image.resizable().scaledToFit() }
                    placeholder: { ProgressView().tint(.white) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Button { showImage = false } label: { Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white).padding() }
                    .accessibilityLabel("Close product image")
            }
        }
    }
    private func productHeader(_ product: Product) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Button { showImage = true } label: { ProductImage(url: product.imageURL, size: 96) }
                .disabled(product.imageURL == nil).accessibilityLabel("Enlarge product image")
            VStack(alignment: .leading, spacing: 8) {
                if let brand = product.brand { Text(brand.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(AppTheme.accent) }
                Text(product.name).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let quantity = product.quantity { Text(quantity).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder private var priceHighlight: some View {
        if let latest = viewModel.latest {
            VStack(alignment: .leading, spacing: 10) {
                Text("LAST RECORDED PRICE").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                Text(latest.observedAt.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                Text(latest.money.formatted).font(.system(size: 56, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.55).lineLimit(1).foregroundStyle(changeColor)
                if let change = viewModel.latestChange {
                    Text("\(change.before.money.formatted) → \(change.after.money.formatted)")
                        .font(.title2.weight(.semibold)).accessibilityIdentifier("latestPriceTransition")
                    PriceChangeBadge(change: change)
                    Text("Previous different price recorded \(change.before.observedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text("No earlier different price recorded.").font(.subheadline).foregroundStyle(.secondary) }
                Button("Compare dates") { showComparison = true }.font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("compareDatesButton")
                Text(latest.store.displayName).font(.subheadline)
                Text(latest.source.label).font(.caption).foregroundStyle(.secondary)
                if latest.isDiscounted { Text("Discounted price\(latest.priceBasis.map { " · " + $0.replacingOccurrences(of: "_", with: " ").lowercased() } ?? "")").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        } else {
            VStack(alignment: .leading, spacing: 14) {
                InfoCard(title: viewModel.availabilityTitle, message: viewModel.availabilityMessage, icon: "chart.xyaxis.line")
                HStack {
                    Button("Compare dates") { showComparison = true }.accessibilityIdentifier("compareDatesButton")
                    Spacer()
                    Button("Check again") { Task { await viewModel.load(refresh: true) } }.disabled(viewModel.isLoading)
                }.font(.subheadline.weight(.semibold))
            }.accessibilityIdentifier("priceHistoryEmptyState")
        }
    }
    private var changeColor: Color {
        guard let difference = viewModel.priceDifference else { return .primary }
        return difference > 0 ? .red : (difference < 0 ? AppTheme.accent : .primary)
    }
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recorded price history").font(.title3.bold())
            Picker("Time range", selection: $viewModel.timeRange) {
                ForEach(TimeRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            if viewModel.timeRange == .custom {
                DatePicker("From", selection: $viewModel.customStart, in: ...viewModel.customEnd, displayedComponents: .date)
                DatePicker("To", selection: $viewModel.customEnd, in: viewModel.customStart...Date(), displayedComponents: .date)
            }
            Text("Browse the available records, or choose Custom for any past date range.").font(.caption).foregroundStyle(.secondary)
            if viewModel.filteredPoints.isEmpty {
                Text("No observations in this range for the selected stores.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart {
                    ForEach(viewModel.filteredPoints) { point in
                        LineMark(x: .value("Date", point.observedAt), y: .value("USD", point.money.chartValue), series: .value("Store", point.store.id))
                            .foregroundStyle(by: .value("Store", point.store.id)).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("Date", point.observedAt), y: .value("USD", point.money.chartValue))
                            .foregroundStyle(by: .value("Store", point.store.id)).symbolSize(25)
                    }
                    if let high = viewModel.filteredPoints.max(by: { $0.money.amount < $1.money.amount }) {
                        PointMark(x: .value("Date", high.observedAt), y: .value("USD", high.money.chartValue))
                            .symbol(.diamond).symbolSize(70).foregroundStyle(.red)
                            .annotation(position: .top) { Text("High").font(.caption2).foregroundStyle(.secondary) }
                    }
                    if let date = selectedDate {
                        RuleMark(x: .value("Selected day", date)).foregroundStyle(AppTheme.accent.opacity(0.2)).lineStyle(StrokeStyle(lineWidth: 10))
                        RuleMark(x: .value("Selected day", date)).foregroundStyle(AppTheme.accent).lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartXScale(domain: viewModel.rangeStart...viewModel.chartEnd, range: .plotDimension(padding: 24))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits), centered: false, anchor: .top)
                    }
                }
                .chartForegroundStyleScale(domain: viewModel.markets.map(\.id), range: [AppTheme.accent, Color.teal, Color.indigo])
                .chartLegend {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.markets.filter { viewModel.selectedStores.contains($0.id) }) { store in
                            HStack(spacing: 6) {
                                Circle().fill([AppTheme.accent, Color.teal, Color.indigo][viewModel.markets.firstIndex(of: store) ?? 0]).frame(width: 7, height: 7)
                                Text("\(store.displayName) · \(viewModel.distanceLabel(store) ?? "")")
                            }.font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel))
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 240)
                .accessibilityLabel("Recorded USD prices for selected stores. Use the date selector below for exact observations.")
                if let selectedDate {
                    dayReadout(selectedDate)
                    Button("Compare this date") { viewModel.comparisonEnd = selectedDate; showComparison = true }
                        .font(.subheadline.weight(.semibold))
                }
                if let low = viewModel.filteredPoints.min(by: { $0.money.amount < $1.money.amount }),
                   let high = viewModel.filteredPoints.max(by: { $0.money.amount < $1.money.amount }) {
                    HStack {
                        Text("Low \(low.money.formatted)\n\(low.observedAt.formatted(.dateTime.month(.abbreviated).day()))")
                        Spacer()
                        Text("High \(high.money.formatted)\n\(high.observedAt.formatted(.dateTime.month(.abbreviated).day()))").multilineTextAlignment(.trailing)
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Text("Dots are recorded observations. No prices are created between them.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check a date").font(.title3.bold())
            DatePicker("Observation date", selection: $specificDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
            dayReadout(specificDate)
            Button("Compare with another date") { viewModel.comparisonEnd = specificDate; showComparison = true }
                .font(.subheadline.weight(.semibold))
        }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private func dayReadout(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption.weight(.semibold))
            let points = viewModel.points(on: date)
            if points.isEmpty {
                Text("No observation on \(date.formatted(date: .abbreviated, time: .omitted)) for the selected stores.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(points) { point in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(point.store.displayName); Spacer(); Text(point.money.formatted).fontWeight(.semibold) }
                        Text(point.source.label).font(.caption).foregroundStyle(.secondary)
                    }.font(.callout)
                }
            }
        }
    }
    private var monthlySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Monthly price changes").font(.title3.bold())
                Spacer()
                Button("Compare dates") { showComparison = true }.font(.caption.weight(.semibold))
            }
            if let store = viewModel.referenceStore { Text("Reference · \(store.displayName)").font(.caption).foregroundStyle(.secondary) }
            Text("Last record in each month of the selected range, compared with the previous calendar month. Tap a row to inspect both dates.")
                .font(.caption).foregroundStyle(.secondary)
            let months = viewModel.monthly
            ForEach(showAllMonths ? months : Array(months.prefix(6))) { month in
                Button {
                    viewModel.compare(month); showComparison = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(month.month.formatted(.dateTime.month(.wide).year())).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(month.observation?.money.formatted ?? "No record").font(.headline)
                        }.foregroundStyle(.primary)
                        if let change = month.change {
                            Text("\(change.before.money.formatted) → \(change.after.money.formatted)").font(.caption).foregroundStyle(.secondary)
                            PriceChangeBadge(change: change)
                        } else if month.observation != nil {
                            Text("No record in the previous month to compare.").font(.caption).foregroundStyle(.secondary)
                        }
                        if let observation = month.observation {
                            Text("Recorded \(observation.observedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                }.buttonStyle(.plain)
                Divider()
            }
            if months.count > 6 {
                Button(showAllMonths ? "Show fewer months" : "Show all \(months.count) months") { showAllMonths.toggle() }
                    .font(.subheadline.weight(.semibold))
            }
        }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
    private var marketSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.isWiderArea ? "Reference stores in the wider area" : "Local stores with price records").font(.title3.bold())
            Text(viewModel.isWiderArea ? "Nearest available records · up to three stores" : "Nearest first · up to three stores").font(.caption).foregroundStyle(.secondary)
            ForEach(viewModel.markets) { store in
                Button { viewModel.toggle(store) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.selectedStores.contains(store.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.displayName).font(.headline).foregroundStyle(.primary)
                            if let address = store.address { Text(address).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(viewModel.distanceLabel(store) ?? "").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }.buttonStyle(.plain)
            }
        }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
    @ViewBuilder private var onlineSection: some View {
        if !viewModel.onlineOffers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Online price listings", systemImage: "globe").font(.title3.bold())
                ForEach(viewModel.onlineOffers) { offer in
                VStack(alignment: .leading, spacing: 10) {
                HStack { Text(offer.merchant).font(.headline); Spacer(); Text(offer.money.formatted).font(.title2.bold()) }
                Text(offer.title).font(.subheadline)
                Text(offer.sourceName).font(.caption).foregroundStyle(.secondary)
                if let qualifier = offer.priceQualifier { Text(qualifier).font(.caption).foregroundStyle(.secondary) }
                if let date = offer.updatedAt { Text("Source date \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                else { Text("Update date unavailable").font(.caption).foregroundStyle(.secondary) }
                Text(offer.isStale(at: Date()) ? "This is an older or undated listing. Confirm the price and pack size with the seller." : "Check the seller's pack size and shipping before comparing with store prices.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Price history") { onlineHistoryListing = offer }
                        .accessibilityIdentifier("onlinePriceHistoryButton")
                    Spacer()
                    Link(destination: offer.url) { Label("Visit source", systemImage: "arrow.up.right") }
                }.font(.subheadline.weight(.semibold))
                }
                if offer.id != viewModel.onlineOffers.last?.id { Divider() }
                }
            }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        } else {
            InfoCard(title: "No matching online listing", message: "An online USD offer isn't available from the connected sources for this barcode.", icon: "globe")
        }
        if !viewModel.savedOnlineListings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved online history").font(.headline)
                Text("Previously retrieved listings; current availability is unknown.").font(.caption).foregroundStyle(.secondary)
                ForEach(viewModel.savedOnlineListings) { listing in
                    Button { onlineHistoryListing = listing } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(listing.merchant) · \(listing.sourceName)")
                            Text(listing.title).font(.caption).lineLimit(2)
                        }
                    }
                }
            }.padding(20).background(AppTheme.card, in: RoundedRectangle(cornerRadius: 22))
        }
    }
}

struct RecordPriceView: View {
    @ObservedObject var viewModel: PriceTimelineViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var price = ""
    @State private var storeID = ""
    @State private var date = Date()
    @State private var submissionID = UUID()
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Price in USD", text: $price).keyboardType(.decimalPad).accessibilityIdentifier("recordPriceField")
                    Picker("Store", selection: $storeID) {
                        Text("Choose a store").tag("")
                        ForEach(viewModel.recordableStores) { store in
                            Text("\(store.displayName) · \(viewModel.distanceLabel(store) ?? "")").tag(store.id)
                        }
                    }
                    DatePicker("Date seen", selection: $date, in: ...Date(), displayedComponents: .date)
                } header: { Text("The price you saw") } footer: {
                    Text("Record the price of the exact package shown. Saved on this device only; not a verified community submission.")
                }
                if viewModel.recordableStores.isEmpty {
                    Section { Text(viewModel.storeNotice ?? "No stores are available yet. Set your area from the home screen, or try again once nearby stores load.") }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Button("Save price on this device") {
                    do { try viewModel.save(id: submissionID, price: price, storeID: storeID, date: date); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.disabled(storeID.isEmpty || price.isEmpty).accessibilityIdentifier("savePriceButton")
            }.navigationTitle("Record a price").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
