-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- BASE DE DATOS: retail_inventory_db
-- ARCHIVO: 02_seed.sql
-- DESCRIPCIÓN: Carga masiva de datos ficticios reproducibles utilizando
--              generate_series() y funciones matemáticas/aleatorias controladas.
-- =============================================================================

-- Establecer semilla para reproducibilidad matemática
SELECT setseed(0.42);

-- -----------------------------------------------------------------------------
-- 1. CARGA: categoria (20 categorías de retail)
-- -----------------------------------------------------------------------------
INSERT INTO categoria (nombre, descripcion)
VALUES
    ('Electrónica y Audio', 'Dispositivos de sonido, audífonos y accesorios multimedia'),
    ('Computación e Informática', 'Laptops, monitores, periféricos y partes de ensamble'),
    ('Telefonía y Celulares', 'Smartphones, cargadores, fundas y soportes móviles'),
    ('Hogar y Cocina', 'Electrodomésticos pequeños, cafeteras y utensilios de cocina'),
    ('Línea Blanca', 'Refrigeradores, lavadoras, secadoras y microondas'),
    ('Muebles y Decoración', 'Sillas ejecutivas, escritorios, estantes y lámparas'),
    ('Ropa para Caballero', 'Camisas, pantalones, chamarras y calzado formal y casual'),
    ('Ropa para Dama', 'Vestidos, blusas, conjuntos y calzado femenino'),
    ('Calzado Deportivo', 'Zapatillas de correr, calzado outdoor y entrenamiento'),
    ('Deportes y Fitness', 'Mancuernas, colchonetas, balones y accesorios fitness'),
    ('Salud y Cuidado Personal', 'Afeitadoras, secadoras de cabello y básculas corporales'),
    ('Belleza y Cosméticos', 'Tratamientos faciales, cremas y lociones protectoras'),
    ('Ferretería y Herramientas', 'Taladros, juegos de destornilladores y fijaciones'),
    ('Jardinería y Exteriores', 'Mangueras, podadoras, macetas y aspersores'),
    ('Juguetería y Entretenimiento', 'Juegos de mesa, figuras de acción y juguetes armables'),
    ('Videojuegos y Consolas', 'Consolas, controles inalámbricos y videojuegos'),
    ('Librería y Papelería', 'Cuadernos, agendas ejecutivas, bolígrafos y rotuladores'),
    ('Alimentos Empaquetados', 'Snacks selectos, cafés gourmet y frutos secos'),
    ('Bebidas y Refrescos', 'Agua purificada, jugos, bebidas isotónicas y energizantes'),
    ('Mascotas y Accesorios', 'Alimento balanceado, collares, correas y camas para mascotas')
ON CONFLICT (nombre) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. CARGA: sucursal (10 sucursales en ciudades clave)
-- -----------------------------------------------------------------------------
INSERT INTO sucursal (nombre, direccion, activa)
VALUES
    ('Sucursal 01 - Centro Histórico', 'Av. Central #101, Cuauhtémoc, CDMX', true),
    ('Sucursal 02 - Polanco Reforma', 'Calz. Manuel Ávila Camacho #450, Miguel Hidalgo, CDMX', true),
    ('Sucursal 03 - Insurgentes Sur', 'Av. Insurgentes Sur #1820, Benito Juárez, CDMX', true),
    ('Sucursal 04 - Santa Fe Corporativo', 'Vasco de Quiroga #3800, Cuajimalpa, CDMX', true),
    ('Sucursal 05 - Monterrey Valle', 'Calz. del Valle #250, San Pedro Garza García, NL', true),
    ('Sucursal 06 - Guadalajara Andares', 'Blvd. Puerta de Hierro #4965, Zapopan, JAL', true),
    ('Sucursal 07 - Querétaro Antea', 'Carretera San Luis Potosí #12401, Querétaro, QRO', true),
    ('Sucursal 08 - Puebla Angelópolis', 'Blvd. del Niño Poblano #2510, Puebla, PUE', true),
    ('Sucursal 09 - Mérida Altabrisa', 'Calle 7 #451, Fracc. Altabrisa, Mérida, YUC', true),
    ('Sucursal 10 - Cancún Marina', 'Blvd. Kukulcán Km 12.5, Zona Hotelera, Cancún, QROO', true);

