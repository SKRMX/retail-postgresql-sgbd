-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- BASE DE DATOS: retail_inventory_db
-- ARCHIVO: 06_validation.sql
-- DESCRIPCIÓN: Consultas de auditoría e introspección del catálogo para validar:
--              1. Tablas existentes en el esquema public
--              2. Conteo de registros por entidad
--              3. Restricciones (PK, FK, UNIQUE, CHECK)
--              4. Claves foráneas y reglas referenciales
--              5. Índices creados y tamaños en disco
--              6. Validación de integridad general
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. TABLAS EXISTENTES EN EL ESQUEMA PÚBLICO
-- -----------------------------------------------------------------------------
SELECT
    table_schema,
    table_name,
    table_type
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- -----------------------------------------------------------------------------
-- 2. CONTEO EXACTO DE REGISTROS POR TABLA
-- -----------------------------------------------------------------------------
SELECT 'categoria' AS tabla, COUNT(*) AS total_registros FROM categoria
UNION ALL
SELECT 'producto', COUNT(*) FROM producto
UNION ALL
SELECT 'proveedor', COUNT(*) FROM proveedor
UNION ALL
SELECT 'producto_proveedor', COUNT(*) FROM producto_proveedor
UNION ALL
SELECT 'sucursal', COUNT(*) FROM sucursal
UNION ALL
SELECT 'inventario', COUNT(*) FROM inventario
UNION ALL
SELECT 'movimiento_inventario', COUNT(*) FROM movimiento_inventario
UNION ALL
SELECT 'venta', COUNT(*) FROM venta
UNION ALL
SELECT 'detalle_venta', COUNT(*) FROM detalle_venta
UNION ALL
SELECT 'compra', COUNT(*) FROM compra
UNION ALL
SELECT 'detalle_compra', COUNT(*) FROM detalle_compra
ORDER BY total_registros DESC;

-- -----------------------------------------------------------------------------
-- 3. RESTRICCIONES (PRIMARY KEY, UNIQUE, FOREIGN KEY, CHECK)
-- -----------------------------------------------------------------------------
SELECT
    tc.table_name,
    tc.constraint_name,
    tc.constraint_type
FROM information_schema.table_constraints tc
WHERE tc.table_schema = 'public'
ORDER BY tc.table_name, tc.constraint_type, tc.constraint_name;

-- -----------------------------------------------------------------------------
-- 4. DETALLE DE CLAVES FORÁNEAS Y ACCIONES REFERENCIALES
-- -----------------------------------------------------------------------------
SELECT
    kcu.table_name AS tabla_origen,
    kcu.column_name AS columna_origen,
    ccu.table_name AS tabla_destino,
    ccu.column_name AS columna_destino,
    rc.update_rule,
    rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
JOIN information_schema.referential_constraints AS rc
    ON tc.constraint_name = rc.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
ORDER BY tabla_origen, columna_origen;

-- -----------------------------------------------------------------------------
-- 5. ÍNDICES CREADOS, DEFINICIÓN Y TAMAÑO EN DISCO
-- -----------------------------------------------------------------------------
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef,
    pg_size_pretty(pg_relation_size(indexname::regclass)) AS tamano_indice
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

-- -----------------------------------------------------------------------------
-- 6. AUDITORÍA DE INTEGRIDAD DE DATOS (VERIFICACIÓN DE HUÉRFANOS Y REGLAS)
-- Todas las consultas siguientes deben arrojar 0 registros incoherentes.
-- -----------------------------------------------------------------------------
-- A) Verificar si existen productos con categoría inexistente
SELECT COUNT(*) AS productos_huerfanos_categoria
FROM producto p
LEFT JOIN categoria c ON c.id_categoria = p.id_categoria
WHERE c.id_categoria IS NULL;

-- B) Verificar si existen existencias negativas
SELECT COUNT(*) AS inventarios_negativos
FROM inventario
WHERE existencia < 0 OR stock_minimo < 0;

-- C) Verificar si existen precios de venta menores al precio de compra
SELECT COUNT(*) AS productos_precio_invalido
FROM producto
WHERE precio_venta < precio_compra OR precio_compra < 0;

-- D) Verificar coherencia en subtotales de ventas
SELECT COUNT(*) AS detalles_venta_incoherentes
FROM detalle_venta
WHERE cantidad <= 0 OR precio_unitario < 0 OR subtotal != ROUND(cantidad * precio_unitario, 2);

-- E) Verificar coherencia entre cabecera de venta y suma de detalles
SELECT COUNT(*) AS ventas_total_descuadrado
FROM venta v
JOIN (
    SELECT id_venta, SUM(subtotal) AS suma_calculada
    FROM detalle_venta
    GROUP BY id_venta
) d ON v.id_venta = d.id_venta
WHERE v.total != d.suma_calculada;

