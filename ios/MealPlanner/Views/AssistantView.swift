import SwiftUI
import MealCore

struct AssistantView: View {
    @EnvironmentObject var store: AppStore
    @State private var text = ""
    private let hints = ["Замени ужин в среду на что-нибудь с курицей", "Хочу питаться разнообразнее, но бюджет увеличивать нельзя", "Сделай подешевле", "Что приготовить из остатков?"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if store.state.chat.isEmpty {
                                Text("Я меняю меню и пересчитываю закупки. Цены, граммовки, аллергены, технику и бюджет всегда проверяет программа, а не нейросеть.").font(Theme.caption).foregroundStyle(Theme.muted)
                                ForEach(hints, id: \.self) { h in Button { text = h } label: { Chip(text: h) }.buttonStyle(.plain) }
                            }
                            ForEach(store.state.chat) { m in
                                HStack { if m.fromUser { Spacer() }
                                    Text(m.text).font(Theme.body).padding(12)
                                        .foregroundStyle(m.fromUser ? Color.white : Theme.ink)
                                        .background(m.fromUser ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 16))
                                    if !m.fromUser { Spacer() } }.id(m.id)
                            }
                            if store.assistantBusy { ProgressView().padding() }
                        }.padding(16)
                    }
                    .onChange(of: store.state.chat.count) { _, _ in if let last = store.state.chat.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                }
                HStack {
                    TextField("Напишите, что изменить…", text: $text, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3)
                    Button { let t = text; text = ""; Task { await store.sendToAssistant(t) } } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || store.assistantBusy)
                }.padding(12).background(Theme.paper)
            }
            .screenBackground().navigationTitle("Помощник")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { store.state.chat = [] } label: { Image(systemName: "trash") } } }
        }
    }
}
