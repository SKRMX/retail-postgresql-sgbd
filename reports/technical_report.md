# Reporte Técnico de Implementación, Benchmarking y Optimización en PostgreSQL 17
## Sistema de Gestión de Inventario para Retail (`retail-postgresql-sgbd`)

---

### 1. Resumen Ejecutivo y Entorno de Ejecución

Este informe documenta la implementación física, validación de integridad referencial, benchmarking de rendimiento y optimización de consultas del modelo relacional para el sistema de inventario retail en una base de datos PostgreSQL independiente.

* **Motor de Base de Datos:** PostgreSQL 17.2 (x86_64-windows, compilado por MSVC 19.41.34123, 64-bit).
* **Entornos de Despliegue:**
  * *Entorno local de desarrollo y benchmarking:* Binarios portátiles oficiales de PostgreSQL 17.2 en espacio de usuario (`./pgsql/`), excluidos de Git por buenas prácticas de tamaño.
  * *Entorno reproducible para terceros:* Orquestación en contenedores mediante Docker Compose (`postgres:17-alpine` + `pgadmin4`), con persistencia de volúmenes y montaje directo de los scripts DDL/DML.
* **Base de Datos Implementada:** `retail_inventory_db`.
* **Esquema:** Relacional normalizado en Tercera Forma Normal (3FN), nombres en `snake_case`, claves foráneas con reglas de acción referencial (`ON DELETE RESTRICT` / `CASCADE`) y restricciones `CHECK`.
* **Periodo de Datos:** Todas las transacciones, compras y movimientos de inventario se encuentran estrictamente acotados dentro del año **2026**.

---

### 2. Estructura y Volumen Real de Datos Cargados

Se ejecutó la carga masiva mediante funciones generadoras deterministas reproducibles (`generate_series()`, `setseed(0.42)`, `make_interval()`) garantizando una selectividad realista y representativa:

| # | Nombre de la Tabla | Conteo Real de Filas | Propósito y Relaciones |
|---|-------------------|---------------------:|-------------------------|
| 1 | `categoria` | 20 | Familias de artículos del sector retail. |
| 2 | `sucursal` | 10 | Puntos de venta físicos en ciudades principales. |
| 3 | `proveedor` | 100 | Proveedores comerciales mayoristas. |
| 4 | `producto` | 5,000 | Catálogo maestro de SKUs con precios de compra y venta (`precio_venta >= precio_compra`). |
| 5 | `producto_proveedor` | 10,000 | Tabla puente N:M (asociando 2 proveedores por producto). |
| 6 | `inventario` | 50,000 | Existencia y stock mínimo por cada combinación sucursal-producto ($10 \times 5,000$). |
| 7 | `movimiento_inventario` | 120,001 | Histórico de trazabilidad (`ENTRADA`, `SALIDA`, `AJUSTE`) entre enero y noviembre de 2026. |
| 8 | `venta` | 47,001 | Transacciones comerciales registradas en sucursales a lo largo de 2026. |
| 9 | `detalle_venta` | 86,167 | Renglones de venta con coherencia estricta en cantidad, precio unitario y subtotal. |
| 10 | `compra` | 12,000 | Órdenes de abastecimiento emitidas a proveedores durante 2026. |
| 11 | `detalle_compra` | 27,600 | Renglones de compra por producto y costo unitario. |
| **TOTAL** | **Volumen Global** | **357,899 registros** | Base de datos con volumen suficiente para evaluación realista de planes. |

#### Rango Temporal Verificado en `movimiento_inventario`:
* **Fecha mínima general:** `2026-01-01 09:01:04`
* **Fecha máxima general:** `2026-11-08 07:13:22`
* **Movimientos específicos Sucursal 3 + Producto 125:** 150 registros comprendidos entre `2026-01-07 09:28:00` y `2026-11-01 09:15:54`.

---

### 3. Catálogo de Índices Implementados

