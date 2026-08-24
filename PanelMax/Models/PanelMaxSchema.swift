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
/// Cuando cambies un modelo:
/// 1. Duplica `V1` en un `V2` con los modelos nuevos.
/// 2. Añade `V2` a `schemas` en `PanelMaxMigrationPlan`.
/// 3. Declara la etapa (`.lightweight` o `.custom`) en `stages`.
enum PanelMaxSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Series.self, Issue.self, CollectionEntry.self, ReadingProgress.self, LocalComicFile.self]
    }
}

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