-- -----------------------------------------------------------------------------
-- 3. CARGA: proveedor (100 proveedores mayoristas)
-- -----------------------------------------------------------------------------
INSERT INTO proveedor (nombre, telefono, email)
SELECT
    'Distribuidora Comercial ' || LPAD(i::text, 3, '0') || ' S.A. de C.V.',
    '+52 55 ' || LPAD((FLOOR(random() * 89999999) + 10000000)::bigint::text, 8, '0'),
    'contacto@proveedor' || LPAD(i::text, 3, '0') || '.com.mx'
FROM generate_series(1, 100) AS i;

-- -----------------------------------------------------------------------------
-- 4. CARGA: producto (5,000 productos)
-- -----------------------------------------------------------------------------
WITH base_prod AS (
    SELECT
        i,
        'PROD-SKU-' || LPAD(i::text, 6, '0') AS sku,
        'Producto Cat' || ((i % 20) + 1)::text || ' Modelo ' || LPAD(i::text, 5, '0') AS nombre,
        ((i % 20) + 1) AS id_categoria,
        ROUND((15.0 + (random() * 985.0))::numeric, 2) AS precio_compra,
        (random() > 0.05) AS activo -- 95% productos activos
    FROM generate_series(1, 5000) AS i
)
INSERT INTO producto (sku, nombre, id_categoria, precio_compra, precio_venta, activo)
SELECT
    sku,
    nombre,
    id_categoria,
    precio_compra,
    ROUND((precio_compra * (1.25 + (random() * 0.75)))::numeric, 2) AS precio_venta,
    activo
FROM base_prod;

-- -----------------------------------------------------------------------------
-- 5. CARGA: producto_proveedor (10,000 relaciones N:M producto-proveedor)
-- -----------------------------------------------------------------------------
-- Proveedor principal (1 por producto)
INSERT INTO producto_proveedor (id_producto, id_proveedor, costo_referencia)
SELECT
    p.id_producto,
    ((p.id_producto % 100) + 1) AS id_proveedor,
    p.precio_compra AS costo_referencia
FROM producto p;

-- Proveedor secundario alterno (1 adicional por producto)
INSERT INTO producto_proveedor (id_producto, id_proveedor, costo_referencia)
SELECT
    p.id_producto,
    (((p.id_producto + 47) % 100) + 1) AS id_proveedor,
    ROUND((p.precio_compra * (0.95 + (random() * 0.15)))::numeric, 2) AS costo_referencia
FROM producto p
ON CONFLICT (id_producto, id_proveedor) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 6. CARGA: inventario (50,000 registros: 10 sucursales * 5,000 productos)
-- -----------------------------------------------------------------------------
-- Se distribuye deliberadamente un porcentaje significativo (~12%) con stock bajo
-- (existencia <= stock_minimo) para que los filtros de optimización tengan alta selectividad
INSERT INTO inventario (id_sucursal, id_producto, existencia, stock_minimo, updated_at)
SELECT
    s.id_sucursal,
    p.id_producto,
    CASE
        -- Caso 1: Stock bajo / crítico (~12% de probabilidad)
        WHEN (p.id_producto + s.id_sucursal * 17) % 8 = 0
            THEN FLOOR(random() * 10)::int
        -- Caso 2: Stock regular / saludable (~88%)
        ELSE (20 + FLOOR(random() * 230))::int
    END AS existencia,
    -- Stock mínimo configurado entre 10 y 25 unidades
    (10 + FLOOR(random() * 15))::int AS stock_minimo,
    TIMESTAMP '2026-10-01 00:00:00' + (INTERVAL '1 day' * (random() * 35))
FROM sucursal s
CROSS JOIN producto p;

-- -----------------------------------------------------------------------------
-- 7. CARGA: movimiento_inventario (120,000 movimientos de trazabilidad histórica)
-- -----------------------------------------------------------------------------
-- A) Movimientos generales distribuidos en el año 2026
INSERT INTO movimiento_inventario (id_sucursal, id_producto, tipo, cantidad, fecha, referencia)
SELECT
    ((i % 10) + 1) AS id_sucursal,
    ((i % 5000) + 1) AS id_producto,
    CASE (i % 3)
        WHEN 0 THEN 'ENTRADA'
        WHEN 1 THEN 'SALIDA'
        ELSE 'AJUSTE'
    END AS tipo,
    (FLOOR(random() * 45) + 1)::int AS cantidad,
    TIMESTAMP '2026-01-01 08:00:00' + (INTERVAL '1 day' * (random() * 310))
                                   + (INTERVAL '1 second' * (random() * 86400)) AS fecha,
    'MOV-REF-' || LPAD(i::text, 7, '0') AS referencia
FROM generate_series(1, 119850) AS i;

