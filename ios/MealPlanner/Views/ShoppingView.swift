import SwiftUI
import MealCore

struct ShoppingView: View {
    @EnvironmentObject var store: AppStore
    @State private var showReceipt = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = store.state.currentPlan { list(plan) }
                else { ScrollView { EmptyState(icon: "cart", title: "Список пуст", text: "После создания рациона здесь появится список покупок по магазинам.") } }
            }
            .screenBackground()
            .navigationTitle("Покупки")
            .toolbar {
                if let plan = store.state.currentPlan {
                    ToolbarItem(placement: .topBarTrailing) { ShareLink(item: ShoppingExport.text(plan)) { Image(systemName: "square.and.arrow.up") } }
                    ToolbarItem(placement: .topBarTrailing) { ShareLink(item: ShoppingExport.csv(plan)) { Image(systemName: "tablecells") } }
                }
            }
            .sheet(isPresented: $showReceipt) { ReceiptSheet() }
        }
    }

    private func list(_ plan: MealPlan) -> some View {
        let groups = ShoppingExport.groupedByStore(plan)
        return List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Корзина").font(Theme.display(22)); Spacer(); Text(plan.basketTotal.formatted()).font(Theme.number(24)) }
                    Text("Бюджет \(plan.budget.formatted()) · остаток \(plan.remaining.formatted())").font(Theme.caption).foregroundStyle(plan.status == .overBudget ? Theme.tomato : Theme.muted)
                    Text("Упаковки покупаются целиком; остатки на ≈ \(plan.leftoverValue.formatted()) пойдут в запас. " + (plan.visits.isEmpty ? "Магазин не определён (цены-ориентиры)." : "Магазинов: \(Set(plan.visits.map { $0.storeID }).count), заходов: \(plan.visits.count).")).font(Theme.caption).foregroundStyle(Theme.muted)
                    if plan.estimateShare > 0 { Label("Цены помечены «ориентир» — это не данные магазина.", systemImage: "exclamationmark.triangle.fill").font(Theme.caption).foregroundStyle(Theme.tomato) }
                    SecondaryButton(title: "Записать фактический чек", systemImage: "receipt") { showReceipt = true }
                }.listRowBackground(Color.clear)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                Section {
                    ForEach(g.lines) { l in LineRow(line: l) }
                } header: {
                    HStack { Text("\(g.store) · день \(g.day + 1)"); Spacer(); Text(Money.sum(g.lines.map { $0.total }).formatted()) }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

struct LineRow: View {
    @EnvironmentObject var store: AppStore
    let line: PurchaseLine
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { store.toggleLine(line) } label: {
                Image(systemName: store.isLineChecked(line) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(Theme.accent)
            }.buttonStyle(.plain)
            if let u = line.imageURL, let url = URL(string: u) {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Theme.sage }
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(line.ingredientName).font(.system(.body, design: .rounded).weight(.semibold)).foregroundStyle(Theme.ink)
                    .strikethrough(store.isLineChecked(line))
                Text("\(line.productName) — \(line.packs) × \(Fmt.amount(Double(line.packBase), unit: line.unit))").font(Theme.caption).foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    QualityBadge(quality: line.quality)
                    if let promo = line.promoText { Text(promo).font(.caption2.weight(.semibold)).foregroundStyle(Theme.saffron) }
                    if let d = line.priceDate { Text("цена от \(d.dayString())").font(.caption2).foregroundStyle(Theme.muted) }
                }
                if let w = line.warning { Text(w).font(.caption2).foregroundStyle(Theme.tomato) }
                if let a = line.storageAdvice, a.contains("заморозьте") { Text(a).font(.caption2).foregroundStyle(Theme.saffron) }
                if let u = line.url, let url = URL(string: u) { Link("Открыть товар", destination: url).font(.caption2) }
            }
            Spacer()
            Text(line.total.formatted()).font(Theme.number(15)).foregroundStyle(Theme.ink)
        }
    }
}

