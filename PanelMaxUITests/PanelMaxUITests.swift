//
//  PanelMaxUITests.swift
//  PanelMaxUITests
//
//  Created by Raul Gallego on 20/08/2026.
//

import XCTest

final class PanelMaxUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Recorre las cinco páginas del onboarding con "Siguiente" y termina
    /// con "Empezar", comprobando que al acabar se ve la app real (la barra
    /// de pestañas). `-uiTestsShowOnboarding` fuerza que se muestre sin
    /// depender de si el simulador ya la había marcado como vista.
    @MainActor
    func testOnboardingCanBeCompletedWithNextButtons() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsInMemoryStore", "-uiTestsShowOnboarding"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Bienvenido a Viñe"].waitForExistence(timeout: 5))

        // 5 páginas: de la 0 a la última (4) hacen falta 4 toques en "Siguiente".
        for _ in 0..<4 {
            app.buttons["Siguiente"].firstMatch.tap()
        }

        let startButton = app.buttons["Empezar"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 2))
        startButton.tap()

        XCTAssertTrue(app.buttons["Mi colección"].firstMatch.waitForExistence(timeout: 2))
    }

    /// Salta la introducción con la X y comprueba que se llega directamente
    /// a la app.
    @MainActor
    func testOnboardingCanBeSkipped() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsInMemoryStore", "-uiTestsShowOnboarding"]
        app.launch()

        // Se espera a que el onboarding esté en pantalla antes de pulsar la X:
        // sin esto, en un arranque lento el toque llegaba antes de que el
        // `fullScreenCover` terminara de presentarse y se perdía.
        let skipButton = app.buttons["Saltar la introducción"].firstMatch
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        // Margen para la animación de cierre del `fullScreenCover`.
        XCTAssertTrue(app.buttons["Mi colección"].firstMatch.waitForExistence(timeout: 5))
    }

    /// Crea una serie desde cero, comprueba que aparece en la lista y la
    /// elimina desde su ficha. Cubre el camino de alta/borrado manual que
    /// sustituye a la búsqueda de catálogo en la 1.0.
    ///
    /// La barra de pestañas flotante nueva expone cada botón por duplicado
    /// en el árbol de accesibilidad (contenedor + botón interno): por eso
    /// todos los botones de este test usan `.firstMatch` en vez de asumir
    /// que la consulta devuelve un único elemento.
    @MainActor
    func testCreateAndDeleteSeries() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestsInMemoryStore", "-uiTestsSkipOnboarding"]
        app.launch()

        app.buttons["Mi colección"].firstMatch.tap()

        let addButton = app.buttons["Nueva serie"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))
        addButton.tap()

        let titleField = app.textFields["Título"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText("Cuervo Negro")

        app.buttons["Guardar"].firstMatch.tap()

        let seriesRow = app.staticTexts["Cuervo Negro"].firstMatch
        XCTAssertTrue(seriesRow.waitForExistence(timeout: 2))
        seriesRow.tap()

        app.buttons["Opciones de la serie"].firstMatch.tap()
        app.buttons["Eliminar serie"].firstMatch.tap() // el ítem del menú, abre el confirmationDialog
        app.buttons["Eliminar serie"].firstMatch.tap() // el botón destructivo del propio diálogo

        XCTAssertTrue(app.staticTexts["Aún no has catalogado nada"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Cuervo Negro"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
