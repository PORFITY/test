import XCTest

/// Сквозной сценарий в симуляторе: мастер → расчёт по ориентирам → календарь → рецепт → покупки → помощник.
final class WizardFlowUITests: XCTestCase {
    let shots = "/tmp/ui-shots"

    func shot(_ name: String) {
        try? FileManager.default.createDirectory(atPath: shots, withIntermediateDirectories: true)
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shots)/\(name).png"))
    }

    func tap(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 10) {
        let b = app.buttons[label].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "нет кнопки «\(label)»")
        b.tap()
    }

    func testFullFlow() {
        let app = XCUIApplication()
        app.launch()
        shot("01-stores")
        tap(app, "Продолжить без магазинов (ориентиры)")
        shot("02-budget")
        tap(app, "Далее")                       // бюджет → аллергены
        XCTAssertTrue(app.staticTexts["Аллергены"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Далее"].isEnabled, "без ответа об аллергенах продолжить нельзя")
        tap(app, "У нас нет аллергий — продолжить")
        shot("03-allergens")
        tap(app, "Далее")                       // вкусы
        tap(app, "Далее")                       // цель
        tap(app, "Далее")                       // кухня
        tap(app, "Это моя кухня — всё верно")
        shot("04-kitchen")
        tap(app, "Далее")                       // итог
        shot("05-summary")
        tap(app, "Создать рацион")
        XCTAssertTrue(app.staticTexts["Сегодня в меню"].waitForExistence(timeout: 90), "рацион не создан")
        shot("06-home")
        app.tabBars.buttons["Рацион"].tap()
        shot("07-plan")
        app.tabBars.buttons["Покупки"].tap()
        XCTAssertTrue(app.staticTexts["Корзина"].waitForExistence(timeout: 10))
        shot("08-shopping")
        app.tabBars.buttons["Помощник"].tap()
        shot("09-assistant")
        app.tabBars.buttons["Ещё"].tap()
        shot("10-more")
    }
}
