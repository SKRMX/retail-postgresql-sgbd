-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- BASE DE DATOS: retail_inventory_db
-- ARCHIVO: 05_explain_analyze.sql
-- DESCRIPCIÓN: Ejecución de planes reales mediante EXPLAIN (ANALYZE, BUFFERS)
--              para evidenciar el impacto de los índices y el comportamiento
--              del planificador de consultas de PostgreSQL.
-- =============================================================================

-- =============================================================================
-- EXPLAIN ANALYZE 1: Stock bajo en Sucursal 3
-- Evaluación del índice parcial idx_inventario_stock_bajo
-- =============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    p.sku,
    p.nombre,
    i.existencia,
    i.stock_minimo
FROM inventario i
JOIN producto p
    ON p.id_producto = i.id_producto
WHERE i.id_sucursal = 3
  AND i.existencia <= i.stock_minimo
ORDER BY p.nombre;

-- =============================================================================
-- EXPLAIN ANALYZE 2: Historial de movimientos (Sucursal 3, Producto 125)
-- Evaluación del índice compuesto idx_movimiento_sucursal_producto_fecha con LIMIT 50
-- =============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    fecha,
    tipo,
    cantidad,
    referencia
FROM movimiento_inventario
WHERE id_sucursal = 3
  AND id_producto = 125
ORDER BY fecha DESC
LIMIT 50;

-- =============================================================================
-- EXPLAIN ANALYZE 3: Ventas por sucursal en rango temporal (Octubre 2026)
-- Evaluación del índice idx_venta_sucursal_fecha
-- =============================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    DATE(fecha) AS dia,
    COUNT(*) AS numero_ventas,
    SUM(total) AS total_vendido
FROM venta
WHERE id_sucursal = 3
  AND fecha >= TIMESTAMP '2026-10-01'
  AND fecha < TIMESTAMP '2026-11-01'
GROUP BY DATE(fecha)
ORDER BY dia;