-- B) Asegurar registros específicos para Sucursal 3 y Producto 125 (Consulta Optimizada 2)
-- Para evaluar eficazmente el ordenamiento, índice compuesto y LIMIT 50 dentro del año 2026
INSERT INTO movimiento_inventario (id_sucursal, id_producto, tipo, cantidad, fecha, referencia)
SELECT
    3 AS id_sucursal,
    125 AS id_producto,
    CASE (i % 3)
        WHEN 0 THEN 'ENTRADA'
        WHEN 1 THEN 'SALIDA'
        ELSE 'AJUSTE'
    END AS tipo,
    (FLOOR(random() * 20) + 1)::int AS cantidad,
    TIMESTAMP '2026-01-05 08:30:00' + (INTERVAL '1 day' * (i * 2.0))
                                   + (INTERVAL '1 second' * (random() * 3600)) AS fecha,
    'MOV-SUC3-P125-' || LPAD(i::text, 4, '0') AS referencia
FROM generate_series(1, 150) AS i;

-- -----------------------------------------------------------------------------
-- 8. CARGA: venta (45,000 transacciones de venta)
-- -----------------------------------------------------------------------------
INSERT INTO venta (id_sucursal, fecha, total, metodo_pago)
SELECT
    ((i % 10) + 1) AS id_sucursal,
    -- Generar fechas a lo largo de 2026, con fuerte presencia en octubre 2026
    TIMESTAMP '2026-01-01 09:00:00' + (INTERVAL '1 day' * (random() * 308))
                                   + (INTERVAL '1 second' * (random() * 43200)) AS fecha,
    0.00 AS total, -- Se actualizará coherentemente con sus detalles
    CASE (i % 4)
        WHEN 0 THEN 'TARJETA_CREDITO'
        WHEN 1 THEN 'TARJETA_DEBITO'
        WHEN 2 THEN 'EFECTIVO'
        ELSE 'TRANSFERENCIA'
    END AS metodo_pago
FROM generate_series(1, 45000) AS i;

-- Asegurar volumen denso de ventas para Sucursal 3 en Octubre de 2026 (Consulta Optimizada 3)
INSERT INTO venta (id_sucursal, fecha, total, metodo_pago)
SELECT
    3 AS id_sucursal,
    TIMESTAMP '2026-10-01 08:30:00' + (INTERVAL '1 day' * (i % 31))
                                   + (INTERVAL '1 second' * (random() * 40000)) AS fecha,
    0.00 AS total,
    CASE (i % 3)
        WHEN 0 THEN 'TARJETA_CREDITO'
        WHEN 1 THEN 'TARJETA_DEBITO'
        ELSE 'EFECTIVO'
    END AS metodo_pago
FROM generate_series(1, 2000) AS i;

-- -----------------------------------------------------------------------------
-- 9. CARGA: detalle_venta (~110,000 renglones de venta)
-- -----------------------------------------------------------------------------
-- Renglón 1 obligatorio por venta
WITH base_det1 AS (
    SELECT
        v.id_venta,
        ((v.id_venta % 5000) + 1) AS id_producto,
        (FLOOR(random() * 4) + 1)::int AS cantidad,
        p.precio_venta AS precio_unitario
    FROM venta v
    JOIN producto p ON p.id_producto = ((v.id_venta % 5000) + 1)
)
INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, subtotal)
SELECT
    id_venta,
    id_producto,
    cantidad,
    precio_unitario,
    ROUND((cantidad * precio_unitario)::numeric, 2) AS subtotal
FROM base_det1;

-- Renglón 2 para ventas pares (~23,500 renglones)
WITH base_det2 AS (
    SELECT
        v.id_venta,
        (((v.id_venta + 137) % 5000) + 1) AS id_producto,
        (FLOOR(random() * 3) + 1)::int AS cantidad,
        p.precio_venta AS precio_unitario
    FROM venta v
    JOIN producto p ON p.id_producto = (((v.id_venta + 137) % 5000) + 1)
    WHERE v.id_venta % 2 = 0
)
INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, subtotal)
SELECT
    id_venta,
    id_producto,
    cantidad,
    precio_unitario,
    ROUND((cantidad * precio_unitario)::numeric, 2) AS subtotal
FROM base_det2;