| Tabla | Nombre del Índice | Tipo / Método | Columnas Indexadas / Condición | Tamaño en Disco |
|---|---|---|---|---|
| `inventario` | `idx_inventario_stock_bajo` | B-Tree (Parcial) | `(id_sucursal, id_producto) WHERE existencia <= stock_minimo` | **160 kB** |
| `inventario` | `inventario_pkey` | B-Tree (Único) | `(id_sucursal, id_producto)` | 1,136 kB |
| `movimiento_inventario` | `idx_movimiento_sucursal_producto_fecha` | B-Tree (Compuesto) | `(id_sucursal, id_producto, fecha DESC)` | **3,720 kB** |
| `movimiento_inventario` | `movimiento_inventario_pkey` | B-Tree (Único) | `(id_movimiento)` | 2,640 kB |
| `venta` | `idx_venta_sucursal_fecha` | B-Tree (Compuesto) | `(id_sucursal, fecha DESC)` | **1,464 kB** |
| `venta` | `venta_pkey` | B-Tree (Único) | `(id_venta)` | 2,072 kB |
| `producto` | `producto_sku_key` | B-Tree (Único) | `(sku)` | 176 kB |
| `producto` | `producto_pkey` | B-Tree (Único) | `(id_producto)` | 128 kB |
| `producto_proveedor` | `producto_proveedor_pkey` | B-Tree (Único) | `(id_producto, id_proveedor)` | 344 kB |
| `detalle_venta` | `detalle_venta_pkey` | B-Tree (Único) | `(id_detalle_venta)` | 1,904 kB |
| `compra` | `compra_pkey` | B-Tree (Único) | `(id_compra)` | 552 kB |
| `detalle_compra` | `detalle_compra_pkey` | B-Tree (Único) | `(id_detalle_compra)` | 624 kB |
| `categoria` | `categoria_nombre_key` | B-Tree (Único) | `(nombre)` | 16 kB |
| `categoria` | `categoria_pkey` | B-Tree (Único) | `(id_categoria)` | 16 kB |
| `sucursal` | `sucursal_pkey` | B-Tree (Único) | `(id_sucursal)` | 16 kB |
| `proveedor` | `proveedor_pkey` | B-Tree (Único) | `(id_proveedor)` | 16 kB |

---

### 4. Análisis Detallado de Consultas Optimizadas y Planes de Ejecución

---

#### 4.1 Consulta 1 — Detección de Stock Bajo por Sucursal

**Objetivo:** Identificar oportunamente artículos cuyo nivel de existencia sea igual o inferior al stock mínimo en la Sucursal 3 (`Insurgentes Sur`), ordenados alfabéticamente por nombre de producto.

**Sentencia SQL:**
```sql
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
```

**Resultado Funcional:**
* **Filas retornadas:** 639 productos con stock crítico en Sucursal 3.

**Plan de Ejecución Real (`EXPLAIN (ANALYZE, BUFFERS)`):**
```text
Sort  (cost=615.81..619.97 rows=1661 width=51) (actual time=1.807..1.825 rows=639 loops=1)
  Sort Key: p.nombre
  Sort Method: quicksort  Memory: 69kB
  Buffers: shared hit=388
  ->  Hash Join  (cost=401.83..526.97 rows=1661 width=51) (actual time=0.932..1.599 rows=639 loops=1)
        Hash Cond: (p.id_producto = i.id_producto)
        Buffers: shared hit=385
        ->  Seq Scan on producto p  (cost=0.00..112.00 rows=5000 width=47) (actual time=0.009..0.342 rows=5000 loops=1)
              Buffers: shared hit=62
        ->  Hash  (cost=381.07..381.07 rows=1661 width=12) (actual time=0.913..0.913 rows=639 loops=1)
              Buckets: 2048  Batches: 1  Memory Usage: 44kB
              Buffers: shared hit=323
              ->  Bitmap Heap Scan on inventario i  (cost=37.16..381.07 rows=1661 width=12) (actual time=0.080..0.854 rows=639 loops=1)
                    Recheck Cond: ((id_sucursal = 3) AND (existencia <= stock_minimo))
                    Heap Blocks: exact=319
                    Buffers: shared hit=323
                    ->  Bitmap Index Scan on idx_inventario_stock_bajo  (cost=0.00..36.74 rows=1661 width=0) (actual time=0.048..0.048 rows=639 loops=1)
                          Index Cond: (id_sucursal = 3)
                          Buffers: shared hit=4
Planning:
  Buffers: shared hit=237
Planning Time: 2.757 ms
Execution Time: 1.900 ms
```

