# Notas para la revisión de App Store

Este documento recoge lo que hay que rellenar en App Store Connect →
**App Review Information** para que el revisor de Apple pueda probar la app.

## Por qué hace falta

La 1.0 no trae ningún cómic incluido ni descarga contenido. Un revisor que
instala la app en un dispositivo limpio ve la biblioteca vacía y no puede
probar la función principal (leer). Sin archivos de prueba el rechazo típico
es por la guideline 2.1 (*App Completeness / Information Needed*).

## Qué subir

- **Attachment** (campo de App Review Information): sube
  `Sample-Comic.cbz` y `Sample-Comic.pdf` de esta carpeta (o un ZIP con los
  dos).
- **Enlace de descarga** en las notas: súbelos también a la web, por ejemplo
  a `https://kontroldesignstudio.com/vine/sample/`, y comprueba desde Safari
  en un iPhone que se descargan a la app Archivos. Si la URL final es otra,
  cámbiala en el texto de abajo.
- **Sign-in required**: desmarcado (la app no tiene cuentas).

Los archivos se generan con `swift scripts/make_review_comic.swift`. Son
dibujos originales hechos por código, sin personajes, arte ni marcas de
terceros.

## Texto para el campo "Notes" (copiar y pegar)

```
Viñe is a fully offline comic reader and collection tracker. It has no
accounts, no in-app purchases, no ads and makes no network requests. It does
not ship with or download any comics: users read files they already own
(CBZ, ZIP or PDF) by importing them from the Files app.

The interface is in Spanish. To test reading, please use our original,
royalty-free sample comic (CC0), attached to this submission and also
available here:

  CBZ: https://kontroldesignstudio.com/vine/sample/Sample-Comic.cbz
  PDF: https://kontroldesignstudio.com/vine/sample/Sample-Comic.pdf

Quickest way to try the reader: open Viñe, skip or finish the short
introduction, go to the "Biblioteca" (Library) tab and tap "Abrir ejemplo"
(Open sample). A short built-in sample comic opens in the reader without
being added to the library.

Steps to test importing:
1. Download the sample file in Safari and save it to Files (On My iPhone /
   iPad or iCloud Drive).
2. Open Viñe and skip or finish the short introduction.
3. Go to the "Biblioteca" (Library) tab and tap "+" (top right) or
   "Importar cómic" (Import comic). Select the sample file.
4. Tap the imported comic to open the reader. Swipe to turn pages, pinch or
   double-tap to zoom. On iPad in landscape, pages are shown as two-page
   spreads.
5. Optional: in "Mi colección" (My collection), tap "+" to create a series,
   add issue numbers and link the imported file to an issue.

Imported files are copied into the app's own sandbox and are only stored on
the device. The "Perfil" (Profile) tab contains links to the privacy
policy, terms and support pages.
```
