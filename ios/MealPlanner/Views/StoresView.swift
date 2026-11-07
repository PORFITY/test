import SwiftUI
import MapKit
import MealCore
import CoreLocation
import UniformTypeIdentifiers

struct StoresView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var location = LocationService()
    var embedded = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var address = ""
    @State private var detail: StoreInfo?
    @State private var filter = StoreDirectory.Filter()
    @State private var onlyCatalog = false
    @State private var onlyFresh = false
    @State private var onlyDelivery = false
    @State private var customRadius = ""
    @State private var addName = ""

    private var center: CLLocationCoordinate2D? {
        if let l = location.location { return l.coordinate }
        if let a = store.state.activeAddress { return CLLocationCoordinate2D(latitude: a.lat, longitude: a.lon) }
        return nil
    }

    private var visibleStores: [StoreInfo] {
        var f = filter; f.onlyWithCatalog = onlyCatalog; f.onlyWithFreshPrices = onlyFresh; f.onlyDelivery = onlyDelivery
        return StoreDirectory.apply(f, to: store.state.knownStores)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            locationCard
            radiusCard
            if let n = store.storeNote { Text(n).font(Theme.caption).foregroundStyle(Theme.muted) }
            if store.searchingStores { HStack { ProgressView(); Text("Ищем магазины…").font(Theme.caption) } }
            if !store.state.knownStores.isEmpty {
                mapView.frame(height: 280).clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                filterBar
                selectionBar
                ForEach(visibleStores) { s in storeRow(s) }
            }
            manualAdd
        }
        .navigationTitle("Магазины")
        .sheet(item: $detail) { s in StoreDetailSheet(storeID: s.id) }
        .onChange(of: location.location) { _, new in if let c = new?.coordinate { Task { await run(c) } } }
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Где вы?").font(.system(.headline, design: .rounded))
            Text("Геопозиция запрашивается один раз для поиска магазинов — постоянный доступ не нужен.").font(Theme.caption).foregroundStyle(Theme.muted)
            PrimaryButton(title: location.isLocating ? "Определяем…" : "Найти магазины рядом", systemImage: "location.fill", isLoading: location.isLocating) { location.request() }
            if let m = location.message { Text(m).font(Theme.caption).foregroundStyle(Theme.tomato) }
            HStack {
                TextField("Или введите адрес / город", text: $address).textFieldStyle(.roundedBorder).submitLabel(.search).onSubmit { Task { await geocode() } }
                Button("Найти") { Task { await geocode() } }.disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !store.state.addresses.isEmpty {
                FlowLayout { ForEach(store.state.addresses) { a in
                    Button { store.state.activeAddressID = a.id; Task { await run(CLLocationCoordinate2D(latitude: a.lat, longitude: a.lon)) } } label: { Chip(text: a.title, selected: store.state.activeAddressID == a.id, systemImage: "mappin") }.buttonStyle(.plain)
                } }
            }
        }.card()
    }

    private var radiusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Радиус поиска: \(SearchRadius.title(store.state.searchRadiusM))").font(.system(.headline, design: .rounded))
            FlowLayout { ForEach(SearchRadius.presets, id: \.self) { r in
                Button { store.state.searchRadiusM = r; if let c = center { Task { await run(c) } } } label: { Chip(text: SearchRadius.title(r), selected: store.state.searchRadiusM == r) }.buttonStyle(.plain) } }
            HStack {
                TextField("Свой радиус, м", text: $customRadius).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                Button("Применить") {
                    if let v = Double(customRadius), v >= 100, v <= 200_000 { store.state.searchRadiusM = v; if let c = center { Task { await run(c) } } }
                }
            }
            Text("Если рядом мало магазинов, радиус расширяется автоматически.").font(Theme.caption).foregroundStyle(Theme.muted)
        }.card()
    }

    private var mapView: some View {
        Map(position: $camera) {
            UserAnnotation()
            if let c = center { MapCircle(center: c, radius: store.state.searchRadiusM).foregroundStyle(Theme.accent.opacity(0.08)).stroke(Theme.accent.opacity(0.4), lineWidth: 1) }
            ForEach(visibleStores) { s in
                Annotation(s.name, coordinate: CLLocationCoordinate2D(latitude: s.lat, longitude: s.lon)) {
                    Button { detail = s } label: {
                        Image(systemName: store.state.selectedStoreIDs.contains(s.id) ? "cart.circle.fill" : "cart.circle")
                            .font(.title2).foregroundStyle(store.state.selectedStoreIDs.contains(s.id) ? Theme.accent : Theme.muted)
                            .background(Circle().fill(Theme.card))
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Фильтры").font(.system(.headline, design: .rounded))
            FlowLayout {
                Button { onlyCatalog.toggle() } label: { Chip(text: "Только с каталогом", selected: onlyCatalog) }.buttonStyle(.plain)
                Button { onlyFresh.toggle() } label: { Chip(text: "Свежие цены", selected: onlyFresh) }.buttonStyle(.plain)
                Button { onlyDelivery.toggle() } label: { Chip(text: "С доставкой", selected: onlyDelivery) }.buttonStyle(.plain)
                ForEach(chainsAvailable, id: \.self) { c in
                    Button { if filter.chains.contains(c) { filter.chains.remove(c) } else { filter.chains.insert(c) } } label: { Chip(text: c, selected: filter.chains.contains(c)) }.buttonStyle(.plain)
                }
                ForEach(typesAvailable, id: \.self) { t in
                    Button { if filter.types.contains(t) { filter.types.remove(t) } else { filter.types.insert(t) } } label: { Chip(text: typeTitle(t), selected: filter.types.contains(t)) }.buttonStyle(.plain)
                }
            }
        }
    }

    private var chainsAvailable: [String] { Array(Set(store.state.knownStores.compactMap { $0.chain })).sorted().prefix(12).map { $0 } }
    private var typesAvailable: [String] { Array(Set(store.state.knownStores.map { $0.shopType })).sorted() }
    private func typeTitle(_ t: String) -> String {
        ["supermarket": "Супермаркет", "convenience": "Магазин у дома", "greengrocer": "Овощи/фрукты", "butcher": "Мясной", "bakery": "Пекарня", "marketplace": "Рынок"][t] ?? "Другое"
    }

    private var selectionBar: some View {
        HStack {
            Text("Выбрано: \(store.state.selectedStoreIDs.count) из \(store.state.knownStores.count)").font(Theme.caption).foregroundStyle(Theme.muted)
            Spacer()
            Button("Все") { store.state.selectedStoreIDs.formUnion(visibleStores.map { $0.id }) }.font(Theme.caption)
            Button("Снять") { store.state.selectedStoreIDs.subtract(visibleStores.map { $0.id }) }.font(Theme.caption)
        }
    }

    private func storeRow(_ s: StoreInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { store.toggleStore(s.id) } label: {
                Image(systemName: store.state.selectedStoreIDs.contains(s.id) ? "checkmark.square.fill" : "square").font(.title3).foregroundStyle(Theme.accent)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(Theme.ink)
                Text([s.address, s.distanceText].compactMap { $0 }.joined(separator: " · ")).font(Theme.caption).foregroundStyle(Theme.muted)
                Text(s.catalog.title).font(.caption2.weight(.semibold)).foregroundStyle(s.catalog == .unknown || s.catalog == .unavailable ? Theme.muted : Theme.accent)
            }
            Spacer()
            Button { detail = s } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).foregroundStyle(Theme.muted)
        }.card(padding: 12)
    }

    private var manualAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Нет вашего магазина в списке?").font(.system(.headline, design: .rounded))
            HStack {
                TextField("Название магазина", text: $addName).textFieldStyle(.roundedBorder)
                Button("Добавить") {
                    if let c = center, !addName.isEmpty { store.addManualStore(name: addName, near: c); addName = "" }
                }.disabled(center == nil || addName.isEmpty)
            }
            Text("Наличие магазина на карте не означает, что у него есть доступный каталог цен: цены можно загрузить из файла или ввести вручную в Настройках.").font(Theme.caption).foregroundStyle(Theme.muted)
        }.card()
    }

    private func run(_ c: CLLocationCoordinate2D) async {
        camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: store.state.searchRadiusM * 2.4, longitudinalMeters: store.state.searchRadiusM * 2.4))
        await store.discoverStores(center: c, radiusM: store.state.searchRadiusM)
    }

    private func geocode() async {
        guard let (c, title) = await StoreSearchService.geocode(address) else { store.storeNote = "Адрес не найден."; return }
        let a = SavedAddress(title: title, lat: c.latitude, lon: c.longitude)
        store.state.addresses.append(a); store.state.activeAddressID = a.id
        await run(c)
    }
}

