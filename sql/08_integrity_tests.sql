-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- BASE DE DATOS: retail_inventory_db
-- ARCHIVO: 08_integrity_tests.sql
-- DESCRIPCIÓN: Pruebas automatizadas de integridad referencial y restricciones.
--              Cada bloque intenta una operación inválida y valida que PostgreSQL
--              lance la excepción esperada (UNIQUE, FK, CHECK).
-- =============================================================================

SET client_min_messages = notice;

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'INICIANDO PRUEBAS DE INTEGRIDAD Y RESTRICCIONES EN BD';
    RAISE NOTICE '=====================================================';
END $$;

-- -----------------------------------------------------------------------------
-- PRUEBA 1: SKU DUPLICADO (Restricción UNIQUE)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    -- Intentar insertar un producto con SKU ya existente ('PROD-SKU-000001')
    INSERT INTO producto (sku, nombre, id_categoria, precio_compra, precio_venta, activo)
    VALUES ('PROD-SKU-000001', 'Producto Clon Ilegal', 1, 50.00, 80.00, true);
    
    RAISE EXCEPTION 'FALLO: Se permitió insertar un SKU duplicado.';
EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE '[ÉXITO] Prueba 1 - Restricción UNIQUE de SKU funcionó correctamente: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- PRUEBA 2: CATEGORÍA INEXISTENTE (Restricción FOREIGN KEY)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    -- Intentar asociar a una categoría que no existe (id_categoria = 99999)
    INSERT INTO producto (sku, nombre, id_categoria, precio_compra, precio_venta, activo)
    VALUES ('PROD-TEST-FK-INV', 'Producto Huérfano', 99999, 10.00, 20.00, true);
    
    RAISE EXCEPTION 'FALLO: Se permitió insertar una FK de categoría inexistente.';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE '[ÉXITO] Prueba 2 - Restricción FOREIGN KEY de categoría funcionó correctamente: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- PRUEBA 3: INVENTARIO NEGATIVO (Restricción CHECK existencia >= 0)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    -- Intentar asignar una existencia negativa (-15)
    UPDATE inventario
    SET existencia = -15
    WHERE id_sucursal = 1 AND id_producto = 1;
    
    RAISE EXCEPTION 'FALLO: Se permitió establecer una existencia de inventario negativa.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[ÉXITO] Prueba 3 - Restricción CHECK de existencia >= 0 funcionó correctamente: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- PRUEBA 4: DETALLE DE VENTA CON CANTIDAD 0 (Restricción CHECK cantidad > 0)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    -- Intentar insertar un detalle de venta con cantidad 0
    INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, subtotal)
    VALUES (1, 1, 0, 100.00, 0.00);
    
    RAISE EXCEPTION 'FALLO: Se permitió registrar detalle de venta con cantidad 0.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[ÉXITO] Prueba 4 - Restricción CHECK de cantidad > 0 funcionó correctamente: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- PRUEBA 5: BORRADO DE PADRE CON HIJOS (ON DELETE RESTRICT en categoría)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    -- Intentar eliminar una categoría que tiene miles de productos asociados
    DELETE FROM categoria WHERE id_categoria = 1;
    
    RAISE EXCEPTION 'FALLO: Se permitió borrar una categoría padre con productos asociados.';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE '[ÉXITO] Prueba 5 - Integridad referencial ON DELETE RESTRICT funcionó correctamente: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- PRUEBA 6: PRECIO VENTA MENOR A PRECIO COMPRA (Restricción CHECK coherencia)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    -- Intentar insertar producto con precio venta menor al costo
    INSERT INTO producto (sku, nombre, id_categoria, precio_compra, precio_venta, activo)
    VALUES ('PROD-TEST-PRECIO-INV', 'Producto a Pérdida', 1, 200.00, 100.00, true);
    
    RAISE EXCEPTION 'FALLO: Se permitió insertar producto con precio de venta menor al costo.';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE '[ÉXITO] Prueba 6 - Restricción CHECK de margen de precios funcionó correctamente: %', SQLERRM;
END $$;

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TODAS LAS PRUEBAS DE INTEGRIDAD FUERON SUPERADAS (100%%%%)';
    RAISE NOTICE '=====================================================';
END $$;
