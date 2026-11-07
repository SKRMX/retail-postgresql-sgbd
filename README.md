# Retail PostgreSQL SGBD — Sistema de Inventario Retail

Proyecto independiente para la implementación física, validación de integridad referencial, benchmarking de rendimiento y optimización de consultas en **PostgreSQL 17** para un sistema de inventarios y ventas del sector retail.

---

## 1. Objetivo del Proyecto

1. Implementar físicamente en PostgreSQL un modelo relacional normalizado para un sistema de inventario retail (11 tablas con claves primarias, foráneas, restricciones de unicidad y de verificación).
2. Poblar la base de datos con un volumen representativo de datos ficticios (~358,000 registros totales) mediante expresiones deterministas reproducibles.
3. Crear índices especializados para resolver tres casos de uso analíticos críticos del negocio.
4. Validar empíricamente la efectividad de los índices mediante `EXPLAIN (ANALYZE, BUFFERS)` comparando métricas reales de ejecución, accesos a búferes y tipos de escaneo.
5. Demostrar el cumplimiento de restricciones de integridad y comportamiento transaccional ACID (`COMMIT` y `ROLLBACK`).
6. Dejar el entorno preparado para la inspección y generación de evidencia visual académica en **pgAdmin 4**.

---

## 2. Requisitos y Entorno

* **Sistema Operativo:** Windows 10/11 (o Linux/macOS)
* **Motor SGBD:** PostgreSQL 17
  * *Entorno local de pruebas:* PostgreSQL 17.2 portátil ubicado en `./pgsql/` (excluido de Git mediante `.gitignore` para no subir binarios pesados al repositorio).
  * *Entorno reproducible para terceros:* Contenedor Docker Compose con `postgres:17-alpine` y pgAdmin 4, o cualquier instalación existente de PostgreSQL 17.
* **Herramienta Visual:** pgAdmin 4 (local o mediante contenedor web)
* **Shell de Automatización:** PowerShell 7 / Windows PowerShell o Bash

---

## 3. Estructura del Proyecto

```text
retail-postgresql-sgbd/
│
├── .gitignore                      # Exclusiones de seguridad (pgsql/, data/, logs, etc.)
├── .env.example                    # Plantilla de variables de entorno ficticias para desarrollo
├── docker-compose.yml              # Despliegue reproducible con PostgreSQL 17 y pgAdmin 4
├── README.md                       # Guía completa de reconstrucción, uso y validación
│
├── evidence/
│   └── .gitkeep                    # Directorio destinado a capturas de pantalla de pgAdmin 4
│
├── pgadmin/
│   └── servers.json                # Configuración automática de conexión para pgAdmin
│
├── sql/
│   ├── 01_schema.sql               # DDL: Creación de tablas, PK, FK, UNIQUE y CHECK
│   ├── 02_seed.sql                 # DML: Carga masiva de datos (~358k filas) y ANALYZE
│   ├── 03_indexes.sql              # Índices especializados B-Tree para optimización
│   ├── 04_queries.sql              # Consultas funcionales de negocio (Casos 1, 2 y 3)
│   ├── 05_explain_analyze.sql      # Consultas con EXPLAIN (ANALYZE, BUFFERS)
│   ├── 06_validation.sql           # Auditoría: conteos, catálogo, restricciones e integridad
│   ├── 07_transactions.sql         # Demostración transaccional ACID (COMMIT y ROLLBACK)
│   └── 08_integrity_tests.sql      # Pruebas automatizadas de violación de restricciones
│
├── scripts/
│   ├── start_postgres.ps1          # Inicia la instancia local de PostgreSQL 17
│   ├── stop_postgres.ps1           # Detiene de forma segura la instancia local
│   └── run_all_and_capture.ps1     # Ejecuta toda la suite y captura resultados en texto
│
├── results/                        # Evidencia técnica de salida en texto de cada script
│   ├── 01_schema_output.txt
│   ├── 02_seed_output.txt
│   ├── baseline_before_indexes.txt
│   ├── 03_indexes_output.txt
│   ├── 04_queries_output.txt
│   ├── 05_explain_analyze_after_indexes.txt
│   ├── 06_validation_output.txt
│   ├── 07_transactions_output.txt
│   └── 08_integrity_tests_output.txt
│
└── reports/
    └── technical_report.md         # Informe técnico detallado con métricas reales
```

---

## 4. Opciones para Levantar PostgreSQL