-- Renglón 3 para ventas divisibles por 3 (~15,600 renglones)
WITH base_det3 AS (
    SELECT
        v.id_venta,
        (((v.id_venta + 893) % 5000) + 1) AS id_producto,
        (FLOOR(random() * 2) + 1)::int AS cantidad,
        p.precio_venta AS precio_unitario
    FROM venta v
    JOIN producto p ON p.id_producto = (((v.id_venta + 893) % 5000) + 1)
    WHERE v.id_venta % 3 = 0
)
INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, subtotal)
SELECT
    id_venta,
    id_producto,
    cantidad,
    precio_unitario,
    ROUND((cantidad * precio_unitario)::numeric, 2) AS subtotal
FROM base_det3;

-- Actualizar el total de cada venta con la suma exacta de sus subtotales
WITH totales AS (
    SELECT id_venta, SUM(subtotal) AS suma_total
    FROM detalle_venta
    GROUP BY id_venta
)
UPDATE venta v
SET total = t.suma_total
FROM totales t
WHERE v.id_venta = t.id_venta;

-- -----------------------------------------------------------------------------
-- 10. CARGA: compra (12,000 órdenes de compra a proveedores)
-- -----------------------------------------------------------------------------
INSERT INTO compra (id_proveedor, id_sucursal, fecha, total, estado)
SELECT
    ((i % 100) + 1) AS id_proveedor,
    ((i % 10) + 1) AS id_sucursal,
    TIMESTAMP '2026-01-01 07:30:00' + (INTERVAL '1 day' * (random() * 305)) AS fecha,
    0.00 AS total,
    CASE (i % 10)
        WHEN 0 THEN 'CANCELADA'
        WHEN 1 THEN 'PENDIENTE'
        ELSE 'RECIBIDA'
    END AS estado
FROM generate_series(1, 12000) AS i;

-- -----------------------------------------------------------------------------
-- 11. CARGA: detalle_compra (~30,000 renglones de compra)
-- -----------------------------------------------------------------------------
-- Renglón 1 por orden de compra
WITH base_comp1 AS (
    SELECT
        c.id_compra,
        ((c.id_compra % 5000) + 1) AS id_producto,
        (FLOOR(random() * 25) + 10)::int AS cantidad,
        p.precio_compra AS costo_unitario
    FROM compra c
    JOIN producto p ON p.id_producto = ((c.id_compra % 5000) + 1)
)
INSERT INTO detalle_compra (id_compra, id_producto, cantidad, costo_unitario, subtotal)
SELECT
    id_compra,
    id_producto,
    cantidad,
    costo_unitario,
    ROUND((cantidad * costo_unitario)::numeric, 2) AS subtotal
FROM base_comp1;

-- Renglón 2 para el 80% de compras
WITH base_comp2 AS (
    SELECT
        c.id_compra,
        (((c.id_compra + 333) % 5000) + 1) AS id_producto,
        (FLOOR(random() * 20) + 5)::int AS cantidad,
        p.precio_compra AS costo_unitario
    FROM compra c
    JOIN producto p ON p.id_producto = (((c.id_compra + 333) % 5000) + 1)
    WHERE c.id_compra % 5 != 0
)
INSERT INTO detalle_compra (id_compra, id_producto, cantidad, costo_unitario, subtotal)
SELECT
    id_compra,
    id_producto,
    cantidad,
    costo_unitario,
    ROUND((cantidad * costo_unitario)::numeric, 2) AS subtotal
FROM base_comp2;

-- Renglón 3 para el 50% de compras
WITH base_comp3 AS (
    SELECT
        c.id_compra,
        (((c.id_compra + 777) % 5000) + 1) AS id_producto,
        (FLOOR(random() * 15) + 5)::int AS cantidad,
        p.precio_compra AS costo_unitario
    FROM compra c
    JOIN producto p ON p.id_producto = (((c.id_compra + 777) % 5000) + 1)
    WHERE c.id_compra % 2 = 0
)
INSERT INTO detalle_compra (id_compra, id_producto, cantidad, costo_unitario, subtotal)
SELECT
    id_compra,
    id_producto,
    cantidad,
    costo_unitario,
    ROUND((cantidad * costo_unitario)::numeric, 2) AS subtotal
FROM base_comp3;

-- Actualizar el total de compra con la suma de sus detalles
WITH totales_compra AS (
    SELECT id_compra, SUM(subtotal) AS suma_total
    FROM detalle_compra
    GROUP BY id_compra
)
UPDATE compra c
SET total = tc.suma_total
FROM totales_compra tc
WHERE c.id_compra = tc.id_compra;

-- -----------------------------------------------------------------------------
-- ACTUALIZACIÓN DE ESTADÍSTICAS DEL PLANIFICADOR
-- -----------------------------------------------------------------------------
ANALYZE;
