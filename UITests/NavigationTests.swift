import XCTest

final class NavigationTests: XCTestCase {
    @MainActor
    func testBrowsingManualBarcodeValidationAndSearch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let skip = app.buttons["skipLocationButton"]
        if skip.waitForExistence(timeout: 2) { skip.tap() }
        XCTAssertTrue(app.buttons["scanBarcodeButton"].waitForExistence(timeout: 5))
        attach(app, name: "Home")
        app.buttons["scanBarcodeButton"].tap()
        let manual = app.textFields["manualBarcodeField"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap(); manual.typeText("123")
        app.buttons["findBarcodeButton"].tap()
        XCTAssertTrue(app.staticTexts["Enter a valid 8, 12, 13 or 14-digit product barcode."].waitForExistence(timeout: 2))
        attach(app, name: "Scanner validation")
        app.buttons["Close"].tap()
        app.buttons["searchProductsButton"].tap()
        let search = app.textFields["productSearchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["submitSearchButton"].isEnabled)
        search.tap(); search.typeText("123")
        app.buttons["submitSearchButton"].tap()
        XCTAssertTrue(app.staticTexts["Enter a valid 8, 12, 13 or 14-digit product barcode."].waitForExistence(timeout: 3))
        attach(app, name: "Search validation")
    }
    @MainActor private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