Se proporcionan las siguientes opciones según el entorno disponible:

### Opción A: Entorno Reproducible con Docker Compose (Recomendada para terceros)
Levanta de forma automática un contenedor con PostgreSQL 17 y pgAdmin 4 sin requerir instalaciones previas en el sistema host:

1. **Iniciar los servicios:**
   ```bash
   docker compose up -d
   ```
2. **Acceder a pgAdmin 4 en el navegador:**
   * URL: `http://localhost:5050`
   * Correo: `admin@retail.local`
   * Contraseña de desarrollo: `pgadmin_dev_password_123`
3. **Credenciales de la Base de Datos:**
   * Host: `db` (o `localhost` si se conecta desde el equipo host)
   * Puerto: `5432`
   * Base de datos: `retail_inventory_db`
   * Usuario: `retail_user`
   * Contraseña de desarrollo: `retail_dev_password_123`

---

### Opción B: Entorno Local Portátil (Utilizado durante el desarrollo)
Para el desarrollo y pruebas locales se utilizó una instancia portátil oficial de PostgreSQL 17.2 ubicada en la carpeta `./pgsql/` (la cual **no está versionada en el repositorio** por buenas prácticas de tamaño):

1. **Iniciar el servidor local portátil:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\start_postgres.ps1
   ```
2. **Detener el servidor cuando sea necesario:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\stop_postgres.ps1
   ```
* **Host:** `localhost` o `127.0.0.1`
* **Puerto:** `5432`
* **Usuario:** `postgres`
* **Base de datos:** `retail_inventory_db`

---

### Opción C: Instalación Existente de PostgreSQL 17
Si ya cuentas con PostgreSQL 17 instalado en tu sistema operativo:
1. Asegúrate de que el servicio esté en ejecución en el puerto `5432`.
2. Ejecuta los scripts mediante el cliente estándar `psql`.

---

## 5. Reconstrucción de la Base y Orden de Ejecución de Scripts SQL

Para reconstruir la base de datos completa desde cero en una instancia limpia de PostgreSQL 17:

1. **Crear la base de datos:**
   ```sql
   CREATE DATABASE retail_inventory_db;
   ```
2. **Ejecutar los scripts secuencialmente mediante `psql`:**

```powershell
# 1. Crear el esquema relacional
.\pgsql\bin\psql.exe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f .\sql\01_schema.sql

# 2. Cargar datos masivos (~358,000 tuplas) y actualizar estadísticas
.\pgsql\bin\psql.exe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f .\sql\02_seed.sql

# 3. Crear índices optimizados
.\pgsql\bin\psql.exe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f .\sql\03_indexes.sql

# 4. Ejecutar consultas funcionales
.\pgsql\bin\psql.exe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f .\sql\04_queries.sql

# 5. Ejecutar análisis de planes con buffers
.\pgsql\bin\psql.exe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f .\sql\05_explain_analyze.sql

# 6. Ejecutar validación de catálogo y consistencia
.\pgsql\bin\psql.exe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f .\sql\06_validation.sql

# 7. Ejecutar demostración de transacciones (COMMIT y ROLLBACK)
.\pgsql\bin\psql.exe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f .\sql\07_transactions.sql

# 8. Ejecutar pruebas de integridad y restricciones
.\pgsql\bin\psql.exe -h 127.0.0.1 -p 5432 -U postgres -d retail_inventory_db -f .\sql\08_integrity_tests.sql
```

