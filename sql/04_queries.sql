-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- BASE DE DATOS: retail_inventory_db
-- ARCHIVO: 04_queries.sql
-- DESCRIPCIÓN: Consultas analíticas funcionales requeridas por el negocio.
-- =============================================================================

-- =============================================================================
-- CONSULTA 1: Detección de productos en stock bajo o crítico por sucursal
-- Objetivo: Identificar oportunamente artículos que requieren reabastecimiento
--           en la Sucursal 3 (Insurgentes Sur) ordenados alfabéticamente.
-- =============================================================================
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
-- CONSULTA 2: Trazabilidad y últimos 50 movimientos de inventario de un producto
-- Objetivo: Auditar auditoría de kardex para el Producto 125 en Sucursal 3,
--           inspeccionando entradas, salidas y ajustes más recientes.
-- =============================================================================
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
-- CONSULTA 3: Reporte de volumen y montos de ventas diarias en periodo clave
-- Objetivo: Analizar el comportamiento comercial y facturación de la Sucursal 3
--           durante el mes de Octubre de 2026 agrupado día por día.
-- =============================================================================
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

