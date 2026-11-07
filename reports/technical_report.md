# Reporte Técnico de Implementación y Optimización en PostgreSQL 17
## Sistema de Gestión de Inventario para Retail (`retail-postgresql-sgbd`)

---

### 1. Resumen Ejecutivo y Entorno de Ejecución

Este informe documenta la implementación física, validación de integridad referencial, benchmarking y optimización de consultas del modelo relacional para el sistema de inventario retail en una base de datos PostgreSQL independiente.

* **Motor de Base de Datos:** PostgreSQL 17.2 (x86_64-windows, compilado por MSVC 19.41.34123, 64-bit)
* **Entorno de Despliegue:** Binarios portátiles independientes de PostgreSQL 17 en espacio de usuario (`./pgsql/bin/`) y orquestación reproducible complementaria en contenedor mediante Docker Compose (`postgres:17-alpine` + `pgadmin4`).
* **Base de Datos Implementada:** `retail_inventory_db`
* **Esquema:** Relacional normalizado en Tercera Forma Normal (3FN), nombres en `snake_case`, restricciones de dominio y reglas de integridad referencial activas.
* **Fecha y Hora de Auditoría:** Noviembre 2026.

---

### 2. Estructura y Volumen Real de Datos Cargados

Se ejecutó la carga masiva mediante funciones generadoras matemáticas deterministas (`generate_series()`, `setseed(0.42)`, `make_interval()`) garantizando selectividad realista sin sesgos de muestreo trivial.

| # | Nombre de la Tabla | Conteo Real de Filas | Propósito y Relaciones |
|---|-------------------|---------------------:|-------------------------|
| 1 | `categoria` | 20 | Catálogo de familias de productos del sector retail. |
| 2 | `sucursal` | 10 | Puntos de venta físicos en ciudades principales. |
| 3 | `proveedor` | 100 | Proveedores comerciales mayoristas. |
| 4 | `producto` | 5,000 | Catálogo maestro de SKUs con precios de compra y venta. |
| 5 | `producto_proveedor` | 10,000 | Tabla puente N:M asociando 2 proveedores por producto. |
| 6 | `inventario` | 50,000 | Existencia y stock mínimo por cada combinación sucursal-producto. |
| 7 | `movimiento_inventario` | 120,000 | Trazabilidad histórica (ENTRADA, SALIDA, AJUSTE). |
| 8 | `venta` | 47,002 | Transacciones comerciales en sucursales a lo largo de 2026. |
| 9 | `detalle_venta` | 86,167 | Renglones de venta con coherencia estricta cantidad/subtotal. |
| 10 | `compra` | 12,000 | Órdenes de abastecimiento emitidas a proveedores. |
| 11 | `detalle_compra` | 27,600 | Renglones de compra por producto y costo unitario. |
| **TOTAL** | **Volumen Global** | **357,899 registros** | Base robusta para validación de índices y planes de ejecución. |

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

**Objetivo:** Identificar oportunamente artículos cuyo nivel de existencia sea igual o inferior al stock mínimo en la Sucursal 3 (`Insurgentes Sur`), ordenados alfabéticamente por nombre.

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

**Resultado Funcional Resumido:**
* **Filas retornadas:** 639 productos con stock bajo en Sucursal 3.
* **Ejemplo de filas:**
  * `PROD-SKU-000029` | `Producto Cat10 Modelo 00029` | existencia: 9 | stock_minimo: 23
  * `PROD-SKU-000069` | `Producto Cat10 Modelo 00069` | existencia: 3 | stock_minimo: 10
  * `PROD-SKU-000269` | `Producto Cat10 Modelo 00269` | existencia: 0 | stock_minimo: 18