struct ReceiptSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var storeName = ""
    @State private var amount = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Фактическая покупка") {
                    TextField("Магазин", text: $storeName)
                    TextField("Сумма чека, ₽", text: $amount).keyboardType(.decimalPad)
                }
                if !store.state.purchaseRecords.isEmpty {
                    Section("История расходов") {
                        ForEach(store.state.purchaseRecords.sorted { $0.date > $1.date }) { r in
                            HStack { VStack(alignment: .leading) { Text(r.storeName); Text(r.date.dayString()).font(.caption).foregroundStyle(Theme.muted) }; Spacer(); Text(r.amount.formatted()) }
                        }.onDelete { idx in
                            let sorted = store.state.purchaseRecords.sorted { $0.date > $1.date }
                            let ids = idx.map { sorted[$0].id }
                            store.state.purchaseRecords.removeAll { ids.contains($0.id) }
                        }
                    }
                }
            }
            .navigationTitle("Чек").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Сохранить") {
                    if let v = Double(amount.replacingOccurrences(of: ",", with: ".")), v > 0 {
                        store.state.purchaseRecords.append(PurchaseRecord(storeName: storeName.isEmpty ? "Магазин" : storeName, amount: .rub(v), planID: store.state.currentPlan?.id))
                        amount = ""
                    }
                } }
            }
        }
    }
}

struct PantryView: View {
    @EnvironmentObject var store: AppStore
    @State private var adding = false
    var body: some View {
        List {
            if store.state.pantry.isEmpty { EmptyState(icon: "shippingbox", title: "Запасов нет", text: "Добавьте продукты, которые уже есть дома, — приложение не будет покупать их повторно.") }
            ForEach(store.state.pantry.sorted { ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture) }) { item in
                let info = store.library.ingredients[item.ingredientKey]
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info?.name ?? item.ingredientKey).font(.system(.body, design: .rounded).weight(.semibold))
                        Text((item.storage ?? info?.store)?.title ?? "").font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(Fmt.amount(item.amount, unit: info?.unit ?? .g)).font(Theme.number(16))
                        if let e = item.expiry { Text("до \(e.dayString())").font(.caption).foregroundStyle(e < Date().addingTimeInterval(2 * 86400) ? Theme.tomato : Theme.muted) }
                    }
                }
            }.onDelete { idx in
                let sorted = store.state.pantry.sorted { ($0.expiry ?? .distantFuture) < ($1.expiry ?? .distantFuture) }
                let ids = Set(idx.map { sorted[$0].id })
                store.state.pantry.removeAll { ids.contains($0.id) }
            }
        }
        .navigationTitle("Мои продукты")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $adding) { AddPantrySheet() }
    }
}

struct AddPantrySheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = "rice"
    @State private var amount = ""
    @State private var hasExpiry = false
    @State private var expiry = Date().addingTimeInterval(30 * 86400)
    var body: some View {
        NavigationStack {
            Form {
                Picker("Продукт", selection: $key) { ForEach(store.library.ingredientList) { Text($0.name).tag($0.key) } }
                HStack {
                    TextField("Количество", text: $amount).keyboardType(.decimalPad)
                    Text(store.library.ingredients[key]?.unit.short ?? "г").foregroundStyle(Theme.muted)
                }
                Toggle("Указать срок годности", isOn: $hasExpiry)
                if hasExpiry { DatePicker("Годен до", selection: $expiry, displayedComponents: .date) }
                if let i = store.library.ingredients[key] { Text("Хранение: \(i.store.title). Стандартный срок: \(i.shelf) сут.").font(.caption).foregroundStyle(Theme.muted) }
            }
            .navigationTitle("Добавить продукт").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Добавить") {
                    if let a = Double(amount.replacingOccurrences(of: ",", with: ".")), a > 0 {
                        store.state.pantry.append(PantryItem(ingredientKey: key, amount: a, expiry: hasExpiry ? expiry : nil, storage: store.library.ingredients[key]?.store)); dismiss()
                    }
                } }
            }
        }
    }
}