**Métricas y Análisis Técnico:**
* **Planning Time:** 2.757 ms
* **Execution Time:** **1.900 ms** (frente a 2.366 ms sin el índice, una reducción del **19.7%** en tiempo de ejecución).
* **Buffers Compartidos Procesados:** 388 bloques encontrados en la memoria caché compartida (`shared hit`).
* **Estrategia de Acceso:** `Bitmap Index Scan` sobre el índice parcial `idx_inventario_stock_bajo`.
* **Justificación de Optimización:** En el plan sin índice especializado, el motor utilizaba la clave primaria `inventario_pkey`, debiendo examinar los 5,000 registros de la sucursal y descartar **4,361 filas en el Heap** mediante evaluación posfiltro. Con el índice parcial, la búsqueda en el árbol B-Tree consume únicamente **4 buffers compartidos**, localizando directamente las tuplas críticas y descartando 0 filas por filtro en la tabla.

---

#### 4.2 Consulta 2 — Historial Cronológico de Movimientos por Producto

**Objetivo:** Auditar los últimos 50 movimientos registrados en el kardex para el Producto 125 en la Sucursal 3, ordenados de forma descendente por fecha.

**Sentencia SQL:**
```sql
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
```

**Resultado Funcional:**
* **Filas retornadas:** 50 filas (de un total de 150 movimientos históricos asociados a ese producto y sucursal dentro de 2026).
* Muestra cronológica:
  * `2026-11-01 09:15:54` | `ENTRADA` | 15 | `MOV-SUC3-P125-0150`
  * `2026-10-30 08:52:05` | `AJUSTE`  | 15 | `MOV-SUC3-P125-0149`
  * `2026-10-28 08:43:58` | `SALIDA`  | 5  | `MOV-SUC3-P125-0148`

**Plan de Ejecución Real (`EXPLAIN (ANALYZE, BUFFERS)`):**
```text
Limit  (cost=77.73..77.78 rows=20 width=35) (actual time=0.082..0.086 rows=50 loops=1)
  Buffers: shared hit=9
  ->  Sort  (cost=77.73..77.78 rows=20 width=35) (actual time=0.082..0.083 rows=50 loops=1)
        Sort Key: fecha DESC
        Sort Method: top-N heapsort  Memory: 32kB
        Buffers: shared hit=9
        ->  Bitmap Heap Scan on movimiento_inventario  (cost=4.62..77.30 rows=20 width=35) (actual time=0.032..0.050 rows=150 loops=1)
              Recheck Cond: ((id_sucursal = 3) AND (id_producto = 125))
              Heap Blocks: exact=3
              Buffers: shared hit=6
              ->  Bitmap Index Scan on idx_movimiento_sucursal_producto_fecha  (cost=0.00..4.62 rows=20 width=0) (actual time=0.019..0.019 rows=150 loops=1)
                    Index Cond: ((id_sucursal = 3) AND (id_producto = 125))
                    Buffers: shared hit=3
Planning:
  Buffers: shared hit=83
Planning Time: 1.214 ms
Execution Time: 0.097 ms
```