struct StoreDetailSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let storeID: String
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            if let s = store.state.knownStores.first(where: { $0.id == storeID }) {
                List {
                    Section {
                        row("Название", s.name); if let c = s.chain { row("Сеть", c) }
                        row("Адрес", s.address ?? "не указан"); row("Расстояние", s.distanceText)
                        row("Часы работы", s.openingHours ?? "нет данных"); row("Тип", s.shopType)
                        row("Доставка", s.delivery.map { $0 ? "есть" : "нет" } ?? "нет данных")
                        row("Каталог", s.catalog.title)
                        row("Цены обновлены", s.priceUpdatedAt.map { $0.dayString() } ?? "нет данных")
                        row("Источник данных", s.source)
                    }
                    Section {
                        Button(store.state.selectedStoreIDs.contains(s.id) ? "Убрать из выбранных" : "Выбрать для закупок") { store.toggleStore(s.id) }
                        Button("Загрузить каталог/прайс (CSV, JSON)") { importing = true }
                    } footer: { Text("Приложение не выдумывает цены: если у магазина нет доступного каталога, цены берутся из файла, ручного ввода или (по вашему разрешению) помечаются как ориентир.") }
                    if let m = message { Text(m).font(Theme.caption) }
                }
                .navigationTitle(s.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .json, .plainText]) { res in
                    if case .success(let url) = res {
                        let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                        if let data = try? Data(contentsOf: url) { message = store.importCatalog(data: data, fileName: url.lastPathComponent, storeID: s.id) } else { message = "Не удалось прочитать файл." }
                    }
                }
            }
        }
    }
    private func row(_ t: String, _ v: String) -> some View { HStack { Text(t).foregroundStyle(Theme.muted); Spacer(); Text(v).multilineTextAlignment(.trailing) } }
}
