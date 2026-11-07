import SwiftUI
import MealCore

/// Горизонтальный перенос элементов (чипы).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

/// Редактор списка слов (нежелательные/любимые продукты) с подсказками из справочника и свободным вводом.
struct TagEditor: View {
    let title: String
    let placeholder: String
    @Binding var tags: [String]
    @EnvironmentObject var store: AppStore
    @State private var text = ""

    private var suggestions: [String] {
        let t = TextNorm.normalize(text)
        guard t.count >= 2 else { return [] }
        return store.library.ingredientList.map { $0.name }.filter { TextNorm.normalize($0).contains(t) && !tags.contains($0) }.prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(Theme.ink)
            FlowLayout {
                ForEach(tags, id: \.self) { t in
                    Button { tags.removeAll { $0 == t } } label: { Chip(text: t + "  ✕", selected: true) }.buttonStyle(.plain)
                }
            }
            HStack {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { add(text) }
                Button("Добавить") { add(text) }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !suggestions.isEmpty {
                FlowLayout { ForEach(suggestions, id: \.self) { s in Button { add(s) } label: { Chip(text: s) }.buttonStyle(.plain) } }
            }
        }
    }

    private func add(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !tags.contains(t) else { text = ""; return }
        tags.append(t); text = ""
    }
}

struct AllergenPicker: View {
    @Binding var allergens: Set<Allergen>
    @State private var custom = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout {
                ForEach(Allergen.standard) { a in
                    Button {
                        if allergens.contains(a) { allergens.remove(a) } else { allergens.insert(a) }
                    } label: { Chip(text: shortTitle(a), selected: allergens.contains(a)) }.buttonStyle(.plain)
                }
                ForEach(allergens.filter { $0.isCustom }.sorted { $0.rawValue < $1.rawValue }) { a in
                    Button { allergens.remove(a) } label: { Chip(text: a.title + "  ✕", selected: true) }.buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Другой аллерген (например, кешью)", text: $custom).textFieldStyle(.roundedBorder).submitLabel(.done).onSubmit(addCustom)
                Button("Добавить", action: addCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
    private func addCustom() {
        let t = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        allergens.insert(.custom(t)); custom = ""
    }
    private func shortTitle(_ a: Allergen) -> String {
        switch a.rawValue {
        case "milk": return "Молоко"; case "eggs": return "Яйца"; case "peanuts": return "Арахис"; case "tree_nuts": return "Орехи"
        case "fish": return "Рыба"; case "shellfish": return "Морепродукты"; case "soy": return "Соя"; case "wheat": return "Пшеница"
        case "gluten": return "Глютен"; case "sesame": return "Кунжут"; default: return a.title
        }
    }
}

/// Редактор техники и посуды (с объёмом кастрюль).
struct KitchenEditor: View {
    @Binding var kitchen: Kitchen
    @State private var customName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Техника").font(.system(.headline, design: .rounded))
            FlowLayout {
                ForEach(KitchenCatalog.equipment) { e in
                    Button {
                        if kitchen.equipment.contains(e.key) { kitchen.equipment.remove(e.key) } else { kitchen.equipment.insert(e.key) }
                    } label: { Chip(text: e.title, selected: kitchen.equipment.contains(e.key)) }.buttonStyle(.plain)
                }
                ForEach(kitchen.customEquipment, id: \.self) { c in
                    Button { kitchen.customEquipment.removeAll { $0 == c } } label: { Chip(text: c + "  ✕", selected: true) }.buttonStyle(.plain)
                }
            }
            HStack {
                TextField("Другая техника или посуда", text: $customName).textFieldStyle(.roundedBorder)
                Button("Добавить") {
                    let t = customName.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { kitchen.customEquipment.append(t); customName = "" }
                }.disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Посуда и инструменты").font(.system(.headline, design: .rounded))
            FlowLayout {
                ForEach(KitchenCatalog.cookware) { c in
                    let has = kitchen.cookware.contains { $0.kind == c.key }
                    Button {
                        if has { kitchen.cookware.removeAll { $0.kind == c.key } } else { kitchen.cookware.append(Cookware(kind: c.key)) }
                    } label: { Chip(text: c.title, selected: has) }.buttonStyle(.plain)
                }
            }
            ForEach(["pot", "saucepan", "frying_pan", "kazan", "wok"], id: \.self) { kind in
                if let idx = kitchen.cookware.firstIndex(where: { $0.kind == kind }) {
                    VolumeRow(kind: kind, volume: Binding(get: { kitchen.cookware[idx].volumeMl ?? KitchenCatalog.defaultVolumeMl(kind) },
                                                          set: { kitchen.cookware[idx].volumeMl = $0 }))
                }
            }
            Text("Рецепты, которые нельзя приготовить на вашей технике, в меню не попадут. Если блюдо не помещается в посуду за один раз, приложение предложит готовить в несколько подходов.")
                .font(Theme.caption).foregroundStyle(Theme.muted)
        }
    }
}

struct VolumeRow: View {
    let kind: String
    @Binding var volume: Int
    var title: String { KitchenCatalog.cookware.first { $0.key == kind }?.title ?? kind }
    var body: some View {
        HStack {
            Text("\(title): объём").font(Theme.body)
            Spacer()
            Stepper(value: $volume, in: 300...20_000, step: 250) { Text(String(format: "%.1f л", Double(volume) / 1000).replacingOccurrences(of: ".", with: ",")).font(Theme.number(15)) }
                .fixedSize()
        }
    }
}

struct ProfileEditor: View {
    @Binding var profile: PersonProfile
    var isShared = false
    @State private var showBody = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !isShared { TextField("Имя", text: $profile.name).textFieldStyle(.roundedBorder) }
            Text("Аллергены (строгое ограничение)").font(.system(.headline, design: .rounded))
            AllergenPicker(allergens: $profile.allergens)
            TagEditor(title: "Не люблю", placeholder: "Например: грибы, печень", tags: $profile.dislikes)
            Picker("Строгость", selection: $profile.dislikeStrictness) {
                Text("Исключить полностью").tag(Strictness.strict)
                Text("Лучше избегать").tag(Strictness.soft)
            }.pickerStyle(.segmented)
            TagEditor(title: "Люблю", placeholder: "Например: курица, рис", tags: $profile.favorites)
            Toggle("Вегетарианское питание", isOn: $profile.vegetarian)
            if !isShared {
                DisclosureGroup("Параметры тела (необязательно)", isExpanded: $showBody) {
                    BodyFields(profile: $profile).padding(.top, 8)
                }
            }
        }
    }
}

