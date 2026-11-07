-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- BASE DE DATOS: retail_inventory_db
-- ARCHIVO: 07_transactions.sql
-- DESCRIPCIÓN: Demostración de transacciones ACID en PostgreSQL:
--              1. Transacción exitosa (COMMIT) con captura segura de clave
--                 mediante RETURNING id_venta INTO v_id_venta (sin MAX) y
--                 validación estricta de stock disponible.
--              2. Transacción abortada por regla de negocio (Stock insuficiente).
--              3. Transacción abortada manualmente mediante ROLLBACK (Fallo simulado).
-- =============================================================================

SET client_min_messages = notice;

-- =============================================================================
-- CASO 1: TRANSACCIÓN EXITOSA DE VENTA (COMMIT SEGURO PARA CONCURRENCIA)
-- =============================================================================
-- Escenario: La Sucursal 1 vende 2 unidades del Producto 10.
-- 1. Verificamos el stock antes de la transacción
SELECT id_sucursal, id_producto, existencia
FROM inventario
WHERE id_sucursal = 1 AND id_producto = 10;

DO $$
DECLARE
    v_id_venta BIGINT;
    v_precio_unitario NUMERIC(12, 2);
    v_subtotal NUMERIC(14, 2);
    v_filas_actualizadas INT;
BEGIN
    -- Paso 1: Consultar precio de venta del producto
    SELECT precio_venta INTO v_precio_unitario
    FROM producto
    WHERE id_producto = 10;

    v_subtotal := ROUND((2 * v_precio_unitario)::numeric, 2);

    -- Paso 2: Insertar venta y capturar id_venta directamente (seguro en concurrencia)
    INSERT INTO venta (id_sucursal, fecha, total, metodo_pago)
    VALUES (1, CURRENT_TIMESTAMP, v_subtotal, 'TARJETA_CREDITO')
    RETURNING id_venta INTO v_id_venta;

    -- Paso 3: Insertar detalle utilizando exclusivamente v_id_venta (sin MAX)
    INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, subtotal)
    VALUES (v_id_venta, 10, 2, v_precio_unitario, v_subtotal);

    -- Paso 4: Descontar stock verificando disponibilidad suficiente (existencia >= 2)
    UPDATE inventario
    SET existencia = existencia - 2,
        updated_at = CURRENT_TIMESTAMP
    WHERE id_sucursal = 1
      AND id_producto = 10
      AND existencia >= 2;

    -- Validar que se haya actualizado exactamente una fila
    GET DIAGNOSTICS v_filas_actualizadas = ROW_COUNT;
    IF v_filas_actualizadas = 0 THEN
        RAISE EXCEPTION 'Stock insuficiente para el Producto 10 en Sucursal 1';
    END IF;

    -- Paso 5: Registrar trazabilidad histórica solo tras validar stock
    INSERT INTO movimiento_inventario (id_sucursal, id_producto, tipo, cantidad, fecha, referencia)
    VALUES (1, 10, 'SALIDA', 2, CURRENT_TIMESTAMP, 'VENTA-EXITOSA-' || v_id_venta::text);

    RAISE NOTICE '[ÉXITO COMMIT] Venta % confirmada. Stock descontado. Total: $%', v_id_venta, v_subtotal;
END $$;

-- Verificación posterior: El stock disminuyó exactamente 2 unidades
SELECT id_sucursal, id_producto, existencia
FROM inventario
WHERE id_sucursal = 1 AND id_producto = 10;


-- =============================================================================
-- CASO 2: TRANSACCIÓN ABORTADA POR STOCK INSUFICIENTE (PROTECCIÓN DE INTEGRIDAD)
-- =============================================================================
-- Escenario: Se intenta vender una cantidad excesiva (50,000 unidades) del Producto 10.
-- La validación detecta que no hay stock, aborta la transacción y revierte todo cambio.

SELECT existencia AS stock_antes_intento_invalido
FROM inventario
WHERE id_sucursal = 1 AND id_producto = 10;

DO $$
DECLARE
    v_id_venta BIGINT;
    v_precio_unitario NUMERIC(12, 2);
    v_subtotal NUMERIC(14, 2);
    v_filas_actualizadas INT;
    v_cantidad_solicitada INT := 50000; -- Cantidad que supera la existencia
BEGIN
    SELECT precio_venta INTO v_precio_unitario
    FROM producto
    WHERE id_producto = 10;

    v_subtotal := ROUND((v_cantidad_solicitada * v_precio_unitario)::numeric, 2);

    -- Se intenta crear la venta
    INSERT INTO venta (id_sucursal, fecha, total, metodo_pago)
    VALUES (1, CURRENT_TIMESTAMP, v_subtotal, 'EFECTIVO')
    RETURNING id_venta INTO v_id_venta;

    INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, subtotal)
    VALUES (v_id_venta, 10, v_cantidad_solicitada, v_precio_unitario, v_subtotal);

    -- Intento de descuento con condición de existencia suficiente
    UPDATE inventario
    SET existencia = existencia - v_cantidad_solicitada,
        updated_at = CURRENT_TIMESTAMP
    WHERE id_sucursal = 1
      AND id_producto = 10
      AND existencia >= v_cantidad_solicitada;

    GET DIAGNOSTICS v_filas_actualizadas = ROW_COUNT;
    IF v_filas_actualizadas = 0 THEN
        RAISE EXCEPTION 'Stock insuficiente para vender % unidades del Producto 10', v_cantidad_solicitada;
    END IF;

    -- Este paso NO llegará a ejecutarse
    INSERT INTO movimiento_inventario (id_sucursal, id_producto, tipo, cantidad, fecha, referencia)
    VALUES (1, 10, 'SALIDA', v_cantidad_solicitada, CURRENT_TIMESTAMP, 'VENTA-FALLIDA-' || v_id_venta::text);

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE '[ABORTADO POR STOCK] Transacción revertida correctamente: %', SQLERRM;
END $$;

-- Verificación posterior: El stock permanece exactamente igual que antes del intento
SELECT existencia AS stock_despues_intento_invalido
FROM inventario
WHERE id_sucursal = 1 AND id_producto = 10;


-- =============================================================================
-- CASO 3: TRANSACCIÓN ABORTADA EXPLÍCITAMENTE (ROLLBACK)
-- =============================================================================
-- Escenario: Simulación de fallo en pasarela de pagos durante un flujo SQL interactivo.
-- Se demuestra que un ROLLBACK manual no deja tuplas huérfanas ni modifica el stock.

SELECT COUNT(*) AS total_ventas_antes_rollback FROM venta;

BEGIN;

-- Se inserta venta provisional
INSERT INTO venta (id_sucursal, fecha, total, metodo_pago)
VALUES (2, CURRENT_TIMESTAMP, 1500.00, 'TARJETA_RECHAZADA');

-- Descuento tentativo de inventario
UPDATE inventario
SET existencia = existencia - 1
WHERE id_sucursal = 2 AND id_producto = 20;

-- Simulación de evento de rechazo bancario -> Emisión de ROLLBACK
ROLLBACK;

-- Verificación: Las ventas se mantienen sin cambios y no existe el método rechazado
SELECT COUNT(*) AS total_ventas_despues_rollback FROM venta;

SELECT COUNT(*) AS ventas_con_metodo_rechazado
FROM venta
WHERE metodo_pago = 'TARJETA_RECHAZADA';