**Plan de Ejecución Real (`EXPLAIN (ANALYZE, BUFFERS)`):**
```text
Sort  (cost=615.33..619.47 rows=1656 width=51) (actual time=2.165..2.183 rows=639 loops=1)
  Sort Key: p.nombre
  Sort Method: quicksort  Memory: 69kB
  Buffers: shared hit=388
  ->  Hash Join  (cost=401.66..526.79 rows=1656 width=51) (actual time=1.159..1.803 rows=639 loops=1)
        Hash Cond: (p.id_producto = i.id_producto)
        Buffers: shared hit=385
        ->  Seq Scan on producto p  (cost=0.00..112.00 rows=5000 width=47) (actual time=0.010..0.333 rows=5000 loops=1)
              Buffers: shared hit=62
        ->  Hash  (cost=380.96..380.96 rows=1656 width=12) (actual time=0.979..0.979 rows=639 loops=1)
              Buckets: 2048  Batches: 1  Memory Usage: 44kB
              Buffers: shared hit=323
              ->  Bitmap Heap Scan on inventario i  (cost=37.12..380.96 rows=1656 width=12) (actual time=0.081..0.916 rows=639 loops=1)
                    Recheck Cond: ((id_sucursal = 3) AND (existencia <= stock_minimo))
                    Heap Blocks: exact=319
                    Buffers: shared hit=323
                    ->  Bitmap Index Scan on idx_inventario_stock_bajo  (cost=0.00..36.70 rows=1656 width=0) (actual time=0.051..0.051 rows=639 loops=1)
                          Index Cond: (id_sucursal = 3)
                          Buffers: shared hit=4
Planning:
  Buffers: shared hit=237
Planning Time: 3.016 ms
Execution Time: 2.265 ms
```

**Métricas Clave:**
* **Planning Time:** 3.016 ms
* **Execution Time:** 2.265 ms
* **Costo Estimado:** `615.33..619.47` (reducido respecto a 731.60 previo al índice)
* **Buffers Totales:** 388 shared hit
* **Tipo de Scan:** `Bitmap Index Scan` sobre `idx_inventario_stock_bajo` seguido de `Bitmap Heap Scan`.
* **Uso del Índice:** Sí, utiliza `idx_inventario_stock_bajo`. Nótese que para escanear el índice solo necesitó **4 buffers de memoria**, descartando a nivel de índice el 87% de productos que no tenían stock bajo sin siquiera leerlos de disco o memoria intermedia.

---

#### 4.2 Consulta 2 — Historial Cronológico de Movimientos por Producto

**Objetivo:** Obtener los últimos 50 movimientos registrados de inventario para un artículo específico (`id_producto = 125`) en la Sucursal 3, ordenados de forma descendente por fecha.

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

**Resultado Funcional Resumido:**
* **Filas retornadas:** 50 filas (de un total de 150 movimientos históricos asociados a ese par sucursal-producto).
* **Muestra de resultados:**
  * `2027-01-12 09:45:54` | `ENTRADA` | 15 | `MOV-SUC3-P125-0150`
  * `2027-01-10 21:22:05` | `AJUSTE`  | 15 | `MOV-SUC3-P125-0149`
  * `2027-01-09 09:13:58` | `SALIDA`  | 5  | `MOV-SUC3-P125-0148`

**Plan de Ejecución Real (`EXPLAIN (ANALYZE, BUFFERS)`):**
```text
Limit  (cost=81.20..81.26 rows=21 width=35) (actual time=0.082..0.086 rows=50 loops=1)
  Buffers: shared hit=9
  ->  Sort  (cost=81.20..81.26 rows=21 width=35) (actual time=0.082..0.083 rows=50 loops=1)
        Sort Key: fecha DESC
        Sort Method: top-N heapsort  Memory: 32kB
        Buffers: shared hit=9
        ->  Bitmap Heap Scan on movimiento_inventario  (cost=4.63..80.74 rows=21 width=35) (actual time=0.029..0.048 rows=150 loops=1)
              Recheck Cond: ((id_sucursal = 3) AND (id_producto = 125))
              Heap Blocks: exact=3
              Buffers: shared hit=6
              ->  Bitmap Index Scan on idx_movimiento_sucursal_producto_fecha  (cost=0.00..4.63 rows=21 width=0) (actual time=0.015..0.015 rows=150 loops=1)
                    Index Cond: ((id_sucursal = 3) AND (id_producto = 125))
                    Buffers: shared hit=3
Planning:
  Buffers: shared hit=82
Planning Time: 1.460 ms
Execution Time: 0.099 ms
```

