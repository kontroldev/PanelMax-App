import Foundation
import SwiftData

/// Esquema versionado de PanelMax.
///
/// Existe desde la versión 1 a propósito, aunque todavía no haya nada que
/// migrar. El motivo es práctico: en cuanto la app está publicada, la primera
/// vez que cambies un modelo necesitas un `VersionedSchema` de partida contra el
/// que comparar. Si no lo creaste antes, no tienes forma de describir el "antes"
/// y la migración ligera de SwiftData puede fallar en dispositivos con datos
/// reales — que es exactamente el escenario que no puedes reproducir en el
/// simulador.
///
/// Los modelos viven DENTRO de `PanelMaxSchemaV1` (cada archivo de `Models/`
/// los declara en un `extension PanelMaxSchemaV1`). Es lo que hace posible
/// migrar: si `V1` apuntara a las clases que usa la app en cada momento, al
/// crear una `V2` las dos versiones describirían los mismos modelos y SwiftData
/// no sabría qué cambió. El nombre de cada tabla sigue siendo el de la clase
/// («Series», «Issue»...), así que anidarlos no altera la base de datos.
///
/// Cuando cambies un modelo:
/// 1. Copia los modelos actuales en un `PanelMaxSchemaV2` y haz ahí los cambios.
///    `V1` se queda congelado tal y como está.
/// 2. Añade `V2` a `schemas` en `PanelMaxMigrationPlan`.
/// 3. Declara la etapa (`.lightweight` o `.custom`) en `stages`.
/// 4. Apunta los `typealias` de abajo a los modelos de `V2`.
enum PanelMaxSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Series.self, Issue.self, CollectionEntry.self, ReadingProgress.self, LocalComicFile.self]
    }
}

// Nombres cortos para el resto de la app: las vistas y los stores siguen
// escribiendo `Series` o `Issue` sin saber en qué versión del esquema viven.
typealias Series = PanelMaxSchemaV1.Series
typealias Issue = PanelMaxSchemaV1.Issue
typealias CollectionEntry = PanelMaxSchemaV1.CollectionEntry
typealias ReadingProgress = PanelMaxSchemaV1.ReadingProgress
typealias LocalComicFile = PanelMaxSchemaV1.LocalComicFile

/// Plan de migración de la base de datos local.
enum PanelMaxMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [PanelMaxSchemaV1.self]
    }

    /// Vacío mientras solo exista una versión. No borres esta propiedad:
    /// es donde se encadenan las etapas en cuanto haya una V2.
    static var stages: [MigrationStage] { [] }
}

extension Schema {
    /// Esquema activo de la app. Un único sitio donde se listan los modelos,
    /// para que el contenedor de la app, el de las previsualizaciones y el de
    /// los tests no puedan quedar desincronizados entre sí.
    static var panelMax: Schema {
        Schema(PanelMaxSchemaV1.models, version: PanelMaxSchemaV1.versionIdentifier)
    }
}
