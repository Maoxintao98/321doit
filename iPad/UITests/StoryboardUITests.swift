import XCTest

final class StoryboardUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDrawingRemovesEmptyStateInCanvasAndShotList() throws {
        let app = XCUIApplication()
        app.launch()

        let storyboardTab = app.buttons["分镜"]
        XCTAssertTrue(storyboardTab.waitForExistence(timeout: 5))
        storyboardTab.tap()

        let canvasPlaceholder = app.images["Annotate"]
        let thumbnailPlaceholder = app.images["Autofill"]
        XCTAssertTrue(canvasPlaceholder.waitForExistence(timeout: 3))
        XCTAssertTrue(thumbnailPlaceholder.exists)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.61, dy: 0.34))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.77, dy: 0.40))
        start.press(forDuration: 0.1, thenDragTo: end)

        XCTAssertTrue(canvasPlaceholder.waitForNonExistence(timeout: 3))
        XCTAssertTrue(thumbnailPlaceholder.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
    }

    func testScheduleSectionsAreAllVisibleAndOpen() throws {
        let app = XCUIApplication()
        app.launch()

        let planTab = app.buttons["计划"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 5))
        planTab.tap()

        for title in ["概览", "时间表", "人员", "DIT"] {
            let button = app.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 2), "\(title) should be visible")
            XCTAssertTrue(button.isHittable, "\(title) should be tappable")
            button.tap()
            if title == "时间表" {
                let localizedCrewCall = app.textFields
                    .matching(NSPredicate(format: "value == %@", "全组通告"))
                    .firstMatch
                XCTAssertTrue(localizedCrewCall.waitForExistence(timeout: 2))
            }
        }

        XCTAssertTrue(app.staticTexts["DIT"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["生成校验报告"].exists)
        XCTAssertTrue(app.switches["生成后期交接包"].exists)
    }

    func testMediaSectionsAreVisibleAndOpen() throws {
        let app = XCUIApplication()
        app.launch()

        let mediaTab = app.buttons["媒体"]
        XCTAssertTrue(mediaTab.waitForExistence(timeout: 5))
        mediaTab.tap()

        for title in ["安全拷卡", "媒体转换", "后期交接"] {
            let button = app.buttons[title]
            XCTAssertTrue(button.waitForExistence(timeout: 2), "\(title) should be visible")
            XCTAssertTrue(button.isHittable, "\(title) should be tappable")
            button.tap()
        }

        XCTAssertTrue(app.staticTexts["后期交接包"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["生成并分享"].isHittable)
    }
}