**Métricas Clave:**
* **Planning Time:** 1.460 ms
* **Execution Time:** **0.099 ms**
* **Costo Estimado:** `81.20..81.26`
* **Buffers Totales:** **9 shared hit** (3 en índice, 6 en heap)
* **Tipo de Scan:** `Bitmap Index Scan` sobre `idx_movimiento_sucursal_producto_fecha` + `top-N heapsort` con `LIMIT 50`.
* **Uso del Índice:** Sí, el índice compuesto `(id_sucursal, id_producto, fecha DESC)` permite ubicar inmediatamente los 150 registros exactos pertenecientes a dicha combinación en solo 3 bloques de datos (`Heap Blocks: exact=3`), evitando examinar los restantes 119,850 registros de la tabla.

---

#### 4.3 Consulta 3 — Ventas por Sucursal en Periodo Temporal (Octubre 2026)

**Objetivo:** Consolidar el volumen de transacciones y facturación diaria en la Sucursal 3 durante el mes de Octubre de 2026.

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

**Resultado Funcional Resumido:**
* **Filas retornadas:** 31 registros (uno por cada día de Octubre de 2026).
* **Muestra de resultados:**
  * `2026-10-01` | 77 ventas | Total: $256,694.06
  * `2026-10-02` | 83 ventas | Total: $272,797.15
  * `2026-10-03` | 83 ventas | Total: $292,871.54
  * `...`
  * `2026-10-31` | 76 ventas | Total: $264,812.30

**Plan de Ejecución Real (`EXPLAIN (ANALYZE, BUFFERS)`):**
```text
GroupAggregate  (cost=981.42..1004.14 rows=909 width=44) (actual time=1.236..1.523 rows=31 loops=1)
  Group Key: (date(fecha))
  Buffers: shared hit=308
  ->  Sort  (cost=981.42..983.69 rows=909 width=10) (actual time=1.210..1.276 rows=2432 loops=1)
        Sort Key: (date(fecha))
        Sort Method: quicksort  Memory: 173kB
        Buffers: shared hit=308
        ->  Bitmap Heap Scan on venta  (cost=27.88..936.75 rows=909 width=10) (actual time=0.161..0.981 rows=2432 loops=1)
              Recheck Cond: ((id_sucursal = 3) AND (fecha >= '2026-10-01 00:00:00'::timestamp without time zone) AND (fecha < '2026-11-01 00:00:00'::timestamp without time zone))
              Heap Blocks: exact=293
              Buffers: shared hit=305
              ->  Bitmap Index Scan on idx_venta_sucursal_fecha  (cost=0.00..27.65 rows=909 width=0) (actual time=0.132..0.132 rows=2432 loops=1)
                    Index Cond: ((id_sucursal = 3) AND (fecha >= '2026-10-01 00:00:00'::timestamp without time zone) AND (fecha < '2026-11-01 00:00:00'::timestamp without time zone))
                    Buffers: shared hit=12
Planning:
  Buffers: shared hit=70
Planning Time: 1.208 ms
Execution Time: 1.571 ms
```

**Métricas Clave:**
* **Planning Time:** 1.208 ms
* **Execution Time:** 1.571 ms
* **Costo Estimado:** `981.42..1004.14` (reducido respecto a 1,747.84 inicial)
* **Buffers Totales:** 308 shared hit (reducido desde 858)
* **Tipo de Scan:** `Bitmap Index Scan` sobre `idx_venta_sucursal_fecha` + `Bitmap Heap Scan` + `GroupAggregate`.
* **Uso del Índice:** Sí, el índice compuesto `(id_sucursal, fecha DESC)` aísla el rango temporal de la sucursal 3, leyendo únicamente 12 buffers del índice para identificar los 2,432 registros correspondientes.

---

### 5. Comparativa Exhaustiva de Rendimiento (Antes vs. Después)

A continuación se presenta la comparativa formal con métricas reales obtenidas directamente de PostgreSQL en la misma máquina y con el mismo conjunto de datos (sin alterar parámetros del planificador):

#### Comparación Integral: Las 3 Consultas

