import SwiftUI

/// User preferences screen. Currently houses the display-currency picker
/// and a "refresh exchange rates" action; will grow as we add more
/// settings (theme, notifications, etc.).
struct SettingsScreen: View {

    @State private var currency: String = LocalCurrency.current
    @State private var ratesUpdated: String = "Never"
    @State private var refreshing: Bool = false
    @State private var pricesUpdated: String = "Never"
    @Bindable private var currencyService = CurrencyService.shared
    @Bindable private var iconManager = AppIconManager.shared
    @Bindable private var printingPreference = PrintingStrategyPreference.shared

    var body: some View {
        List {
            Section {
                Picker("Display currency", selection: $currency) {
                    ForEach(LocalCurrency.supported, id: \.code) { entry in
                        HStack {
                            Text(entry.symbol)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(MD3Theme.primary)
                            Text(entry.name)
                            Text(entry.code)
                                .foregroundStyle(.secondary)
                        }
                        .tag(entry.code)
                    }
                }
                .pickerStyle(.navigationLink)
                .onChange(of: currency) { _, newValue in
                    LocalCurrency.current = newValue
                }
            } header: {
                Text("Currency")
            } footer: {
                Text("Card prices and collection value are converted from Scryfall's USD prices into your chosen currency for display. Real billing currencies on orders are unaffected.")
                    .font(.caption2)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exchange rates")
                            .foregroundStyle(MD3Theme.onSurface)
                        Text("Last updated: \(ratesUpdated)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await refresh() }
                    } label: {
                        if refreshing {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(MD3Theme.primary)
                        }
                    }
                    .disabled(refreshing)
                }
            } footer: {
                Text("Rates are fetched from frankfurter.app (free, ECB-backed) and cached locally for 24 hours. Tap refresh to fetch new rates immediately.")
                    .font(.caption2)
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Card prices")
                            .foregroundStyle(MD3Theme.onSurface)
                        Text("Last updated: \(pricesUpdated)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let service = PriceRefreshService.shared {
                        if service.isRefreshing {
                            VStack(spacing: 2) {
                                ProgressView().scaleEffect(0.7)
                                Text("\(Int(service.progress * 100))%")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button {
                                Task { await service.refresh(); updatePricesTimestamp() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(MD3Theme.primary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Prices from Scryfall (TCGPlayer market data). Auto-refreshes daily on launch. ~100MB download over WiFi recommended.")
                    .font(.caption2)
            }

            if let symbol = LocalCurrency.supported.first(where: { $0.code == currency })?.symbol,
               let usdPreview = currencyService.convert(1.0, to: currency) {
                Section("Preview") {
                    HStack {
                        Text("$1.00 USD")
                        Spacer()
                        Text("≈ \(symbol)\(LocalCurrency.format(usdPreview, currency: currency).dropFirst(symbol.count))")
                            .foregroundStyle(MD3Theme.primary)
                            .font(.body.weight(.semibold))
                    }
                }
            }

            Section {
                Picker("Default printing", selection: $printingPreference.strategy) {
                    ForEach(PrintingStrategy.allCases) { option in
                        HStack {
                            Image(systemName: option.iconName)
                                .foregroundStyle(MD3Theme.primary)
                            Text(option.displayName)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Deck Display")
            } footer: {
                Text("Decks browsed from MTGTop8 (and other deck lists outside My Decks) only carry card names — we resolve each name to a concrete printing using this strategy. Your saved decks in My Decks aren't affected; they keep whichever printings you picked.")
                    .font(.caption2)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { iconManager.rotationEnabled },
                    set: { newValue in
                        if newValue {
                            iconManager.enableRotation()
                        } else {
                            iconManager.rotationEnabled = false
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily color rotation")
                        Text("Cycles W → U → B → R → G each day")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(AppIconManager.ManaColor.allCases) { color in
                    Button {
                        iconManager.setManual(color)
                    } label: {
                        HStack {
                            Image(systemName: color.symbolName)
                                .frame(width: 28)
                                .foregroundStyle(MD3Theme.primary)
                            Text(color.displayName)
                                .foregroundStyle(MD3Theme.onSurface)
                            Spacer()
                            if iconManager.currentColor == color {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(MD3Theme.primary)
                            }
                        }
                    }
                }
            } header: {
                Text("App Icon")
            } footer: {
                Text("Picking a color manually disables rotation. iOS will show a system confirmation alert each time the icon actually changes — that's an Apple-imposed limitation.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await currencyService.refreshIfStale()
            updateTimestamp()
            updatePricesTimestamp()
        }
        .onChange(of: currencyService.lastUpdated) { _, _ in
            updateTimestamp()
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        await currencyService.refresh()
        updateTimestamp()
    }

    private func updateTimestamp() {
        if let date = currencyService.lastUpdated {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            ratesUpdated = formatter.string(from: date)
        } else {
            ratesUpdated = "Never"
        }
    }

    private func updatePricesTimestamp() {
        if let date = PriceRefreshService.shared?.lastUpdated {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            pricesUpdated = formatter.string(from: date)
        } else {
            pricesUpdated = "Never"
        }
    }

}
