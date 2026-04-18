import SwiftUI

/// User preferences screen. Currently houses the display-currency picker
/// and a "refresh exchange rates" action; will grow as we add more
/// settings (theme, notifications, etc.).
struct SettingsScreen: View {

    @State private var currency: String = LocalCurrency.current
    @State private var ratesUpdated: String = "Never"
    @State private var refreshing: Bool = false
    @State private var pricesUpdated: String = "Never"
    @State private var geminiAPIKey: String = GeminiVisionService.apiKey ?? ""
    @State private var geminiEnabled: Bool = GeminiVisionService.isEnabled || (GeminiVisionService.isConfigured && UserDefaults.standard.object(forKey: "geminiEnabled") == nil)
    @State private var geminiTestResult: String?
    @State private var geminiTesting: Bool = false
    @State private var showUsageEditor: Bool = false
    @State private var manualUsageText: String = ""
    @State private var showGeminiHelp: Bool = false
    @State private var geminiToast: String?
    @FocusState private var geminiKeyFocused: Bool
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
                SecureField("Gemini API Key", text: $geminiAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($geminiKeyFocused)
                    .submitLabel(.done)
                    .onSubmit { geminiKeyFocused = false }
                    .onChange(of: geminiAPIKey) { _, newValue in
                        let wasConfigured = GeminiVisionService.isConfigured
                        GeminiVisionService.apiKey = newValue.isEmpty ? nil : newValue
                        geminiTestResult = nil
                        // Auto-enable and show toast when key first entered
                        if !wasConfigured && GeminiVisionService.isConfigured {
                            geminiEnabled = true
                            GeminiVisionService.isEnabled = true
                            showGeminiToast("Gemini Vision auto-enabled")
                        } else if wasConfigured && !GeminiVisionService.isConfigured {
                            geminiEnabled = false
                            showGeminiToast("Gemini Vision disabled (key removed)")
                        }
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { geminiKeyFocused = false }
                        }
                    }
                if !geminiAPIKey.isEmpty {
                    Toggle("Enable Gemini Vision", isOn: $geminiEnabled)
                        .onChange(of: geminiEnabled) { _, newValue in
                            GeminiVisionService.isEnabled = newValue
                            showGeminiToast(newValue ? "Gemini Vision enabled" : "Gemini Vision disabled")
                        }
                }
                HStack {
                    Text("Status")
                    Spacer()
                    let hasKey = !geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if !hasKey {
                        Text("No API key")
                            .foregroundStyle(.secondary)
                    } else if !geminiEnabled {
                        Text("Disabled")
                            .foregroundStyle(.orange)
                    } else if GeminiVisionService.isDailyLimitReached {
                        Text("Daily limit reached")
                            .foregroundStyle(.red)
                    } else {
                        Text("Active")
                            .foregroundStyle(.green)
                    }
                }
                if !geminiAPIKey.isEmpty {
                    Button {
                        manualUsageText = "\(GeminiVisionService.dailyUsage)"
                        showUsageEditor = true
                    } label: {
                        HStack {
                            Text("Today's usage")
                                .foregroundStyle(MD3Theme.onSurface)
                            Spacer()
                            Text("\(GeminiVisionService.dailyUsage) / 1,000")
                                .foregroundStyle(GeminiVisionService.isDailyLimitReached ? .red : .secondary)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error = GeminiVisionService.lastError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if !geminiAPIKey.isEmpty {
                    Button {
                        Task { await testGeminiConnection() }
                    } label: {
                        HStack {
                            if geminiTesting {
                                ProgressView().scaleEffect(0.7)
                                Text("Testing...")
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Test Connection")
                            }
                            Spacer()
                            if let result = geminiTestResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(result.contains("OK") ? .green : .red)
                            }
                        }
                    }
                    .disabled(geminiTesting)
                }
            } header: {
                HStack {
                    Text("Gemini Vision (Card Scanner)")
                    Spacer()
                    Button {
                        showGeminiHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 14))
                    }
                }
            } footer: {
                Text("Free API key from aistudio.google.com. Used as a fallback when the local scanner can't identify a card.\n\nFree tier: 15 requests/min, 1,000 requests/day. Exceeding these limits may result in charges on your Google Cloud account. Monitor usage at aistudio.google.com.")
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
        .sheet(isPresented: $showGeminiHelp) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Group {
                            Text("Getting a Free API Key")
                                .font(.headline)
                            copyableURL("aistudio.google.com/apikey")
                            Text("2. Sign in with your Google account")
                            Text("3. Click \"Create API Key\"")
                            Text("4. Copy the key and paste it in the field above")
                        }

                        Divider()

                        Group {
                            Text("Checking Your Usage")
                                .font(.headline)
                            copyableURL("aistudio.google.com")
                            Text("2. Click on your profile icon (top right)")
                            Text("3. Select \"API Keys\" or \"Settings\"")
                            Text("4. Look for \"Usage\" or \"Activity\" section")
                            Text("5. The dashboard shows total API requests")
                            Text("6. Tap the usage counter in the app to sync the count manually")
                        }

                        Divider()

                        Group {
                            Text("Free Tier Limits")
                                .font(.headline)
                            HStack {
                                Text("Requests per minute:")
                                Spacer()
                                Text("15").bold()
                            }
                            HStack {
                                Text("Requests per day:")
                                Spacer()
                                Text("20").bold()
                            }
                            Text("The app automatically stops using Gemini when the daily limit is reached and falls back to local scanning. Rate limit errors (429) pause Gemini for 60 seconds.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        Group {
                            Text("How It Works")
                                .font(.headline)
                            Text("When enabled, the app sends your card photo to Google's Gemini AI which identifies all visible cards in one shot. This is much more accurate than local scanning for binder pages, sleeved cards, and angled photos.")
                            Text("The local scanner is used as a fallback when Gemini is disabled, offline, or has reached its daily limit.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .navigationTitle("Gemini Vision Help")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showGeminiHelp = false }
                    }
                }
            }
        }
        .alert("Set API Usage", isPresented: $showUsageEditor) {
            TextField("Usage count", text: $manualUsageText)
                .keyboardType(.numberPad)
            Button("Save") {
                if let count = Int(manualUsageText) {
                    GeminiVisionService.setDailyUsage(count)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the actual request count from aistudio.google.com to sync with Google's dashboard.")
        }
        .task {
            await currencyService.refreshIfStale()
            updateTimestamp()
            updatePricesTimestamp()
        }
        .onChange(of: currencyService.lastUpdated) { _, _ in
            updateTimestamp()
        }
        .overlay(alignment: .top) {
            if let toast = geminiToast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(MD3Theme.primary)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: geminiToast)
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

    private func testGeminiConnection() async {
        geminiTesting = true
        defer { geminiTesting = false }

        guard let apiKey = GeminiVisionService.apiKey, !apiKey.isEmpty else {
            geminiTestResult = "No key"
            return
        }

        let url = URL(string: "\(GeminiVisionService.endpointURL)?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "contents": [["parts": [["text": "Reply with exactly: OK"]]]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = json["candidates"] as? [[String: Any]],
                   !candidates.isEmpty {
                    geminiTestResult = "OK"
                    GeminiVisionService.lastError = nil
                } else {
                    geminiTestResult = "Unexpected response"
                }
            } else if statusCode == 400 {
                geminiTestResult = "Invalid key"
            } else if statusCode == 403 {
                geminiTestResult = "Key not authorized"
            } else if statusCode == 429 {
                geminiTestResult = "Rate limited"
            } else {
                geminiTestResult = "HTTP \(statusCode)"
            }
        } catch {
            geminiTestResult = "Network error"
        }
    }

    private func showGeminiToast(_ message: String) {
        geminiToast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            geminiToast = nil
        }
    }

    private func copyableURL(_ urlString: String) -> some View {
        Button {
            UIPasteboard.general.string = "https://\(urlString)"
        } label: {
            HStack(spacing: 4) {
                Text("1. Go to ")
                Text(urlString)
                    .foregroundStyle(MD3Theme.primary)
                    .underline()
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(MD3Theme.primary)
            }
        }
        .buttonStyle(.plain)
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