**Métricas y Análisis Técnico del Plan:**
* **Planning Time:** 1.214 ms
* **Execution Time:** **0.097 ms** (frente a 7.423 ms sin el índice, alcanzando un factor de aceleración de **76.5x** y una reducción del tiempo de ejecución del **98.7%**).
* **Buffers Compartidos Procesados:** **9 buffers** encontrados en caché compartida (`shared hit`), frente a 1,241 buffers del escaneo secuencial (una reducción del **99.27%** en bloques procesados por el plan).
* **Estrategia de Acceso y Explicación del Ordenamiento:**
  * El planificador **no eliminó el paso de ordenamiento (`Sort`)**, sino que seleccionó una combinación sumamente eficiente: `Bitmap Index Scan` sobre `idx_movimiento_sucursal_producto_fecha` $\rightarrow$ `Bitmap Heap Scan` $\rightarrow$ `Sort (top-N heapsort)` $\rightarrow$ `Limit`.
  * El índice reduce de forma inmediata el universo candidato de **120,000 registros a únicamente 150 registros** correspondientes al par `id_sucursal = 3 AND id_producto = 125` contenidos en solo 3 bloques físicos de tabla (`Heap Blocks: exact=3`).
  * Con este subconjunto diminuto de 150 tuplas, el optimizador determina que ejecutar un ordenamiento en memoria mediante `top-N heapsort` (utilizando apenas 32 kB de memoria de trabajo) tiene un costo insignificante (costo total de 77.78 frente a 3,038.32 inicial).
  * La presencia de `fecha DESC` en la definición del índice lo hace conceptualmente apto para este patrón de ordenamiento, logrando que la consulta culmine en menos de 0.1 milisegundos.

---

#### 4.3 Consulta 3 — Ventas por Sucursal en Periodo Temporal (Octubre 2026)

**Objetivo:** Consolidar el volumen de transacciones y facturación diaria en la Sucursal 3 durante el mes de Octubre de 2026 agrupado día por día.

**Sentencia SQL:**
```sql
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
```

**Resultado Funcional:**
* **Filas retornadas:** 31 registros (uno por cada día de Octubre de 2026).
* Facturación diaria promedio: entre \$237,000 y \$292,000 MXN por día (75 a 85 transacciones diarias).

**Plan de Ejecución Real (`EXPLAIN (ANALYZE, BUFFERS)`):**
```text
GroupAggregate  (cost=976.72..998.87 rows=886 width=44) (actual time=1.356..1.640 rows=31 loops=1)
  Group Key: (date(fecha))
  Buffers: shared hit=308
  ->  Sort  (cost=976.72..978.93 rows=886 width=10) (actual time=1.330..1.398 rows=2432 loops=1)
        Sort Key: (date(fecha))
        Sort Method: quicksort  Memory: 173kB
        Buffers: shared hit=308
        ->  Bitmap Heap Scan on venta  (cost=27.59..933.34 rows=886 width=10) (actual time=0.147..1.108 rows=2432 loops=1)
              Recheck Cond: ((id_sucursal = 3) AND (fecha >= '2026-10-01 00:00:00'::timestamp without time zone) AND (fecha < '2026-11-01 00:00:00'::timestamp without time zone))
              Heap Blocks: exact=293
              Buffers: shared hit=305
              ->  Bitmap Index Scan on idx_venta_sucursal_fecha  (cost=0.00..27.37 rows=886 width=0) (actual time=0.116..0.116 rows=2432 loops=1)
                    Index Cond: ((id_sucursal = 3) AND (fecha >= '2026-10-01 00:00:00'::timestamp without time zone) AND (fecha < '2026-11-01 00:00:00'::timestamp without time zone))
                    Buffers: shared hit=12
Planning:
  Buffers: shared hit=71
Planning Time: 1.211 ms
Execution Time: 1.686 ms
```

