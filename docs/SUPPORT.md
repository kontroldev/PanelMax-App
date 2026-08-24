# Soporte de PanelMax
PanelMax está en desarrollo activo. Para informar de un error o solicitar ayuda, abre una incidencia en [GitHub Issues](https://github.com/kontroldev/PanelMax/issues) o escribe a [raulgallego79@icloud.com](mailto:raulgallego79@icloud.com).

Incluye, cuando sea posible:

- versión de PanelMax y de iOS;
- modelo del dispositivo;
- pasos para reproducir el problema;
- mensaje de error visible.

No publiques ni envíes archivos CBZ/PDF, contraseñas, tokens del catálogo, recibos completos ni otros datos personales.

## Problemas habituales

### El catálogo no está disponible

Las builds Debug usan un catálogo ficticio de forma predeterminada. Una build Release necesita la URL HTTPS de un backend de catálogo configurada por el distribuidor. PanelMax muestra un aviso si la build no dispone de esa configuración; no es necesario introducir credenciales en el dispositivo.

### Un archivo no se abre

Comprueba que sea un PDF válido o un CBZ/ZIP que contenga imágenes compatibles. Vuelve a importarlo si el archivo original se movió o dejó de estar disponible. Evita compartir el archivo al solicitar soporte.

### Una compra no aparece

Usa «Restaurar compras» con el mismo Apple ID que realizó la compra. Si StoreKit confirma el cargo pero PanelMax no recupera el acceso, adjunta únicamente el identificador de producto y la fecha aproximada; no envíes información bancaria.

## Compatibilidad

La versión actual tiene como mínimo iOS 18 y está diseñada para iPhone y iPad.
