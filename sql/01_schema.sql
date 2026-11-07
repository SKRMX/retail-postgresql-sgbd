-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- BASE DE DATOS: retail_inventory_db
-- ARCHIVO: 01_schema.sql
-- DESCRIPCIÓN: Definición completa del esquema relacional (tablas, claves,
--              restricciones UNIQUE, CHECK y relaciones referenciales).
-- =============================================================================

-- Eliminar tablas si existen previamente para asegurar reproducibilidad
DROP TABLE IF EXISTS detalle_venta CASCADE;
DROP TABLE IF EXISTS venta CASCADE;
DROP TABLE IF EXISTS detalle_compra CASCADE;
DROP TABLE IF EXISTS compra CASCADE;
DROP TABLE IF EXISTS movimiento_inventario CASCADE;
DROP TABLE IF EXISTS inventario CASCADE;
DROP TABLE IF EXISTS producto_proveedor CASCADE;
DROP TABLE IF EXISTS sucursal CASCADE;
DROP TABLE IF EXISTS proveedor CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;

-- -----------------------------------------------------------------------------
-- 1. TABLA: categoria
-- -----------------------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE,
    descripcion TEXT
);

-- -----------------------------------------------------------------------------
-- 2. TABLA: producto
-- -----------------------------------------------------------------------------
CREATE TABLE producto (
    id_producto SERIAL PRIMARY KEY,
    sku VARCHAR(50) NOT NULL UNIQUE,
    nombre VARCHAR(150) NOT NULL,
    id_categoria INT NOT NULL REFERENCES categoria(id_categoria) ON DELETE RESTRICT,
    precio_compra NUMERIC(12, 2) NOT NULL CHECK (precio_compra >= 0),
    precio_venta NUMERIC(12, 2) NOT NULL CHECK (precio_venta >= 0),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT chk_producto_precios_coherentes CHECK (precio_venta >= precio_compra)
);

-- -----------------------------------------------------------------------------
-- 3. TABLA: proveedor
-- -----------------------------------------------------------------------------
CREATE TABLE proveedor (
    id_proveedor SERIAL PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL,
    telefono VARCHAR(30),
    email VARCHAR(100)
);

-- -----------------------------------------------------------------------------
-- 4. TABLA: producto_proveedor (Relación N:M)
-- -----------------------------------------------------------------------------
CREATE TABLE producto_proveedor (
    id_producto INT NOT NULL REFERENCES producto(id_producto) ON DELETE CASCADE,
    id_proveedor INT NOT NULL REFERENCES proveedor(id_proveedor) ON DELETE RESTRICT,
    costo_referencia NUMERIC(12, 2) NOT NULL CHECK (costo_referencia >= 0),
    PRIMARY KEY (id_producto, id_proveedor)
);

-- -----------------------------------------------------------------------------
-- 5. TABLA: sucursal
-- -----------------------------------------------------------------------------
CREATE TABLE sucursal (
    id_sucursal SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    direccion TEXT NOT NULL,
    activa BOOLEAN NOT NULL DEFAULT TRUE
);

-- -----------------------------------------------------------------------------
-- 6. TABLA: inventario (Existencia actual por sucursal)
-- -----------------------------------------------------------------------------
CREATE TABLE inventario (
    id_sucursal INT NOT NULL REFERENCES sucursal(id_sucursal) ON DELETE RESTRICT,
    id_producto INT NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    existencia INT NOT NULL DEFAULT 0 CHECK (existencia >= 0),
    stock_minimo INT NOT NULL DEFAULT 0 CHECK (stock_minimo >= 0),
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_sucursal, id_producto)
);

-- -----------------------------------------------------------------------------
-- 7. TABLA: movimiento_inventario (Trazabilidad histórica de inventario)
-- -----------------------------------------------------------------------------
CREATE TABLE movimiento_inventario (
    id_movimiento BIGSERIAL PRIMARY KEY,
    id_sucursal INT NOT NULL REFERENCES sucursal(id_sucursal) ON DELETE RESTRICT,
    id_producto INT NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('ENTRADA', 'SALIDA', 'AJUSTE')),
    cantidad INT NOT NULL CHECK (cantidad > 0),
    fecha TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    referencia VARCHAR(200)
);

-- -----------------------------------------------------------------------------
-- 8. TABLA: venta
-- -----------------------------------------------------------------------------
CREATE TABLE venta (
    id_venta BIGSERIAL PRIMARY KEY,
    id_sucursal INT NOT NULL REFERENCES sucursal(id_sucursal) ON DELETE RESTRICT,
    fecha TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total NUMERIC(14, 2) NOT NULL CHECK (total >= 0),
    metodo_pago VARCHAR(50) NOT NULL
);

-- -----------------------------------------------------------------------------
-- 9. TABLA: detalle_venta
-- -----------------------------------------------------------------------------
CREATE TABLE detalle_venta (
    id_detalle_venta BIGSERIAL PRIMARY KEY,
    id_venta BIGINT NOT NULL REFERENCES venta(id_venta) ON DELETE CASCADE,
    id_producto INT NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(12, 2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal NUMERIC(14, 2) NOT NULL CHECK (subtotal >= 0)
);

-- -----------------------------------------------------------------------------
-- 10. TABLA: compra
-- -----------------------------------------------------------------------------
CREATE TABLE compra (
    id_compra BIGSERIAL PRIMARY KEY,
    id_proveedor INT NOT NULL REFERENCES proveedor(id_proveedor) ON DELETE RESTRICT,
    id_sucursal INT NOT NULL REFERENCES sucursal(id_sucursal) ON DELETE RESTRICT,
    fecha TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total NUMERIC(14, 2) NOT NULL CHECK (total >= 0),
    estado VARCHAR(20) NOT NULL CHECK (estado IN ('PENDIENTE', 'RECIBIDA', 'CANCELADA'))
);

-- -----------------------------------------------------------------------------
-- 11. TABLA: detalle_compra
-- -----------------------------------------------------------------------------
CREATE TABLE detalle_compra (
    id_detalle_compra BIGSERIAL PRIMARY KEY,
    id_compra BIGINT NOT NULL REFERENCES compra(id_compra) ON DELETE CASCADE,
    id_producto INT NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    costo_unitario NUMERIC(12, 2) NOT NULL CHECK (costo_unitario >= 0),
    subtotal NUMERIC(14, 2) NOT NULL CHECK (subtotal >= 0)
);

