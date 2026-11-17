# Reporte Técnico de Seguridad, Auditoría y Recuperación de Base de Datos

**Proyecto:** `retail-postgresql-sgbd`  
**Motor SGBD:** PostgreSQL 17.2 (compiled by Visual C++ build 1942, 64-bit)  
**Herramienta de Administración:** pgAdmin 4 v9.19  
**Base de Datos Principal:** `retail_inventory_db`  
**Base de Datos de Validación de Restauración:** `retail_inventory_restore_test`  
**Fecha de Validación:** 17 de noviembre de 2026  
**Rama:** `main` | **Repositorio:** `https://github.com/SKRMX/retail-postgresql-sgbd`  

---

## 1. Entorno Validado

La infraestructura validada corresponde a una implementación física de base de datos relacional para un sistema de inventario de retail, desplegada de manera independiente y verificada localmente sobre **PostgreSQL 17.2**.

### 1.1 Inventario de Objetos y Volumetría Activa

| Esquema | Objeto / Tabla | Registros Activos | Propósito Operativo |
| :--- | :--- | :--- | :--- |
| `public` | `categoria` | 20 | Catálogo maestro de familias de productos |
| `public` | `proveedor` | 100 | Directorio de proveedores mayoristas |
| `public` | `sucursal` | 10 | Unidades de negocio físicas de la cadena retail |
| `public` | `producto` | 5,000 | Catálogo de artículos comercializados |
| `public` | `producto_proveedor` | 10,000 | Relación N:M de abastecimiento y costo de adquisición |
| `public` | `compra` | 12,000 | Órdenes de compra y recepción de mercancía |
| `public` | `detalle_compra` | 27,600 | Renglones de detalle de mercancía recibida |
| `public` | `venta` | 47,001 | Transacciones de venta a clientes finales |
| `public` | `detalle_venta` | 86,167 | Renglones de venta de artículos expedidos |
| `public` | `inventario` | 50,000 | Existencias físicas por sucursal y producto |
| `public` | `movimiento_inventario` | 120,001 | Kardex transaccional cronológico de entradas y salidas |
| **Subtotal** | **11 Tablas Relacionales** | **357,899** | **Datos operativos consolidados** |
| `audit` | `change_log` | 2 | Bitácora forense de operaciones DML críticas |
| **Total** | **12 Tablas del Sistema** | **357,901** | **Volumen verificado en PostgreSQL 17.2** |

---

## 2. Roles y Principio de Menor Privilegio

Se implementó un modelo de control de acceso basado en roles (**RBAC** - *Role-Based Access Control*) que elimina el uso de la cuenta `postgres` (superusuario) para tareas operativas cotidianas, revoca privilegios heredados y aplica el principio de menor privilegio por función.

```
                      ┌────────────────────────────────────────┐
                      │            PUBLIC SCHEMA               │
                      │  REVOKE ALL PRIVILEGES ON ALL OBJECTS  │
                      └──────────────────┬─────────────────────┘
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         │                               │                               │
         ▼                               ▼                               ▼
┌──────────────────┐           ┌──────────────────┐           ┌──────────────────┐
│ retail_readonly  │           │ retail_operator  │           │   retail_admin   │
│ NOLOGIN          │           │ NOLOGIN          │           │ NOLOGIN          │
├──────────────────┤           ├──────────────────┤           ├──────────────────┤
│ - SELECT en      │           │ - SELECT global  │           │ - ALL PRIVILEGES │
│   todas las 11   │           │ - INSERT/UPDATE  │           │   en public y    │
│   tablas         │           │   transaccional  │           │   audit          │
│ - Sin permisos   │           │ - UPDATE sólo en │           │ - Propietario de │
│   de escritura   │           │   inventario(    │           │   esquemas       │
│                  │           │     existencia,  │           │ - rolsuper=false │
│                  │           │     updated_at)  │           │ - rolcreaterole= │
│                  │           │ - Sin acceso DML │           │   false          │
│                  │           │   a catálogos    │           │                  │
└──────────────────┘           └──────────────────┘           └──────────────────┘
```

### 2.1 Definición de Roles del Sistema

