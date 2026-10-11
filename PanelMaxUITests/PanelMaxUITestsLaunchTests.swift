//
//  PanelMaxUITestsLaunchTests.swift
//  PanelMaxUITests
//
//  Created by Raul Gallego on 20/08/2026.
//

import XCTest

final class PanelMaxUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // Almacén en memoria: la captura no debe depender de lo que haya en la
        // colección real del simulador, ni modificarla.
        app.launchArguments = ["-uiTestsInMemoryStore"]
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
