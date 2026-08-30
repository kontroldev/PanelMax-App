# Aparcado para la 1.1

Este código no forma parte de la build de la 1.0. Vive fuera de `PanelMax/`
a propósito: Xcode 16+ sincroniza automáticamente todo lo que hay dentro de
`PanelMax/` como parte del target, así que sacarlo de esa carpeta es la
forma más simple de excluirlo sin tocar el `.pbxproj` a mano.

## Por qué existe

La 1.0 es una app 100% local: sin catálogo remoto, sin cuenta, sin compras.
Eso permite declararse *no-trader* ante la Digital Services Act de la UE y
publicar sin esperar al alta de autónomo. El catálogo y la suscripción
vuelven en la 1.1, cuando haya un servicio real (datos de series, próximos
lanzamientos) que justifique un cobro recurrente ante Guideline 3.1.2 de
Apple: las suscripciones autorrenovables solo se aprueban para servicios de
valor continuado, no para desbloquear límites de una colección local.

## Qué hay aquí

- `Store/SubscriptionStore.swift` — StoreKit 2, ya con verificación de
  transacciones, `restore()` y el listener de `Transaction.updates`.
- `Store/PaywallView.swift` — el muro de pago con los enlaces legales
  obligatorios (3.1.2) ya marcados en el código.
- `Store/PremiumGate.swift` — `FreeLimits` y la lógica de qué acción bloquea
  qué límite.

## Al recuperarlo en la 1.1

1. Mover la carpeta `Store/` de vuelta a `PanelMax/Store/`.
2. `LegalLinks` vive dentro de `PaywallView.swift`: si `SettingsView` ya
   tiene su propia copia (para los enlaces de privacidad/soporte de la 1.0),
   unificarlas antes de que compile en duplicado.
3. Revisar `ProductID` y `PanelMax.storekit`: los identificadores no se
   pueden reciclar una vez usados en App Store Connect, así que decide los
   definitivos antes de crear los productos, no antes de tocar el código.
4. El código de `PremiumGate` asumía límites sobre la colección local
   (`FreeLimits.collectionEntries`, etc.). Si el modelo de negocio de la 1.1
   es "colección local gratis para siempre, catálogo de pago", ese gate ya
   no aplica a la colección: solo a las funciones del catálogo.