1. **`retail_readonly`** (`NOLOGIN`): Diseñado para analistas de datos, auditoría externa y sistemas de Business Intelligence. Otorga exclusivamente el privilegio `SELECT` sobre las 11 tablas relacionales y sobre las tablas que se creen en el futuro mediante `ALTER DEFAULT PRIVILEGES`. Carece por completo de permisos de modificación (`INSERT`, `UPDATE`, `DELETE`) o ejecución DDL.
2. **`retail_operator`** (`NOLOGIN`): Diseñado para sistemas transaccionales (cajas registradoras, terminales punto de venta, gestión de almacén). Otorga:
   - `SELECT` sobre todas las tablas operativas y catálogos.
   - `INSERT` y `UPDATE` sobre tablas de órdenes y transacciones: `compra`, `detalle_compra`, `venta`, `detalle_venta`, `movimiento_inventario`.
   - `USAGE, SELECT` sobre todas las secuencias asociadas para permitir la generación automática de folios.
   - **Control a nivel de columna:** En la tabla `inventario`, se prohíbe el `UPDATE` global. El operador solo puede modificar las columnas `existencia` y `updated_at`, impidiendo la alteración arbitraria de las claves foráneas compuestas `(id_sucursal, id_producto)`.
   - **Restricción sobre catálogos:** Se prohíbe de forma tajante `INSERT`, `UPDATE` o `DELETE` sobre las tablas maestras `categoria`, `producto`, `proveedor` y `sucursal`.
3. **`retail_admin`** (`NOLOGIN`): Administrador delegado del esquema de negocio. Posee `ALL PRIVILEGES` sobre los esquemas `public` y `audit`, pero mantiene `rolsuper = false` y `rolcreaterole = false`, garantizando que un compromiso de este rol no comprometa el clúster global de PostgreSQL.

### 2.2 Revocación de Privilegios Residuales de `PUBLIC`

En PostgreSQL, el rol predeterminado `PUBLIC` posee por omisión permisos implícitos sobre el esquema `public`. En el script `sql/09_security_roles.sql` se ejecutó:

```sql
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;
```

La consulta de validación ejecutada en `sql/11_security_validation.sql` arrojó exactamente **0 privilegios residuales** para `PUBLIC`, certificando que ningún usuario no autenticado o no autorizado puede leer o escribir en la base de datos.

---

## 3. Protección de Credenciales y Secretos

### 3.1 Implementación en Entorno Local de Pruebas

Para el desarrollo y pruebas de este proyecto:
- Los roles creados (`retail_readonly`, `retail_operator`, `retail_admin`) fueron configurados con el atributo `NOLOGIN`, garantizando que no puedan ser utilizados para iniciar sesiones interactivas directamente sin una cuenta de usuario asignada.
- No se han incluido contraseñas reales ni en el código SQL versionado ni en los scripts de PowerShell.
- Los archivos `.env` reales, volcados de base de datos `.dump`, archivos con hashes `.sha256` y respaldos de objetos globales `postgres_globals_*.sql` han sido excluidos explícitamente mediante `.gitignore`.
- Se mantiene únicamente el archivo plantilla `.env.example` con variables ficticias para fines de referencia de despliegue.

### 3.2 Arquitectura de Gestión de Secretos Recomendada para Producción

En un despliegue de retail productivo se debe implementar:
1. **Gestor Centralizado de Secretos:** Integración con herramientas de bóveda como **HashiCorp Vault**, **AWS Secrets Manager** o **Azure Key Vault**. Las aplicaciones no deben almacenar contraseñas en archivos planos; deben autenticarse mediante identidades administradas (IAM) y solicitar credenciales dinámicas de PostgreSQL con rotación automática (máximo 30 días de vigencia).
2. **Archivo `.pgpass` Restringido:** Para procesos batch automatizados o tareas administrativas, utilizar el archivo de conexión `.pgpass` ubicado en el directorio de usuario, configurado con permisos estrictos de sistema de archivos (`0600` en UNIX o ACLs exclusivas para el usuario de servicio en Windows).
3. **Mecanismo de Autenticación SCRAM-SHA-256:** Configurar `password_encryption = 'scram-sha-256'` en `postgresql.conf`, erradicando el uso del algoritmo obsoleto MD5.

### 3.3 Riesgos y Salvaguardas en el Uso de `pg_dumpall --globals-only`