**Métricas y Análisis Técnico:**
* **Planning Time:** 1.211 ms
* **Execution Time:** **1.686 ms** (frente a 5.887 ms sin el índice, un factor de aceleración de **3.49x** y una reducción del tiempo de ejecución del **71.4%**).
* **Buffers Compartidos Procesados:** **308 buffers** en caché compartida (`shared hit`), frente a 858 buffers del escaneo secuencial (una reducción del **64.1%** en bloques procesados por el plan).
* **Justificación de Optimización:** El índice compuesto `(id_sucursal, fecha DESC)` permite un escaneo de índice por rango (*Range Scan*) acotado por la clave de sucursal y el intervalo de fechas. Lee solo 12 bloques del índice para identificar exactamente las 2,432 ventas del periodo, descartando a priori el 95% restante de transacciones de la tabla sin necesidad de leer sus registros.

---

### 5. Comparativa Integral de Rendimiento (Antes vs. Después)

| Métrica Técnica | Consulta 1 (Stock Bajo) - Antes | Consulta 1 (Stock Bajo) - Después | Consulta 2 (Kardex Movimientos) - Antes | Consulta 2 (Kardex Movimientos) - Después | Consulta 3 (Ventas Periodo) - Antes | Consulta 3 (Ventas Periodo) - Después |
|---|---|---|---|---|---|---|
| **Estrategia de Acceso** | Bitmap Scan (`pkey`) | **Bitmap Scan (`idx_parcial`)** | **Seq Scan (Tabla completa)** | **Bitmap Index Scan** | **Seq Scan (Tabla completa)** | **Bitmap Index Scan** |
| **Índice Utilizado** | `inventario_pkey` | `idx_inventario_stock_bajo` | *Ninguno (Full Scan)* | `idx_movimiento_sucursal_producto_fecha` | *Ninguno (Full Scan)* | `idx_venta_sucursal_fecha` |
| **Filas Inspeccionadas** | 5,000 en PK | **639 directas** | 120,000 filas | **150 directas** | 47,000 filas | **2,432 directas** |
| **Filas Descartadas (Filter)** | 4,361 descartadas | **0 descartadas** | 119,850 descartadas | **0 descartadas** | 44,568 descartadas | **0 descartadas** |
| **Accesos a Buffers (shared hit)** | 399 bloques | **388 bloques** | 1,241 bloques | **9 bloques** | 858 bloques | **308 bloques** |
| **Reducción de Buffers Procesados** | — | **-2.8%** | — | **-99.27%** | — | **-64.10%** |
| **Costo Total Estimado** | 737.44 | **619.97** | 3,038.36 | **77.78** | 1,746.08 | **998.87** |
| **Planning Time** | 2.509 ms | 2.757 ms | 0.964 ms | 1.214 ms | 0.868 ms | 1.211 ms |
| **Execution Time** | 2.366 ms | **1.900 ms** | 7.423 ms | **0.097 ms** | 5.887 ms | **1.686 ms** |
| **Factor de Aceleración** | — | **1.25x** | — | **76.5x** | — | **3.49x** |
| **Reducción de Tiempo de Ejecución** | — | **19.7%** | — | **98.7%** | — | **71.4%** |

*(Nota técnica: Todas las métricas de búferes corresponden a `shared hit`, es decir, bloques leídos directamente desde la memoria caché compartida de PostgreSQL (`shared_buffers`), sin registrar lecturas físicas de disco `shared read` debido al precalentamiento adecuado de la memoria intermedia).*

---

### 6. Validación de Integridad Referencial y Restricciones

Se ejecutaron pruebas automatizadas controladas en `sql/08_integrity_tests.sql`, comprobando que PostgreSQL lance la excepción correspondiente ante intentos de violar las reglas del modelo:

