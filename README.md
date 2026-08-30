# PanelMax 📚

Aplicación iOS para catalogar una colección de cómics a mano y leer archivos
propios en CBZ y PDF. Funciona por completo sin conexión: sin catálogo
remoto, sin cuenta y sin compras.

[![CI](https://github.com/kontroldev/PanelMax-App/actions/workflows/ci.yml/badge.svg)](https://github.com/kontroldev/PanelMax-App/actions/workflows/ci.yml)
![iOS](https://img.shields.io/badge/iOS-18%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-green)
![Versión](https://img.shields.io/badge/versi%C3%B3n-1.0-red)

## Funciones · versión 1.0

- Catalogar series a mano: título, editorial, año y números publicados en
  total, para calcular huecos y porcentaje de la colección.
- Añadir números uno a uno o por rango completo ("del 1 al 40" de una vez).
- Marcar cada número como poseído, deseado o leído, en papel o en digital.
- Importar, listar, abrir, vincular y eliminar archivos CBZ y PDF propios.
- Leer con progreso, caché, reducción de imágenes grandes, zoom persistente
  por pellizco o doble toque, arrastre dentro de la página, y un deslizador
  para saltar directamente a una página.
- Portada automática por cómic, generada desde su propia primera página: no
  hace falta catálogo remoto para tener miniaturas.
- Un cómic de bienvenida incluido, para que la biblioteca no empiece vacía.
- Exportar la colección catalogada a un archivo, como única copia de
  seguridad posible sin iCloud ni cuenta.
- Disfrutar de superficies Liquid Glass en iOS 26 en Inicio, la ficha de
  serie y el lector, con una apariencia equivalente y compatible en iOS 18–25.

## Capturas

<p align="center">
  <img src="docs/screenshots/inicio.png" width="280" alt="Pantalla de inicio de PanelMax">
  &nbsp;&nbsp;
  <img src="docs/screenshots/coleccion.png" width="280" alt="Colección de cómics de PanelMax">
</p>

<p align="center">
  <strong>Inicio</strong>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
  <strong>Mi colección</strong>
</p>

<p align="center">
  <sub>Pendiente de actualizar con capturas de la versión 1.0. Las antiguas
  mostraban el catálogo remoto, que ya no existe en esta versión.</sub>
</p>

PanelMax no distribuye cómics. Los archivos de lectura son seleccionados por
el usuario y se copian al contenedor privado de la app.

No están implementados en esta versión el catálogo remoto, la suscripción,
la sincronización con iCloud, la vista guiada viñeta a viñeta, el escáner de
códigos ni el uso compartido en familia. Volverán en versiones futuras
cuando haya un servicio real detrás que los justifique.

## Arquitectura

| Área | Implementación |
|---|---|
| Interfaz | SwiftUI, `NavigationStack` y estado Observable |
| Persistencia | SwiftData local; sin CloudKit |
| Portadas | Generadas en el dispositivo desde la página 1 del propio archivo |
| Lector | PDFKit, ImageIO y ZIPFoundation 0.9.20 |
| Pruebas | Swift Testing, sin dependencias externas ni acceso a red |
| Concurrencia | Modo de lenguaje Swift 6, aislamiento `MainActor` por defecto |

`CollectionStore` centraliza todas las escrituras sobre la colección
(crear series, añadir números por rango, cambiar estados, vincular
archivos). Ninguna vista toca `ModelContext` directamente.

Si el almacén persistente no puede abrirse, la app no borra la colección:
arranca con un contenedor temporal y muestra el problema.

El esquema está versionado desde la versión 1 en `PanelMaxSchema.swift`, con
un `SchemaMigrationPlan` ya conectado al contenedor. Cuando cambie un modelo
hay que añadir una `V2` y su etapa de migración; el esquema activo se declara
en un único sitio (`Schema.panelMax`) que comparten la app, las
previsualizaciones y los tests.

Los cómics importados viven en `Documents/Comics` y sus miniaturas en
`Documents/Covers`, ambas excluidas de la copia de seguridad de iCloud: son
archivos grandes (o regenerables) que no deben consumir la cuota de respaldo
del usuario.

## Requisitos y ejecución

- Xcode 26.6 o posterior (toolchain de Swift 6.4).
- iOS 18 o posterior. Solo iPhone en esta versión.

El proyecto compila en **modo de lenguaje Swift 6**: la concurrencia estricta
se comprueba en tiempo de compilación, no como avisos.

1. Clona el repositorio y abre `PanelMax.xcodeproj`.
2. Xcode resolverá automáticamente ZIPFoundation, fijado exactamente en la
   versión 0.9.20.
3. Ejecuta el esquema compartido `PanelMax`. Al primer arranque se importa un
   cómic de ejemplo para que la biblioteca no empiece vacía.
4. Usa `⌘U` para ejecutar los tests.

## Pruebas y CI

La suite incluye pruebas para:

- orden natural de números y especiales, con casos límite (cero, negativos, empates);
- alta de series y números, incluida el alta por rango y sus casos límite;
- huecos de una serie, porcentaje de progreso y estados de colección;
- que borrar una serie no borra el archivo importado que tenía vinculado;
- progreso de lectura del archivo importado y escrituras SwiftData;
- validación de rutas de archivo frente a nombres manipulados (`../`, separadores).

GitHub Actions (`.github/workflows/ci.yml`) ejecuta `PanelMaxTests` en un
simulador y compila además la configuración Release. Ninguna prueba necesita
red ni credenciales, porque la app tampoco las usa.

## Registro de cambios

### 1.0 — 30 de agosto de 2026

Reescritura para publicar sin depender de infraestructura externa. Sin
cambios en los datos que ya hubiera de la 1.1.0 de desarrollo: quien viniera
de esa build conserva su colección.

**Quitado**

- Catálogo remoto (Metron) y todo lo que dependía de él: búsqueda de series,
  portadas descargadas, próximos lanzamientos.
- Suscripción PanelMax+, muro de pago y límites del plan gratuito. El código
  se conserva aparte, en `Parked/`, para retomarlo cuando haya un catálogo
  real que justifique un cobro recurrente ante Guideline 3.1.2 de Apple.
- Soporte de iPad: solo iPhone hasta que haya trabajo real de layout para
  pantallas grandes.

**Añadido**

- Alta manual de series y números, incluido el alta por rango.
- Portada automática por cómic, generada desde su propia página 1.
- Pestaña propia de Biblioteca, con importar y buscar.
- Deslizador para saltar de página en el lector.
- Exportar la colección a un archivo.
- Un cómic de bienvenida incluido en el primer arranque.
- Flujo para vincular un archivo importado a un número catalogado.

**Corregido**

- El enlace de soporte apuntaba a un repositorio que no existía y devolvía 404.
- El badge de CI apuntaba a un flujo de GitHub Actions inexistente.
- La app declaraba región de desarrollo en inglés con toda la interfaz en
  español.

### 1.1.0 — 26 de agosto de 2026 (desarrollo, no publicada)

Build de desarrollo con catálogo remoto y suscripción, nunca enviada a App
Store Connect. Su historial de cambios queda documentado en el control de
versiones para quien retome ese trabajo en una versión futura.

## Antes de App Store

- [ ] Sustituir las capturas por otras de la versión 1.0 (sin catálogo).
- [ ] Comprobar desde un dispositivo real los tres enlaces legales de Perfil.
- [ ] Completar pruebas en dispositivo, accesibilidad y localización.
- [ ] Responder el cuestionario de clasificación por edad en App Store Connect.
- [ ] Declarar no-trader en la Digital Services Act (sin compras integradas).

Documentos incluidos: [Privacidad](docs/PRIVACY.md), [Soporte](docs/SUPPORT.md)
y [Términos](docs/TERMS.md).

## Autor

Raúl Gallego — [@kontroldev](https://github.com/kontroldev)

© Raúl Gallego. Todos los derechos reservados. Código visible con fines de
portfolio; no se concede licencia de uso ni redistribución.
