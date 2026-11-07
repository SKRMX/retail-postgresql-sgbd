-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- BASE DE DATOS: retail_inventory_db
-- ARCHIVO: 03_indexes.sql
-- DESCRIPCIÓN: Creación de índices especializados para optimizar las tres
--              consultas analíticas principales del sistema de inventario retail.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- ÍNDICE PARA CONSULTA 1: Detección Rápida de Stock Bajo por Sucursal
-- Tipo: Índice Parcial B-Tree Compuesto
-- Razón técnica:
-- Filtra exclusivamente las tuplas críticas donde existencia <= stock_minimo.
-- Al ser parcial, ocupa una fracción mínima de almacenamiento y memoria RAM
-- en comparación con indexar las 50,000 tuplas de la tabla inventario.
-- La clave compuesta (id_sucursal, id_producto) permite filtrar la sucursal
-- y resolver el JOIN con producto de forma óptima.
-- -----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_inventario_stock_bajo;
CREATE INDEX idx_inventario_stock_bajo
ON inventario (id_sucursal, id_producto)
WHERE existencia <= stock_minimo;

-- -----------------------------------------------------------------------------
-- ÍNDICE PARA CONSULTA 2: Historial Cronológico de Movimientos de un Producto
-- Tipo: Índice B-Tree Compuesto con Orden Descendente
-- Razón técnica:
-- Cubre los predicados de igualdad (id_sucursal, id_producto) y reduce
-- drásticamente el conjunto candidato de 120,000 filas a solo 150 filas mediante
-- un Bitmap Index Scan altamente selectivo. Posteriormente, el motor ejecuta
-- un top-N heapsort mínimo en memoria compartida (32 kB) para obtener las 50
-- filas más recientes requeridas por el LIMIT 50. La presencia de fecha DESC
-- hace que el índice sea conceptualmente idóneo para este patrón, permitiendo
-- un acceso ultrarrápido y focalizado.
-- -----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_movimiento_sucursal_producto_fecha;
CREATE INDEX idx_movimiento_sucursal_producto_fecha
ON movimiento_inventario (id_sucursal, id_producto, fecha DESC);

-- -----------------------------------------------------------------------------
-- ÍNDICE PARA CONSULTA 3: Ventas por Sucursal en Periodo Temporal
-- Tipo: Índice B-Tree Compuesto (id_sucursal, fecha DESC)
-- Razón técnica:
-- Permite acceso directo al subconjunto de transacciones de la sucursal indicada
-- y realizar un recorrido por rango (range scan) exacto entre las fechas dadas,
-- descartando eficientemente el 95%+ de ventas de otras sucursales o periodos.
-- -----------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_venta_sucursal_fecha;
CREATE INDEX idx_venta_sucursal_fecha
ON venta (id_sucursal, fecha DESC);

-- -----------------------------------------------------------------------------
-- ACTUALIZACIÓN DE ESTADÍSTICAS DEL OPTIMIZADOR
-- -----------------------------------------------------------------------------
ANALYZE;