| Prueba | Operación Intentada | Restricción Involucrada | Código / Excepción PostgreSQL | Resultado |
|---|---|---|---|---|
| **1. SKU Duplicado** | Insertar producto con SKU existente `PROD-SKU-000001` | UNIQUE (`producto_sku_key`) | `23505 (unique_violation)`: *duplicate key value violates unique constraint "producto_sku_key"* | **RECHAZADO (OK)** |
| **2. Categoría Inválida** | Insertar producto con `id_categoria = 99999` | FOREIGN KEY (`producto_id_categoria_fkey`) | `23503 (foreign_key_violation)`: *insert or update on table "producto" violates foreign key constraint* | **RECHAZADO (OK)** |
| **3. Inventario Negativo** | Actualizar `existencia = -15` | CHECK (`inventario_existencia_check`) | `23514 (check_violation)`: *new row for relation "inventario" violates check constraint "inventario_existencia_check"* | **RECHAZADO (OK)** |
| **4. Detalle Venta Cantidad 0** | Insertar renglón con `cantidad = 0` | CHECK (`detalle_venta_cantidad_check`) | `23514 (check_violation)`: *new row for relation "detalle_venta" violates check constraint "detalle_venta_cantidad_check"* | **RECHAZADO (OK)** |
| **5. Borrado con Dependencias** | Eliminar categoría 1 con productos activos | ON DELETE RESTRICT | `23503 (foreign_key_violation)`: *update or delete on table "categoria" violates foreign key constraint on table "producto"* | **RECHAZADO (OK)** |
| **6. Margen Negativo** | Insertar producto con precio de venta ($100) < costo ($200) | CHECK (`chk_producto_precios_coherentes`) | `23514 (check_violation)`: *new row for relation "producto" violates check constraint "chk_producto_precios_coherentes"* | **RECHAZADO (OK)** |

---

### 7. Comportamiento Transaccional ACID

Se implementó y verificó la seguridad transaccional en `sql/07_transactions.sql` con captura directa de identificadores y control estricto de concurrencia:

#### Caso 1: Transacción Exitosa (`COMMIT`)
* **Mecanismo:** Bloque PL/pgSQL transaccional seguro contra concurrencia.
  * Captura de clave generada: `INSERT INTO venta (...) RETURNING id_venta INTO v_id_venta;`
  * Todas las operaciones posteriores (`detalle_venta`, `inventario`, `movimiento_inventario`) utilizan exclusivamente `v_id_venta`.
  * **No se utiliza `MAX(id_venta)`**, evitando condiciones de carrera (*race conditions*).
  * Validación de stock: `UPDATE inventario ... WHERE ... AND existencia >= 2;`
  * Verificación: `GET DIAGNOSTICS v_filas_actualizadas = ROW_COUNT; IF v_filas_actualizadas = 0 THEN RAISE EXCEPTION ...; END IF;`
* **Resultado:** Stock inicial del Producto 10 en Sucursal 1: **200 unidades**. Stock final comprobado: **198 unidades**. Movimiento de `SALIDA` insertado con referencia unívoca `VENTA-EXITOSA-47001`.

#### Caso 2: Transacción Abortada por Regla de Negocio (Stock Insuficiente)
* **Escenario:** Intento de venta de 50,000 unidades del Producto 10 (disponibilidad actual: 198).
* **Mecanismo:** El `UPDATE inventario` con filtro `existencia >= 50000` afecta 0 filas. El bloque detecta `v_filas_actualizadas = 0` y dispara:
  ```text
  RAISE EXCEPTION 'Stock insuficiente para vender 50000 unidades del Producto 10'
  ```
* **Resultado:** La transacción se revierte de forma automática (`ROLLBACK`). El stock permanece inalterado en **198 unidades** y no se genera ningún movimiento de salida ni tupla huérfana en `venta`.

#### Caso 3: Transacción Abortada Manualmente (`ROLLBACK`)
* **Escenario:** Fallo simulado en terminal bancaria tras registrar una venta con método `TARJETA_RECHAZADA`.
* **Resultado:** Conteo de ventas previo: **47,001**. Conteo posterior al `ROLLBACK`: **47,001**. Total de ventas con método rechazado: **0 tuplas**. Consistencia total en el estado de la base de datos.
