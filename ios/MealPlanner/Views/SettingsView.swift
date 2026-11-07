import SwiftUI
import MealCore
import UniformTypeIdentifiers

struct MoreView: View {
    @EnvironmentObject var store: AppStore
    @Binding var showWizard: Bool
    var body: some View {
        NavigationStack {
            List {
                Section("Кухня") {
                    NavigationLink { RecipesView() } label: { Label("Рецепты", systemImage: "book") }
                    NavigationLink { PantryView() } label: { Label("Мои продукты", systemImage: "shippingbox") }
                }
                Section("Магазины и цены") {
                    NavigationLink { ScrollView { StoresView().padding(20) }.screenBackground() } label: { Label("Карта магазинов", systemImage: "map") }
                    NavigationLink { ManualPricesView() } label: { Label("Мои цены", systemImage: "rublesign.circle") }
                }
                Section("Аналитика") {
                    NavigationLink { StatsView() } label: { Label("Статистика", systemImage: "chart.bar") }
                    NavigationLink { HistoryView() } label: { Label("История рационов", systemImage: "clock.arrow.circlepath") }
                }
                Section {
                    NavigationLink { SettingsView() } label: { Label("Настройки", systemImage: "gearshape") }
                    Button { showWizard = true } label: { Label("Создать новый рацион", systemImage: "wand.and.stars") }
                }
            }
            .navigationTitle("Ещё")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var token = ""
    @State private var confirmWipe = false

    var body: some View {
        Form {
            Section("Профили питания") {
                NavigationLink("Общие ограничения (для всех)") { ScrollView { ProfileEditor(profile: $store.state.shared, isShared: true).padding(20) }.screenBackground() }
                ForEach($store.state.people) { $p in NavigationLink(p.name) { ScrollView { ProfileEditor(profile: $p).padding(20) }.screenBackground() } }
                    .onDelete { store.state.people.remove(atOffsets: $0) }
                Button("Добавить человека") { store.state.people.append(PersonProfile(name: "Человек \(store.state.people.count + 1)")) }
            }
            Section("Техника и посуда") {
                NavigationLink("Кухня") { ScrollView { KitchenEditor(kitchen: $store.state.kitchen).padding(20) }.screenBackground() }
            }
            Section("Адреса") {
                ForEach(store.state.addresses) { a in
                    HStack { Text(a.title).lineLimit(2); Spacer(); if a.id == store.state.activeAddressID { Image(systemName: "checkmark").foregroundStyle(Theme.accent) } }
                        .contentShape(Rectangle()).onTapGesture { store.state.activeAddressID = a.id }
                }.onDelete { store.state.addresses.remove(atOffsets: $0) }
                Text("Адреса добавляются при поиске магазинов (раздел «Карта магазинов»). Сменить город — введите новый адрес.").font(.caption).foregroundStyle(Theme.muted)
            }
            Section("Напоминания") {
                Toggle("О приготовлении", isOn: $store.state.reminders.cookingEnabled)
                if store.state.reminders.cookingEnabled { Stepper("Время: \(store.state.reminders.cookingHour):00", value: $store.state.reminders.cookingHour, in: 6...22) }
                Toggle("О сроках годности запасов", isOn: $store.state.reminders.expiryEnabled)
                Toggle("Об изменении цен (если есть данные)", isOn: $store.state.reminders.priceChangeEnabled)
            }
            .onChange(of: store.state.reminders) { _, _ in Task { _ = await Notifications.requestAuthorization(); await Notifications.reschedule(state: store.state, library: store.library) } }
            Section("Сервер (необязательно)") {
                Text(store.backend == nil ? "Backend не подключён: каталоги — только из файлов и ручного ввода; поиск магазинов — Apple Карты; ассистент — локальные команды." : "Backend подключён: каталоги Open Prices, магазины из OpenStreetMap, AI-помощник.")
                    .font(.caption).foregroundStyle(Theme.muted)
                SecureField("Токен доступа к backend", text: $token)
                Button("Сохранить токен в Keychain") { if !token.isEmpty { Keychain.save("backend-token", token); token = "" } }
            }
            Section("Данные и приватность") {
                Text("Все данные хранятся только на устройстве (файл защищён шифрованием iOS). На сервер уходят только запросы цен для выбранных магазинов и (при включённом AI) текст вашей команды без имён.").font(.caption).foregroundStyle(Theme.muted)
                Button("Удалить все мои данные", role: .destructive) { confirmWipe = true }
            }
            Section("О приложении") {
                NavigationLink("Что работает и какие есть ограничения") { LimitationsView() }
            }
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Удалить все данные приложения безвозвратно?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) { store.wipeAllData() }
        }
    }
}

struct ManualPricesView: View {
    @EnvironmentObject var store: AppStore
    @State private var key = "rice"
    @State private var size = ""
    @State private var price = ""
    @State private var name = ""
    var body: some View {
        Form {
            Section(footer: Text("Введите реальный ценник из магазина — он будет использован в расчёте и помечен «Введено вручную».")) {
                Picker("Продукт", selection: $key) { ForEach(store.library.ingredientList) { Text($0.name).tag($0.key) } }
                TextField("Название товара (необязательно)", text: $name)
                HStack { TextField("Размер упаковки", text: $size).keyboardType(.decimalPad); Text(store.library.ingredients[key]?.unit.short ?? "г").foregroundStyle(Theme.muted) }
                TextField("Цена за упаковку, ₽", text: $price).keyboardType(.decimalPad)
                Button("Добавить цену") {
                    if let s = Double(size.replacingOccurrences(of: ",", with: ".")), let p = Double(price.replacingOccurrences(of: ",", with: ".")), s > 0, p > 0 {
                        store.state.userPrices.append(UserPrice(ingredientKey: key, productName: name.isEmpty ? (store.library.ingredients[key]?.name ?? key) : name, packSize: s, price: .rub(p)))
                        size = ""; price = ""; name = ""
                    }
                }
            }
            Section("Мои цены") {
                ForEach(store.state.userPrices) { u in
                    HStack { Text(u.productName); Spacer(); Text("\(Fmt.amount(u.packSize, unit: store.library.ingredients[u.ingredientKey]?.unit ?? .g)) — \(u.price.formatted())") }.font(.caption)
                }.onDelete { store.state.userPrices.remove(atOffsets: $0) }
            }
        }.navigationTitle("Мои цены")
    }
}

struct LimitationsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Честно о возможностях").font(Theme.display(26))
                Group {
                    Text("• Магазины ищутся автоматически (Apple Карты, при наличии backend — ещё и OpenStreetMap). Список сетей не ограничен.")
                    Text("• Наличие магазина на карте не означает, что есть каталог его товаров. Готовых интеграций с каталогами конкретных сетей (Пятёрочка, Магнит и т. д.) в приложении нет: у них нет открытых официальных API. Источники цен: реальные цены с чеков (Open Prices), ваши CSV/JSON-файлы и ручной ввод.")
                    Text("• Если реальных цен нет, расчёт возможен только по ориентирам — они всегда явно помечены и не являются ценами магазина.")
                    Text("• Пищевая ценность блюд рассчитана по справочным таблицам для сырых продуктов; реальные значения зависят от продуктов и способа готовки.")
                    Text("• Аллергены проверяются по справочнику и составу товара, если он известен. Это не гарантия безопасности — читайте упаковку. Приложение не заменяет врача.")
                    Text("• Меню общее для всех участников: ограничения каждого человека учитываются, но отдельные блюда для отдельных людей не составляются.")
                }.font(Theme.body).foregroundStyle(Theme.ink)
            }.padding(20)
        }.screenBackground()
    }
}
