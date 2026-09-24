# Guía para subir Viñe (PanelMax) a la App Store

Este archivo es una chuleta autocontenida. Si algo falla y no tienes esta
conversación a mano (o Xcode cerrado), pega este archivo entero en un chat
nuevo con Claude y pídele que te guíe desde aquí.

Proyecto: `PanelMax-App` (rama `version-beta`), app visible como **Viñe**,
bundle ID `com.kontroldesignstudio.vine`.

## Ya corregido en el repo (sesión del 21-22 de sept. 2026)

- `README.md`: 3 menciones a "PanelMax" que debían decir "Viñe" (alt de
  capturas y la frase "Viñe no distribuye cómics"). Ya corregido.
- `docs/SUPPORT.md`: decía "diseñada para iPhone", ahora dice "diseñada
  para iPhone y iPad". Ya corregido.
- Estos cambios están en disco pero **sin commitear** todavía.
- `AddIssuesView.swift`: cambio de teclado `.numberPad` → `.numbersAndPunctuation`
  en el rango de números (para que en iPad no tape el campo). También sin
  commitear.

## Pendiente: pasos manuales en Xcode (no se pueden hacer por script)

### 1. El menú de iPad sigue diciendo "PanelMax" en vez de "Viñe"

Causa: `PRODUCT_NAME = "$(TARGET_NAME)"` hace que `CFBundleName` sea
"PanelMax" (el nombre del target), aunque `CFBundleDisplayName` ya es
"Viñe". El icono de Inicio ya sale bien porque usa `CFBundleDisplayName`;
lo que falta es el menú de la barra superior en iPad con teclado físico y
algunos menús del sistema, que usan `CFBundleName`.

**Pasos:**
1. Xcode → selecciona el proyecto **PanelMax** en el navegador → target
   **PanelMax** (el de la app, no `PanelMaxTests` ni `PanelMaxUITests`).
2. Pestaña **Build Settings**. Arriba, pon el filtro en **All** y
   **Combined** (no "Basic").
3. Botón **+** de la barra superior de la tabla (o menú *Editor → Add
   Build Setting → Add User-Defined Setting*).
4. Nombre exacto: `INFOPLIST_KEY_CFBundleName`
5. Valor: `Viñe`, para **Debug** y **Release**.
6. No toques `PRODUCT_NAME`: si lo cambias, renombras el `.app` compilado.
7. `Product → Clean Build Folder` (⇧⌘K) y vuelve a compilar.

### 2. Enlaces legales apuntando a GitHub Pages en vez de a `blob`

Ahora `LegalLinks.swift` apunta a URLs tipo
`https://github.com/kontroldev/PanelMax-App/blob/main/docs/PRIVACY.md`,
que se ven con toda la interfaz de GitHub (banner de login, etc.).

**Pasos:**
1. En GitHub (web): repo → **Settings → Pages**.
2. **Source**: rama `main`, carpeta **`/docs`**. Guardar.
3. Esperar unos minutos: te da una URL tipo
   `https://kontroldev.github.io/PanelMax-App/`.
4. Avísame (a Claude) de la URL final y te actualizo `LegalLinks.swift`
   para que `terms`, `privacy` y `support` apunten ahí en vez de a los
   `blob`.

## Checklist restante para el envío (de la propia sección "Antes de App
Store" del README, con mi valoración de viabilidad)

- [ ] `NavigationSplitView` en Mi colección para iPad — viable, pendiente.
- [ ] Sustituir capturas del README/App Store Connect por las de la 1.0
      (sin catálogo remoto) — viable, solo contenido.
- [ ] Capturas de iPad de 13" para App Store Connect — **obligatorias**
      porque `TARGETED_DEVICE_FAMILY = "1,2"` (soportas iPad).
- [ ] Comprobar en un dispositivo real los tres enlaces legales de Perfil
      — hazlo después de activar GitHub Pages (paso 2 de arriba).
- [ ] Completar pruebas en dispositivo y de localización.
- [ ] Ampliar la cobertura de UI Tests.
- [ ] Responder el cuestionario de clasificación por edad en App Store
      Connect — trámite, no código.
- [ ] Declarar no-trader en la Digital Services Act — trámite, no código.
- [ ] Confirmar que el Bundle Identifier (`com.kontroldesignstudio.vine`)
      encaja con la cuenta de Apple Developer que vas a usar.

## Tarjetas de Trello revisadas (tablero "Viñe — Desarrollo")

- **"Poner función de pedir permiso al carrete de fotos"** (Backlog): NO
  la implementes. `SeriesFormView.swift` ya usa `PhotosPicker` (el picker
  moderno de SwiftUI/PHPicker), que por diseño de Apple no necesita
  permiso — corre fuera de proceso y solo te entrega la foto elegida.
  Pedir permiso sería un paso atrás en buenas prácticas.
- **"Tarjeta duplicadas"** y **"Visualizacion de vista de comis"** (En
  desarrollo): descritas en detalle en Trello, casi calcan fixes que el
  propio README dice ya hechos en la Beta del 11 sept 2026 (portada
  automática al vincular, lector horizontal en iPhone). Antes de tocar
  código, comprueba en un dispositivo si ya están arregladas o si el bug
  persiste.
- **"Adaptar la app con iPhone Duo"**: sin aclarar todavía, no existe tal
  dispositivo de Apple. Pregúntale a Raúl qué quería decir antes de
  planificarla.

## Contexto de negocio (para no romper el plan)

- Versión actual: **gratis, 100% local**, sin catálogo remoto, sin
  cuenta, sin compras (`Parked/` guarda el código de suscripción para
  cuando haya un catálogo real que lo justifique — no tocar esa carpeta).
- Suscripción prevista para más adelante, no para este envío.
- La app usa superficies **Liquid Glass** en iOS 26 (Inicio, ficha de
  serie, lector) con equivalente visual en iOS 18-25 — cualquier vista
  nueva (p. ej. el `NavigationSplitView` de iPad) debería mantener ese
  mismo lenguaje visual.
