-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- BASE DE DATOS: retail_inventory_db
-- ARCHIVO: 07_transactions.sql
-- DESCRIPCIÓN: Demostración de transacciones ACID en PostgreSQL:
--              1. Transacción exitosa (BEGIN ... COMMIT): Venta, detalle,
--                 actualización de stock y movimiento histórico.
--              2. Transacción abortada (BEGIN ... ROLLBACK): Simulación de falla
--                 (e.g., fondos insuficientes o interrupción) comprobando que
--                 no persisten cambios parciales.
-- =============================================================================

-- =============================================================================
-- CASO 1: TRANSACCIÓN EXITOSA DE VENTA (COMMIT)
-- =============================================================================
-- Escenario: La Sucursal 1 vende 2 unidades del Producto 10.
-- 1. Verificamos el stock antes de la transacción
SELECT id_sucursal, id_producto, existencia
FROM inventario
WHERE id_sucursal = 1 AND id_producto = 10;

BEGIN;

-- Paso 1: Registrar cabecera de la venta
INSERT INTO venta (id_sucursal, fecha, total, metodo_pago)
VALUES (1, CURRENT_TIMESTAMP, 0.00, 'TARJETA_CREDITO')
RETURNING id_venta;
-- Supongamos que el ID generado o capturado se maneja en la sesión

-- Paso 2: Obtener el precio y registrar el detalle de la venta (ej. para la venta más reciente de la sucursal)
WITH nueva_venta AS (
    SELECT id_venta
    FROM venta
    WHERE id_sucursal = 1
    ORDER BY id_venta DESC
    LIMIT 1
)
INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, subtotal)
SELECT
    nv.id_venta,
    10 AS id_producto,
    2 AS cantidad,
    p.precio_venta,
    ROUND((2 * p.precio_venta)::numeric, 2) AS subtotal
FROM nueva_venta nv
JOIN producto p ON p.id_producto = 10;

-- Paso 3: Actualizar el total de la venta en la cabecera
WITH nueva_venta AS (
    SELECT id_venta
    FROM venta
    WHERE id_sucursal = 1
    ORDER BY id_venta DESC
    LIMIT 1
),
suma_detalles AS (
    SELECT SUM(subtotal) AS total_calculado
    FROM detalle_venta
    WHERE id_venta = (SELECT id_venta FROM nueva_venta)
)
UPDATE venta
SET total = (SELECT total_calculado FROM suma_detalles)
WHERE id_venta = (SELECT id_venta FROM nueva_venta);

-- Paso 4: Descontar stock en inventario (asegurando existencia suficiente >= 2)
UPDATE inventario
SET existencia = existencia - 2,
    updated_at = CURRENT_TIMESTAMP
WHERE id_sucursal = 1
  AND id_producto = 10
  AND existencia >= 2;

-- Paso 5: Registrar la trazabilidad del movimiento de SALIDA
INSERT INTO movimiento_inventario (id_sucursal, id_producto, tipo, cantidad, fecha, referencia)
VALUES (
    1,
    10,
    'SALIDA',
    2,
    CURRENT_TIMESTAMP,
    'VENTA-TRANSACCIONAL-EXITOSA-' || (SELECT MAX(id_venta) FROM venta WHERE id_sucursal = 1)
);

-- Confirmar todas las operaciones de forma atómica
COMMIT;

-- Verificación posterior al COMMIT: El stock disminuyó exactamente 2 unidades
SELECT id_sucursal, id_producto, existencia
FROM inventario
WHERE id_sucursal = 1 AND id_producto = 10;


-- =============================================================================
-- CASO 2: TRANSACCIÓN ABORTADA POR ERROR O CONDICIÓN CONTROLADA (ROLLBACK)
-- =============================================================================
-- Escenario: Se inicia una venta, se registra la cabecera y el detalle, pero se
-- detecta una anomalía (ej. fallo en terminal bancaria o stock insuficiente).
-- Se emite ROLLBACK y se demuestra que el estado de la base de datos queda intacto.

-- 1. Capturar el total de ventas antes de la prueba
SELECT COUNT(*) AS total_ventas_antes FROM venta;

BEGIN;

-- Registrar venta preliminar
INSERT INTO venta (id_sucursal, fecha, total, metodo_pago)
VALUES (2, CURRENT_TIMESTAMP, 1500.00, 'TARJETA_RECHAZADA');

-- Insertar detalle
INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, subtotal)
VALUES ((SELECT MAX(id_venta) FROM venta), 20, 1, 1500.00, 1500.00);

-- Descuento tentativo de inventario
UPDATE inventario
SET existencia = existencia - 1
WHERE id_sucursal = 2 AND id_producto = 20;

-- Se produce una excepción / rechazo del pago -> Deshacer completamente
ROLLBACK;

-- Verificación posterior al ROLLBACK: La venta y el detalle NO existen y el stock no cambió
SELECT COUNT(*) AS total_ventas_despues FROM venta;

SELECT *
FROM venta
WHERE metodo_pago = 'TARJETA_RECHAZADA';