| Métrica de Rendimiento | Consulta 1 (Stock Bajo) - Antes | Consulta 1 (Stock Bajo) - Después | Consulta 2 (Movimientos) - Antes | Consulta 2 (Movimientos) - Después | Consulta 3 (Ventas Mes) - Antes | Consulta 3 (Ventas Mes) - Después |
|---|---|---|---|---|---|---|
| **Estrategia de Acceso** | Bitmap Scan (`pkey`) | **Bitmap Scan (`idx_parcial`)** | **Seq Scan (Tabla completa)** | **Bitmap Index Scan** | **Seq Scan (Tabla completa)** | **Bitmap Index Scan** |
| **Índice Utilizado** | `inventario_pkey` | `idx_inventario_stock_bajo` | *Ninguno (Full Scan)* | `idx_movimiento_sucursal_producto_fecha` | *Ninguno (Full Scan)* | `idx_venta_sucursal_fecha` |
| **Filas Inspeccionadas** | 5,000 en PK | **639 directas** | 120,000 filas | **150 directas** | 47,000 filas | **2,432 directas** |
| **Filas Descartadas (Filter)** | 4,361 descartadas | **0 descartadas** | 119,850 descartadas | **0 descartadas** | 44,568 descartadas | **0 descartadas** |
| **Buffers de Memoria (Hit)** | 399 | **388** | 1,241 | **9 (-99.27%)** | 858 | **308 (-64.10%)** |
| **Costo del Plan (Total)** | 731.60 | **619.47** | 3,038.42 | **81.26 (-97.3%)** | 1,747.84 | **1,004.14 (-42.5%)** |
| **Planning Time** | 3.172 ms | 3.016 ms | 0.987 ms | 1.460 ms | 1.011 ms | 1.208 ms |
| **Execution Time** | 2.552 ms | **2.265 ms** | 8.351 ms | **0.099 ms (84x más rápida)** | 5.849 ms | **1.571 ms (3.7x más rápida)** |

#### Profundización en Consulta 2 (Movimientos de Inventario)
La Consulta 2 representa el caso más drástico de optimización:
1. **Antes del índice:** PostgreSQL se veía obligado a ejecutar un `Seq Scan` recorriendo los 120,000 registros históricos de movimientos, consumiendo 1,241 buffers de memoria y descartando 119,850 filas por filtro para retener 150 y luego ordenarlas con heapsort. Tiempo: **8.351 ms**.
2. **Con el índice compuesto:** El índice `(id_sucursal, id_producto, fecha DESC)` permitió filtrar en una única operación de árbol B-Tree tanto la sucursal como el producto. Solo se leyeron 3 bloques de índice y 3 bloques de tabla (9 buffers totales), extrayendo directamente las filas deseadas. Tiempo: **0.099 ms**, alcanzando una ganancia de velocidad de **8,400%**.

---

### 6. Validación de Integridad Referencial y Restricciones

Se ejecutaron pruebas controladas intentando forzar violaciones a las reglas del modelo. Todas fueron rechazadas por PostgreSQL:

| Prueba | Operación Intentada | Restricción Involucrada | Código / Excepción PostgreSQL | Resultado |
|---|---|---|---|---|
| **1. SKU Duplicado** | Insertar producto con SKU existente `PROD-SKU-000001` | UNIQUE (`producto_sku_key`) | `23505 (unique_violation)`: *duplicate key value violates unique constraint "producto_sku_key"* | **RECHAZADO (OK)** |
| **2. Categoría Inválida** | Insertar producto con `id_categoria = 99999` | FOREIGN KEY (`producto_id_categoria_fkey`) | `23503 (foreign_key_violation)`: *insert or update on table "producto" violates foreign key constraint* | **RECHAZADO (OK)** |
| **3. Inventario Negativo** | Actualizar `existencia = -15` | CHECK (`inventario_existencia_check`) | `23514 (check_violation)`: *new row for relation "inventario" violates check constraint "inventario_existencia_check"* | **RECHAZADO (OK)** |
| **4. Detalle Venta Cantidad 0** | Insertar renglón con `cantidad = 0` | CHECK (`detalle_venta_cantidad_check`) | `23514 (check_violation)`: *new row for relation "detalle_venta" violates check constraint "detalle_venta_cantidad_check"* | **RECHAZADO (OK)** |
| **5. Borrado con Dependencias** | Eliminar categoría 1 con productos activos | ON DELETE RESTRICT | `23503 (foreign_key_violation)`: *update or delete on table "categoria" violates foreign key constraint on table "producto"* | **RECHAZADO (OK)** |
| **6. Margen Negativo** | Insertar producto con precio de venta ($100) < costo ($200) | CHECK (`chk_producto_precios_coherentes`) | `23514 (check_violation)`: *new row for relation "producto" violates check constraint "chk_producto_precios_coherentes"* | **RECHAZADO (OK)** |