struct BodyFields: View {
    @Binding var profile: PersonProfile
    var body: some View {
        VStack(spacing: 10) {
            Picker("Пол", selection: Binding(get: { profile.sex }, set: { profile.sex = $0 })) {
                Text("—").tag(Sex?.none); Text("Мужской").tag(Sex?.some(.male)); Text("Женский").tag(Sex?.some(.female))
            }.pickerStyle(.segmented)
            numberRow("Возраст", Binding(get: { Double(profile.ageYears ?? 0) }, set: { profile.ageYears = $0 > 0 ? Int($0) : nil }))
            numberRow("Рост, см", Binding(get: { profile.heightCm ?? 0 }, set: { profile.heightCm = $0 > 0 ? $0 : nil }))
            numberRow("Вес, кг", Binding(get: { profile.weightKg ?? 0 }, set: { profile.weightKg = $0 > 0 ? $0 : nil }))
            Picker("Активность", selection: Binding(get: { profile.activity ?? .light }, set: { profile.activity = $0 })) {
                ForEach(ActivityLevel.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Данные используются только для расчёта размера порций. Это не медицинская рекомендация.").font(Theme.caption).foregroundStyle(Theme.muted)
        }
    }
    private func numberRow(_ title: String, _ value: Binding<Double>) -> some View {
        HStack { Text(title); Spacer(); TextField("0", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90).textFieldStyle(.roundedBorder) }
    }
}

extension Date {
    func dayString() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "d MMMM"
        return f.string(from: self)
    }
    func weekdayShort() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "EE"
        return f.string(from: self)
    }
}

extension MealPlan {
    func date(forDay d: Int) -> Date { Calendar.current.date(byAdding: .day, value: d, to: Calendar.current.startOfDay(for: settings.startDate)) ?? settings.startDate }
    var todayIndex: Int {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: settings.startDate), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return min(max(0, days), settings.days - 1)
    }
    func storeName(_ id: String) -> String {
        if id == ReferencePrices.storeID { return "Ориентировочные цены" }
        if id == "user" { return "Мои цены" }
        return stores.first { $0.id == id }?.name ?? "Магазин"
    }
}
