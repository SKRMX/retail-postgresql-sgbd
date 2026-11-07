# Evidencias Visuales de Ejecución en pgAdmin 4

Este directorio contiene las capturas de pantalla reales obtenidas directamente desde la interfaz gráfica de **pgAdmin 4** (versión 9.19) conectado a la base de datos física `retail_inventory_db` sobre **PostgreSQL 17.2**.

Todas las evidencias corresponden a datos y ejecuciones reales sin simulación ni manipulación externa, demostrando el correcto despliegue del modelo relacional, integridad referencial, índices especializados y planes de ejecución (`EXPLAIN ANALYZE`).

---

## Índice de Evidencias

| Archivo | Objeto / Consulta Asociada | Contenido Visual Mostrado | Demostración Técnica |
| :--- | :--- | :--- | :--- |
| [`01_database_tables.png`](01_database_tables.png) | Esquema `public` (11 tablas) | Árbol de navegación de pgAdmin 4 expandido en `retail_inventory_db -> Schemas -> public -> Tables (11)`. | Demuestra la existencia física de las 11 entidades del modelo relacional de retail en PostgreSQL 17 (`categoria`, `compra`, `detalle_compra`, `detalle_venta`, `inventario`, `movimiento_inventario`, `producto`, `producto_proveedor`, `proveedor`, `sucursal`, `venta`). |
| [`02_erd.png`](02_erd.png) | Modelo Relacional Completo | Diagrama Entidad-Relación generado automáticamente por la herramienta **ERD Tool** de pgAdmin 4. | Evidencia la arquitectura relacional íntegra, todas las claves primarias (PK), foráneas (FK), atributos tipados y las relaciones 1:N entre las 11 tablas con notación pata de gallo. |
| [`03_schema_constraints_indexes.png`](03_schema_constraints_indexes.png) | Tabla `inventario` | Árbol de propiedades expandido en `Constraints` e `Indexes`, junto con la pestaña `SQL` que muestra el DDL real generado por pgAdmin. | Demuestra la implementación física rigurosa: clave primaria compuesta `(id_sucursal, id_producto)`, claves foráneas a `producto` y `sucursal`, restricciones de validación `CHECK (existencia >= 0)` y el índice especializado parcial `idx_inventario_stock_bajo`. |
| [`04_query_stock_low.png`](04_query_stock_low.png) | **Consulta 1**: Detección de Stock Crítico | Query Tool con el SQL de Consulta 1 y la grilla de datos (*Data Output*) mostrando filas devueltas. | Comprueba la funcionalidad de la consulta analítica para reabastecimiento en Sucursal 3 (Insurgentes Sur), devolviendo exactamente **639 filas** ordenadas alfabéticamente por nombre de producto con su existencia y stock mínimo. |
| [`05_explain_stock_low.png`](05_explain_stock_low.png) | **EXPLAIN ANALYZE 1**: Plan Consulta 1 | Plan de ejecución detallado con `EXPLAIN (ANALYZE, BUFFERS)` en el Query Tool. | Evidencia el uso efectivo del índice parcial `idx_inventario_stock_bajo` mediante `Bitmap Index Scan` (Buffers hit: 4, cost 0.00..36.74) seguido de `Bitmap Heap Scan` (Buffers hit: 323), ejecutando en ~1.96 ms. |
| [`06_query_inventory_movements.png`](06_query_inventory_movements.png) | **Consulta 2**: Kardex y Trazabilidad | Query Tool con el SQL de Consulta 2 y Data Output con las 50 filas devueltas. | Demuestra la auditoría de movimientos para el Producto 125 en Sucursal 3, mostrando los últimos 50 registros cronológicos ordenados descendentemente (`ORDER BY fecha DESC LIMIT 50`), con fechas válidas del año 2026. |
| [`07_explain_inventory_movements.png`](07_explain_inventory_movements.png) | **EXPLAIN ANALYZE 2**: Plan Consulta 2 | Plan de ejecución real con buffers y métodos de ordenamiento. | Evidencia técnica real del optimizador: filtra 120,000 movimientos a 150 filas candidatas mediante `Bitmap Index Scan on idx_movimiento_sucursal_producto_fecha` (Buffers hit: 3), y resuelve el límite mediante `Sort (top-N heapsort, Memory: 32kB)` para devolver las 50 filas más recientes en ~0.16 ms. |
| [`08_query_sales_october.png`](08_query_sales_october.png) | **Consulta 3**: Ventas Diarias de Octubre 2026 | Query Tool con el SQL de Consulta 3 y Data Output con las 31 filas devueltas. | Valida el reporte de facturación diaria para Sucursal 3 durante octubre de 2026. Muestra exactamente **31 filas** (una por día del mes), con número de transacciones y suma total facturada. |
| [`09_explain_sales_october.png`](09_explain_sales_october.png) | **EXPLAIN ANALYZE 3**: Plan Consulta 3 | Plan de ejecución real para agregación temporal. | Demuestra el escaneo indexado mediante `Bitmap Index Scan on idx_venta_sucursal_fecha` (cost 0.00..27.37, 2,432 filas recuperadas en ~0.13 ms) seguido de `Bitmap Heap Scan` y `GroupAggregate`, completando en ~1.31 ms. |
| [`10_database_dashboard.png`](10_database_dashboard.png) | Panel de Monitoreo de `retail_inventory_db` | Pestaña **Dashboard** de pgAdmin 4 con gráficas en tiempo real de la base de datos. | Muestra métricas operativas de la instancia: sesiones activas, transacciones por segundo (TPS), tuplas leídas/devueltas (Tuples in/out) y lecturas de bloques de disco/memoria (Block I/O). |

---

## Especificaciones Técnicas del Entorno de Captura

- **SGBD**: PostgreSQL 17.2 (compiled by Visual C++ build 1942, 64-bit)
- **Herramienta de Administración**: pgAdmin 4 v9.19 (Desktop / Web Mode)
- **Base de Datos**: `retail_inventory_db`
- **Volumen de Datos Activo**: 357,899 registros distribuidos en 11 tablas relacionales
- **Resolución de Captura**: 1920 × 1080 píxeles a color (formato PNG nativo)