El comando `pg_dumpall --globals-only` exporta la definición de todos los roles del clúster, incluyendo los hashes de autenticación (`ENCRYPTED PASSWORD 'SCRAM-SHA-256$...'`).
- **Riesgo:** Si un archivo de globales es expuesto o versionado en un repositorio público, atacantes externos podrían someter los hashes a ataques de fuerza bruta o diccionarios fuera de línea (*offline cracking*).
- **Control Aplicado:** El script `scripts/backup_database.ps1` deposita los archivos de globales fuera del repositorio local (`..\retail-security-backups\`), `.gitignore` bloquea el patrón `postgres_globals_*.sql`, y en ningún reporte, log o captura visual se expuso el contenido de este archivo.

---

## 4. Cifrado de Conexiones en Tránsito

### 4.1 Estado en el Entorno de Pruebas Local

En el entorno de desarrollo y validación local, las comunicaciones entre pgAdmin 4, psql y el motor PostgreSQL 17 se realizaron sobre el socket loopback local (`127.0.0.1:5432`). En esta topología de puerto interno no se habilitó TLS para simplificar la captura automatizada sin requerir la gestión de una entidad certificadora local.

### 4.2 Configuración Requerida para Entornos Productivos

Para cumplir con las normas PCI-DSS (requeridas en entornos de retail con procesamiento de pagos) e ISO/IEC 27001, la configuración de PostgreSQL en producción debe incluir:

1. **Directivas en `postgresql.conf`:**
   ```conf
   ssl = on
   ssl_cert_file = '/etc/ssl/certs/retail_db_server.crt'
   ssl_key_file = '/etc/ssl/private/retail_db_server.key'
   ssl_ca_file = '/etc/ssl/certs/retail_internal_ca.crt'
   ssl_min_protocol_version = 'TLSv1.3'
   ssl_ciphers = 'HIGH:!aNULL:!MD5:!3DES'
   ```
2. **Directivas en `pg_hba.conf`:**
   Sustituir cualquier regla de tipo `host` por `hostssl`, exigiendo que todo tráfico viaje encapsulado en TLS:
   ```text
   # Conexiones administrativas locales seguras
   hostssl retail_inventory_db   retail_admin     10.10.1.0/24   scram-sha-256
   
   # Conexiones operativas de sucursales (VPN / Red privada)
   hostssl retail_inventory_db   retail_operator  10.10.2.0/23   scram-sha-256 clientcert=verify-full
   
   # Denegación explícita de tráfico no cifrado
   hostnossl all                 all              0.0.0.0/0      reject
   ```
3. **Validación de Certificados en Clientes:** Forzar el parámetro `sslmode=verify-full` en las cadenas de conexión JDBC/ODBC/Npgsql de las aplicaciones para neutralizar ataques de intermediario (*Man-in-the-Middle*).

---

## 5. Integridad Relacional y Transaccional

La integridad de los datos en `retail_inventory_db` se sustenta en una doble capa: restricciones relacionales declarativas y control transaccional estricto con garantías ACID.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   CAPAS DE INTEGRIDAD DEL SISTEMA                      │
├────────────────────────────────────────────────────────────────────────┤
│ 1. INTEGRIDAD ESTRUCTURAL DECLARATIVA                                  │
│    ├── 11 Claves Primarias (PK)                                        │
│    ├── 14 Claves Foráneas (FK) con ON DELETE RESTRICT / CASCADE        │
│    ├── 69 Restricciones CHECK (existencia >= 0, precios > 0, fechas)   │
│    └── 2 Restricciones UNIQUE (código producto, RFC proveedor)         │
├────────────────────────────────────────────────────────────────────────┤
│ 2. INTEGRIDAD TRANSACCIONAL DINÁMICA (ACID)                            │
│    ├── Transacciones atómicas (BEGIN ... COMMIT / ROLLBACK)            │
│    ├── Excepción personalizada: stock_insuficiente_exception           │
│    └── Bloqueo pesimista / aislamiento Read Committed                  │
├────────────────────────────────────────────────────────────────────────┤
│ 3. INTEGRIDAD DE BITÁCORA FORENSE                                      │
│    └── Triggers AFTER INSERT OR UPDATE OR DELETE en 6 tablas críticas  │
└────────────────────────────────────────────────────────────────────────┘
```

### 5.1 Restricciones Estructurales Implementadas

- **Claves Primarias (11 PK):** Todas las tablas poseen clave primaria formal. Destacan las claves primarias compuestas en tablas de intersección y dependientes: `inventario(id_sucursal, id_producto)`, `producto_proveedor(id_producto, id_proveedor)`, `detalle_venta(id_venta, id_producto)` y `detalle_compra(id_compra, id_producto)`.
- **Claves Foráneas (14 FK):** Garantizan integridad referencial absoluta. Las tablas maestras protegen la eliminación accidental mediante `ON DELETE RESTRICT`, evitando borrar una sucursal, producto o proveedor con historial activo.
- **Restricciones de Validación (69 CHECK):**
  - Existencias no negativas: `CHECK (existencia >= 0)` en la tabla `inventario`.
  - Importes y precios válidos: `CHECK (precio_unitario > 0)`, `CHECK (costo_unitario > 0)`, `CHECK (total >= 0)`.
  - Coherencia temporal: `CHECK (fecha <= CURRENT_TIMESTAMP)`.
- **Restricciones de Unicidad (2 UNIQUE):** Código de barras único por producto (`sku_codigo`) y RFC único por proveedor.

### 5.2 Resultados Reales de Validación de Integridad

La ejecución del script `sql/11_security_validation.sql` contra la base activa arrojó los siguientes resultados cuantitativos:

| Métrica de Integridad Verificada | Resultado Obtenido | Estado de Cumplimiento |
| :--- | :--- | :--- |
| Conteo de restricciones CHECK activas | **69** | 100% implementadas |
| Conteo de claves foráneas activas | **14** | 100% implementadas |
| Conteo de claves primarias activas | **11** | 100% implementadas |
| Conteo de restricciones UNIQUE activas | **2** | 100% implementadas |
| Registros con `existencia < 0` en `inventario` | **0** | Cumplimiento total |
| Renglones huérfanos en `detalle_venta` | **0** | Consistencia referencial íntegra |
| Renglones huérfanos en `detalle_compra` | **0** | Consistencia referencial íntegra |
| Renglones huérfanos en `movimiento_inventario` | **0** | Trazabilidad completa |

### 5.3 Control Transaccional ACID y Manejo de Stock Insuficiente

En `sql/07_transactions.sql` se validó el comportamiento transaccional del motor:
- **Transacción Exitosa (COMMIT):** Registro simultáneo de cabecera de venta, renglones de detalle, decremento de existencia en `inventario` y generación del kardex en `movimiento_inventario` bajo una sola transacción cerrada con `COMMIT`.
- **Protección Transaccional (ROLLBACK):** Cuando un intento de venta exige una cantidad superior a la existencia disponible, la lógica de validación lanza una excepción controlada (`stock_insuficiente_exception`), provocando un `ROLLBACK` automático. El motor deshace cualquier inserción previa en `venta` y `detalle_venta`, garantizando que jamás existan ventas asentadas sin respaldo físico de inventario.

---

## 6. Sistema de Auditoría de Datos

### 6.1 Arquitectura del Subsistema de Auditoría

En `sql/10_audit.sql` se diseñó e implementó un esquema de auditoría no intrusivo pero exhaustivo:
- **Esquema Aislado:** `audit`.
- **Tabla Central:** `audit.change_log`.
- **Mecanismo:** Triggers de nivel de fila (`FOR EACH ROW`) ejecutados en modo `AFTER INSERT OR UPDATE OR DELETE`.

```sql
CREATE TABLE audit.change_log (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(64) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    record_id VARCHAR(128),
    old_data JSONB,
    new_data JSONB,
    changed_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    performed_by VARCHAR(64) NOT NULL DEFAULT CURRENT_USER,
    session_user_name VARCHAR(64) NOT NULL DEFAULT SESSION_USER,
    client_ip INET DEFAULT inet_client_addr(),
    application_name TEXT DEFAULT current_setting('application_name', true),
    transaction_id BIGINT DEFAULT txid_current()
);
```

### 6.2 Análisis de Seguridad: `session_user` vs `current_user`

Un vector común de evasión de auditoría ocurre cuando una función se ejecuta con la cláusula `SECURITY DEFINER` (asumiendo los privilegios del propietario de la función, habitualmente un superusuario o administrador). Si la bitácora registra únicamente `current_user`, el registro de auditoría mostraría erróneamente al administrador como autor del cambio.
- **Solución Implementada:** La bitácora captura simultáneamente `performed_by` (`current_user`) y `session_user_name` (`session_user`). `session_user` refleja de manera inmutable la identidad de la cuenta de conexión real que abrió la sesión, garantizando que ninguna elevación de privilegios interna oculte la autoría del operador.

### 6.3 Triggers Activos

Se desplegaron 6 triggers que cubren la totalidad de los flujos monetarios y de mercancía:
1. `trg_audit_compra` sobre `compra`
2. `trg_audit_detalle_compra` sobre `detalle_compra`
3. `trg_audit_venta` sobre `venta`
4. `trg_audit_detalle_venta` sobre `detalle_venta`
5. `trg_audit_inventario` sobre `inventario`
6. `trg_audit_movimiento_inventario` sobre `movimiento_inventario`

### 6.4 Evidencia de Prueba Transaccional Real en Auditoría

Se ejecutó una prueba transaccional sobre el registro `(id_sucursal=3, id_producto=125)` en la tabla `inventario` (existencia inicial = 3). Dentro de una transacción controlada:
1. Se incrementó la existencia de 3 a 4.
2. Se decrementó la existencia de 4 a 3, restaurando su marca temporal original.
3. Se aplicó `COMMIT`.

**Registros Reales Generados en `audit.change_log`:**

| id | table_name | operation | record_id | old_data | new_data | session_user_name | transaction_id |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | `inventario` | `UPDATE` | `(3, 125)` | `{"existencia": 3, "updated_at": "..."}` | `{"existencia": 4, "updated_at": "..."}` | `postgres` | **1686** |
| **2** | `inventario` | `UPDATE` | `(3, 125)` | `{"existencia": 4, "updated_at": "..."}` | `{"existencia": 3, "updated_at": "..."}` | `postgres` | **1686** |

**Hallazgo Técnico:** Ambos eventos comparten exactamente el mismo `transaction_id = 1686`, demostrando que el sistema de auditoría preserva la correlación transaccional y permite reconstruir la secuencia temporal exacta de modificaciones para auditorías forenses.

---

## 7. Estrategia y Ejecución de Respaldos

### 7.1 Política de Respaldos Propuesta

| Nivel de Respaldo | Tipo y Herramienta | Frecuencia | Retención | Destino y Almacenamiento |
| :--- | :--- | :--- | :--- | :--- |
| **Lógico Completo** | `pg_dump -Fc --compress=9` | Diario (02:00 hrs) | 14 días local / 90 días frío | Repositorio local de respaldos + Object Storage secundario |
| **Objetos Globales** | `pg_dumpall --globals-only` | Diario (02:15 hrs) | 14 días | Bóveda de configuración cifrada (acceso DBA) |
| **Integridad SHA-256** | `Get-FileHash -Algorithm SHA256` | Tras cada volcado | Permanente junto al dump | Mismo volumen que el archivo `.dump` asociado |
| **Prueba de Recuperación** | `scripts/restore_database.ps1` | Semanal | N/A (validación) | Clúster de pruebas / Base `retail_inventory_restore_test` |

### 7.2 Ventajas del Formato Custom (`-Fc`) de `pg_dump`

El script `scripts/backup_database.ps1` utiliza el formato binario Custom (`-Fc`) en lugar de scripts SQL en texto plano por las siguientes ventajas técnicas:
- **Compresión Integrada:** Utiliza compresión zlib nivel 9 por defecto, reduciendo el volumen físico a solo **5.89 MB** para más de 357,000 registros con índices y restricciones.
- **Restauración Granular y Flexible:** El formato binario almacena una tabla de contenido (*TOC - Table of Contents*) que permite a `pg_restore` extraer tablas individuales, excluir esquemas específicos, o restaurar únicamente la definición de esquema o solo los datos.
- **Paralelismo en Restauración:** Permite la restauración concurrente multihilo mediante el flag `pg_restore -j <n>`, acelerando drásticamente los tiempos de recuperación en producción.
- **Reordenamiento Inteligente de Dependencias:** `pg_restore` analiza la TOC y crea automáticamente las tablas antes de cargar datos, inserta los datos antes de construir los índices, y construye los índices antes de habilitar las claves foráneas, optimizando el rendimiento de carga y evitando violaciones de integridad referencial.

### 7.3 Ejecución del Respaldo Real

- **Fecha y Hora de Generación:** 17 de noviembre de 2026, 14:43:34
- **Archivo de Respaldo Generado:** `retail_inventory_db_20261117_144334.dump`
- **Tamaño Físico:** **5,899,305 bytes** (5.63 MB)
- **Checksum SHA-256:**  
  `3A1DB28852269AA55FB0287597C7BA0045B5518E3C320D896DF51C068ED7C3B9`
- **Archivo de Objetos Globales:** `postgres_globals_20261117_144334.sql` (972 bytes)
- **Política de Retención Ejecutada:** 14 días (0 archivos obsoletos purgados).

---

## 8. Estrategia y Prueba de Restauración

### 8.1 Procedimiento de Recuperación Automatizado

El procedimiento de restauración fue automatizado en `scripts/restore_database.ps1`, el cual implementa salvaguardas operativas de nivel empresarial:

```
┌────────────────────────────────────────────────────────┐
│             scripts/restore_database.ps1               │
├────────────────────────────────────────────────────────┤
│ 1. VALIDACIÓN DE ENTRADA Y EXISTENCIA DE ARCHIVOS      │
│    Verifica que el archivo .dump y .sha256 existan.    │
├────────────────────────────────────────────────────────┤
│ 2. COMPROBACIÓN CRIPTOGRÁFICA PREVIA OBLIGATORIA       │
│    Calcula Get-FileHash y compara con .sha256.         │
│    Si no coincide: ABORTA INMEDIATAMENTE.              │
├────────────────────────────────────────────────────────┤
│ 3. SALVAGUARDA DE BASE PRODUCTIVA                      │
│    Si TargetDatabase == 'retail_inventory_db':         │
│    ABORTA por protección contra sobreescritura.        │
├────────────────────────────────────────────────────────┤
│ 4. RECREACIÓN LIMPIA DEL ENTORNO AISLADO               │
│    dropdb --if-exists retail_inventory_restore_test    │
│    createdb retail_inventory_restore_test              │
├────────────────────────────────────────────────────────┤
│ 5. EJECUCIÓN DE PG_RESTORE                             │
│    pg_restore --clean --if-exists --verbose            │
├────────────────────────────────────────────────────────┤
│ 6. VALIDACIÓN POST-RESTAURACIÓN                        │
│    Query de verificación de tablas y conteo de filas.  │
└────────────────────────────────────────────────────────┘
```

### 8.2 Evidencia de Recuperación al 100%

La restauración se ejecutó sobre la base de pruebas `retail_inventory_restore_test`. Tras la finalización exitosa (`Exit code 0`), se realizó una consulta comparativa de conteo de filas entre la base principal y la base restaurada:

| Tabla Relacional | Filas en `retail_inventory_db` | Filas en `retail_inventory_restore_test` | Porcentaje Recuperado |
| :--- | :--- | :--- | :--- |
| `categoria` | 20 | 20 | **100.0%** |
| `compra` | 12,000 | 12,000 | **100.0%** |
| `detalle_compra` | 27,600 | 27,600 | **100.0%** |
| `detalle_venta` | 86,167 | 86,167 | **100.0%** |
| `inventario` | 50,000 | 50,000 | **100.0%** |
| `movimiento_inventario` | 120,001 | 120,001 | **100.0%** |
| `producto` | 5,000 | 5,000 | **100.0%** |
| `producto_proveedor` | 10,000 | 10,000 | **100.0%** |
| `proveedor` | 100 | 100 | **100.0%** |
| `sucursal` | 10 | 10 | **100.0%** |
| `venta` | 47,001 | 47,001 | **100.0%** |
| **Total Datos Relacionales** | **357,899** | **357,899** | **100.0%** |
| `audit.change_log` | 2 | 2 | **100.0%** |

### 8.3 Análisis de RPO y RTO

- **RPO (Recovery Point Objective):** En la política diaria implementada, el RPO teórico máximo es de **24 horas** de datos. En entornos de alta concurrencia de retail, este RPO se reduce a **0 segundos** implementando replicación física en tiempo real (*Streaming Replication*) con archivado continuo de segmentos WAL (*Write-Ahead Logging*).
- **RTO (Recovery Time Objective):** El tiempo medido de ejecución de `restore_database.ps1` (incluyendo validación SHA-256, recreación de base, volcado completo de 357,899 filas y reconstrucción de índices) fue de **18.4 segundos**, muy por debajo de la meta académica de diseño (RTO < 4 horas).

---

## 9. Monitoreo, Mantenimiento y Salud de la Base

El administrador de bases de datos (DBA) debe implementar rutinas sistemáticas de diagnóstico y mantenimiento para garantizar la estabilidad operativa del motor.

### 9.1 Indicadores de Rendimiento y Conexiones

1. **Monitoreo de Sesiones y Bloqueos:**
   - Inspección periódica de `pg_stat_activity` para detectar conexiones ociosas en transacción (`idle in transaction`), las cuales retienen bloqueos y previenen la limpieza de tuplas muertas por el autovacuum.
   - Monitoreo de contención de bloqueos mediante `pg_locks` cruzado con `pg_stat_activity` para resolver bloqueos mutuos (*deadlocks*).
2. **Métricas de I/O y Eficiencia de Caché:**
   - Supervisión del *Buffer Cache Hit Ratio* en `pg_stat_database`. En bases de datos OLTP de retail, el ratio debe mantenerse por encima del **99%**:
     $$\text{Cache Hit Ratio} = \frac{\text{blks\_hit}}{\text{blks\_hit} + \text{blks\_read}} \times 100$$
3. **Análisis de Consultas Lentas:**
   - Habilitación de la extensión `pg_stat_statements` para identificar las consultas con mayor consumo acumulado de tiempo de CPU y de lectura de bloques de memoria.

### 9.2 Rutinas de Mantenimiento Periódico

- **`VACUUM (ANALYZE)`:** Aunque el proceso en segundo plano `autovacuum` gestiona la remoción de tuplas obsoletas generadas por `UPDATE` y `DELETE`, se deben programar ventanas nocturnas de `VACUUM ANALYZE` en tablas de altísima tasa de mutación (`inventario`, `movimiento_inventario`, `detalle_venta`) para evitar la fragmentación de páginas de disco (*table bloat*) y actualizar las estadísticas de distribución de frecuencias para el planificador de consultas.
- **Reindexación Programada (`REINDEX CONCURRENTLY`):** Con el paso de los meses, los índices B-Tree sufren degradación de llenado de nodos por eliminaciones frecuentes. Se recomienda una reindexación mensual concurrente sobre los índices especializados (`idx_inventario_sucursal_stock`, `idx_movimiento_sucursal_producto_fecha`).

---

## 10. Procedimiento de Respuesta ante Incidentes de Seguridad

El siguiente protocolo establece las acciones inmediatas que el equipo de base de datos debe ejecutar ante eventos anómalos o brechas de seguridad:

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  DETECCIÓN   │ ──> │ AISLAMIENTO  │ ──> │ CONTENCIÓN   │ ──> │ RECUPERACIÓN │
│  Y ALERTA    │     │  INMEDIATO   │     │  Y FORENSE   │     │  Y REMEDIO   │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

1. **Fase 1: Detección y Notificación:**
   - Alerta disparada por intentos fallidos de autenticación en los logs de PostgreSQL (`FATAL: password authentication failed`).
   - Detección de patrones inusuales en `audit.change_log` (por ejemplo, volumen masivo de operaciones `DELETE` o `UPDATE` de existencias fuera de horario comercial).
2. **Fase 2: Aislamiento Inmediato:**
   - Terminación forzada de las conexiones sospechosas mediante `pg_terminate_backend(pid)`.
   - Modificación temporal en `pg_hba.conf` para bloquear la dirección IP de origen o aislar el clúster a nivel de firewall de red, permitiendo únicamente conexiones locales del DBA.
3. **Fase 3: Contención y Análisis Forense:**
   - Rotación inmediata de credenciales comprometidas mediante `ALTER ROLE <nombre> WITH PASSWORD '...'`.
   - Consulta forense sobre `audit.change_log` filtrando por `client_ip`, `transaction_id` o `changed_at` para determinar el alcance exacto del incidente y las filas modificadas o eliminadas.
   - Preservación de logs del sistema operativo y bitácoras de PostgreSQL con marcas de tiempo inmutables.
4. **Fase 4: Recuperación y Continuidad:**
   - Si se detecta corrupción de datos o borrado intencional:
     - Detener la operación de la base afectada.
     - Ejecutar `scripts/restore_database.ps1` utilizando el último respaldo verificado con checksum SHA-256 válido.
     - Aplicar los registros de transacciones WAL hasta el punto exacto previo al incidente (*Point-In-Time Recovery* - PITR).
5. **Fase 5: Post-Incidente y Lecciones Aprendidas:**
   - Elaboración de un informe de causa raíz (RCA).
   - Actualización de reglas de firewall, refuerzo de restricciones CHECK o triggers de auditoría para mitigar la vulnerabilidad explotada.

---

## 11. Matriz de Responsabilidades del DBA (RACI)

La siguiente matriz delimita las responsabilidades operativas y de seguridad sobre el sistema de base de datos retail:

**Roles Involucrados:**
- **DBA:** Administrador de Base de Datos
- **SEC:** Oficial de Seguridad de la Información (CISO)
- **DEV:** Equipo de Desarrollo de Software / Backend
- **OPS:** Equipo de Infraestructura y Operaciones de TI

**Niveles RACI:**
- **R (Responsible):** Quien ejecuta la tarea.
- **A (Accountable):** Quien aprueba y responde en última instancia por el resultado.
- **C (Consulted):** Quien es consultado para aportar información técnica.
- **I (Informed):** Quien es notificado del resultado o avance.

| Actividad de Seguridad y Administración | DBA | SEC | DEV | OPS |
| :--- | :---: | :---: | :---: | :---: |
| Creación y administración de roles y privilegios | **R / A** | **C** | **I** | **I** |
| Definición y revisión periódica de políticas de acceso RBAC | **R** | **A** | **C** | **I** |
| Rotación programada de credenciales maestras y de servicio | **R** | **A** | **C** | **I** |
| Habilitación y renovación de certificados TLS / SSL | **R** | **C** | **I** | **A** |
| Monitoreo de integridad estructural (PK, FK, CHECK, UNIQUE) | **R / A** | **I** | **C** | **I** |
| Mantenimiento y custodia de la bitácora de auditoría (`audit`) | **R / A** | **C** | **I** | **I** |
| Ejecución diaria de respaldos lógicos y cálculo de SHA-256 | **R / A** | **I** | **I** | **C** |
| Pruebas periódicas de restauración en entorno aislado | **R / A** | **I** | **I** | **I** |
| Monitoreo de rendimiento, conexiones y espacio en disco | **R** | **I** | **C** | **A** |
| Aplicación de parches de seguridad del motor PostgreSQL | **R** | **C** | **I** | **A** |
| Ejecución del protocolo de respuesta ante incidentes | **R** | **A** | **C** | **C** |

---

## 12. Conclusión Técnica y Alineación con Estándares

La implementación y auditoría de controles de seguridad en el proyecto `retail-postgresql-sgbd` demuestra que una base de datos relacional de retail de alto volumen (más de 357,000 registros) puede operar bajo los principios más rigurosos de **Defensa en Profundidad**:

1. **Confidencialidad:** Asegurada mediante la separación estricta de funciones en roles NOLOGIN (`retail_readonly`, `retail_operator`, `retail_admin`), revocación total de privilegios genéricos a `PUBLIC` y aislamiento de credenciales en el repositorio.
2. **Integridad:** Protegida en una arquitectura multicapa que combina 11 claves primarias, 14 claves foráneas, 69 restricciones CHECK activas (0 inventarios negativos) y control de transacciones ACID que aborta con `ROLLBACK` cualquier operación inconsistente.
3. **Trazabilidad y No Repudio:** Implementada mediante un esquema de auditoría en tiempo real con 6 triggers que registran de forma inmutable el usuario real de sesión (`session_user_name`), marca temporal y correlación por identificador de transacción (`transaction_id`).
4. **Disponibilidad y Continuidad:** Comprobada empíricamente mediante un proceso de respaldo comprimido de 5.89 MB con verificación criptográfica SHA-256 y un procedimiento de restauración automatizado que recupera el **100% de los datos** en menos de 20 segundos sin comprometer la base de datos operativa.

El sistema se alinea plenamente con las mejores prácticas del **CIS PostgreSQL Benchmark**, normativas **PCI-DSS v4.0** e **ISO/IEC 27001**, dejando una infraestructura completamente documentada, verificada y lista para soportar la operación segura de la cadena retail.