---

### 7. Prueba Transaccional ACID (COMMIT y ROLLBACK)

Se validó el soporte ACID transaccional mediante dos casos de prueba:

#### Caso A: Transacción Exitosa (`COMMIT`)
* **Flujo:** Venta en Sucursal 1 del Producto 10 por 2 unidades.
  * Stock inicial verificado: **200 unidades**.
  * `BEGIN;`
  * Registro de venta en cabecera `venta` (`id_venta = 47001` / `47026`).
  * Registro en `detalle_venta` (2 unidades x precio de venta).
  * Actualización del total de la venta calculado por sumatoria.
  * Descuento atómico en `inventario` (`existencia = existencia - 2`).
  * Registro en `movimiento_inventario` tipo `SALIDA` con referencia transaccional.
  * `COMMIT;`
* **Resultado:** Stock final verificado: **198 unidades**. La integridad y persistencia de todos los cambios fueron garantizadas de forma atómica.

#### Caso B: Transacción Abortada (`ROLLBACK`)
* **Flujo:** Simulación de fallo (rechazo de pago con tarjeta).
  * Conteo de ventas previo: **47,002 ventas**.
  * `BEGIN;`
  * Intento de registro en `venta` con método `TARJETA_RECHAZADA`.
  * Inserción tentativa en `detalle_venta`.
  * Intento de descuento en inventario.
  * Evento de error simulado -> Emisión de `ROLLBACK;`.
* **Resultado:** Conteo de ventas posterior: **47,002 ventas**. Búsqueda de registros con método `TARJETA_RECHAZADA`: **0 filas encontradas**. El estado de la base de datos permaneció completamente inalterado.

---

### 8. Incidencias Técnicas Registradas y Soluciones Aplicadas

1. **Aislamiento de sockets en sandbox Windows:**
   * *Incidencia:* La conexión por red local (`127.0.0.1:5432`) desde procesos de consola independientes al servidor requería privilegios fuera del sandbox de red.
   * *Solución:* Se ejecutó el servidor como proceso daemon y se configuraron las conexiones en modo local transparente con autenticación `trust` para entorno de desarrollo controlado.
2. **Colisión de descriptores en registro de logs (`server.log`):**
   * *Incidencia:* El uso del flag `-l` de `pg_ctl` en Windows provocó un error de violación de recursos compartidos (`sharing violation`) debido al bloqueo de archivos del sistema operativo.
   * *Solución:* Se activó el recolector nativo en `postgresql.conf` (`logging_collector = on`, `log_directory = 'log'`), desacoplando el subproceso del motor de cualquier bloqueo de consola.
3. **Cálculo de intervalos temporales en generación sintética:**
   * *Incidencia:* La concatenación de cadenas `((random() * 35) || ' days')::interval` generó en casos de flotantes muy pequeños notación científica (`2.48e-05 days`), rechazada por el parser de PostgreSQL.
   * *Solución:* Se migró a multiplicación de escalares de intervalos: `(INTERVAL '1 day' * (random() * 35))`, la cual es nativa, tipada y matemáticamente exacta.
4. **Coherencia matemática en subtotales de prueba:**
   * *Incidencia:* La evaluación reiterada de `random()` en la misma sentencia generó discrepancias entre la cantidad guardada y el subtotal calculado.
   * *Solución:* Se refactorizó la carga de renglones de venta y compra mediante CTEs (`WITH base_det AS (...)`), garantizando que la cantidad se evaluara una única vez por renglón y el subtotal fuera `cantidad * precio_unitario`.