> **Atajo Automatizado:** Se puede ejecutar toda la cadena de scripts y captura de evidencia de manera desatendida ejecutando:
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\scripts\run_all_and_capture.ps1
> ```

---

## 6. Guía para Conexión y Captura de Evidencia en pgAdmin 4

Para generar las capturas académicas solicitadas, sigue estos pasos:

### 6.1 Conexión en pgAdmin 4
1. Abre pgAdmin 4.
2. En el panel izquierdo (*Browser*), clic derecho en **Servers** -> **Register** -> **Server...**
3. En la pestaña **General**:
   * Name: `Retail PostgreSQL Local`
4. En la pestaña **Connection**:
   * Host name/address: `127.0.0.1`
   * Port: `5432`
   * Maintenance database: `retail_inventory_db`
   * Username: `postgres`
   * Password: *(Dejar vacío o marcar Save Password si se configuró alguna)*
5. Clic en **Save**.

---

### 6.2 Dónde Obtener Cada Captura Académica

| # | Evidencia Requerida | Ruta de Navegación Exacta en pgAdmin 4 |
|---|---|---|
| **1** | **Base `retail_inventory_db`** | Árbol de navegación: `Servers` -> `Retail PostgreSQL Local` -> `Databases` -> Seleccionar `retail_inventory_db`. En el panel derecho se muestra la pestaña *Dashboard* con las estadísticas de la base. |
| **2** | **Árbol de tablas** | Desplegar: `retail_inventory_db` -> `Schemas` -> `public` -> `Tables`. Mostrar las 11 tablas del sistema (`categoria`, `compra`, `detalle_compra`, `detalle_venta`, `inventario`, `movimiento_inventario`, `producto`, `producto_proveedor`, `proveedor`, `sucursal`, `venta`). |
| **3** | **Diagrama ERD** | Clic derecho sobre `retail_inventory_db` (o sobre el esquema `public`) -> **Generate ERD** (Generar diagrama entidad-relación). El visor mostrará gráficamente todas las tablas, columnas y conectores de clave foránea. |
| **4** | **Columnas de una tabla clave** | Desplegar la tabla `producto` o `inventario` -> expandir nodo **Columns**. Se aprecian nombres, tipos de dato y restricciones NOT NULL. |
| **5** | **Restricciones** | Desplegar la tabla `producto` -> expandir nodo **Constraints**. Se visualizan `producto_pkey` (PK), `producto_sku_key` (UNIQUE), `producto_id_categoria_fkey` (FK) y `chk_producto_precios_coherentes` (CHECK). |
| **6** | **Índices** | Desplegar tabla `inventario` -> nodo **Indexes** (se aprecia `idx_inventario_stock_bajo` e `inventario_pkey`). Desplegar tabla `movimiento_inventario` -> nodo **Indexes** (se aprecia `idx_movimiento_sucursal_producto_fecha`). Desplegar tabla `venta` -> nodo **Indexes** (se aprecia `idx_venta_sucursal_fecha`). |
| **7** | **Consulta 1 + Resultado** | Abrir **Query Tool** (icono de rayo o *Tools* -> *Query Tool*). Copiar y ejecutar la Consulta 1 de `sql/04_queries.sql`. Capturar la cuadrícula inferior *Data Output* (muestra los 639 productos en stock bajo). |
| **8** | **EXPLAIN ANALYZE 1** | En el Query Tool, ejecutar la Consulta 1 precedida de `EXPLAIN (ANALYZE, BUFFERS)` o pulsar el botón **Explain Analyze** (icono de cronómetro/árbol). Seleccionar la pestaña **Explain** para ver el diagrama de bloques visual del plan o **Data Output** para ver el texto con `idx_inventario_stock_bajo`. |
| **9** | **Consulta 2 + Resultado** | Pegar la Consulta 2 de `sql/04_queries.sql` (`LIMIT 50`). Ejecutar y capturar la cuadrícula con las 50 tuplas ordenadas cronológicamente. |
| **10** | **EXPLAIN ANALYZE 2** | Ejecutar con `EXPLAIN (ANALYZE, BUFFERS)`. Se observa el `Bitmap Index Scan` sobre `idx_movimiento_sucursal_producto_fecha`, reduciendo el espacio de búsqueda de 120,000 filas a solo 150 filas, seguido de un `top-N heapsort` mínimo (32 kB) para devolver el `LIMIT 50` con solo 9 accesos a buffers compartidos y tiempo inferior a 0.1 ms. |
| **11** | **Consulta 3 + Resultado** | Pegar la Consulta 3 de `sql/04_queries.sql` (Ventas de Octubre 2026 en Sucursal 3). Ejecutar y capturar las 31 filas agrupadas por día. |
| **12** | **EXPLAIN ANALYZE 3** | Ejecutar con `EXPLAIN (ANALYZE, BUFFERS)`. Se aprecia el `Bitmap Index Scan` sobre `idx_venta_sucursal_fecha` aislando eficientemente el rango temporal de la sucursal. |

---

## 7. Verificación de Seguridad y Buenas Prácticas

* No se incluyeron contraseñas de producción ni credenciales sensibles en ningún repositorio.
* Las credenciales provistas para desarrollo en Docker Compose (`retail_user` / `retail_dev_password_123`) son estrictamente ficticias y exclusivas para entornos locales de prueba.
* Todos los datos fueron generados sintéticamente sin ninguna relación con personas, empresas o sistemas de información reales.

