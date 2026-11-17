# Seguridad de base de datos — Sistema de inventario retail

Esta carpeta documenta y automatiza las tareas de **integridad, seguridad, auditoría, respaldo y recuperación** correspondientes al proyecto `retail-postgresql-sgbd`.

## Objetivo

Complementar el modelo e implementación PostgreSQL ya desarrollados con controles propios de la administración de una base de datos:

- mínimo privilegio;
- separación de funciones;
- protección de credenciales;
- conexiones cifradas;
- integridad y consistencia transaccional;
- auditoría de operaciones críticas;
- respaldos verificables;
- restauración controlada;
- monitoreo y mantenimiento;
- respuesta ante incidentes.

## Componentes versionados

| Archivo | Propósito |
|---|---|
| `sql/09_security_roles.sql` | Roles NOLOGIN y privilegios por función |
| `sql/10_audit.sql` | Bitácora de cambios DML sobre tablas críticas |
| `sql/11_security_validation.sql` | Comprobaciones de roles, privilegios, auditoría e integridad |
| `scripts/backup_database.ps1` | Respaldo lógico con checksum SHA-256 |
| `scripts/restore_database.ps1` | Restauración segura sobre una base de prueba |
| `SECURITY.md` | Acceso rápido desde la raíz del repositorio |

## 1. Administración de usuarios y privilegios

Se definen tres roles de grupo sin inicio de sesión:

- `retail_readonly`: consulta de información.
- `retail_operator`: operación diaria de ventas, compras, movimientos y actualización controlada de existencias.
- `retail_admin`: administración del esquema sin otorgar SUPERUSER.

Los usuarios reales deben crearse fuera del repositorio y asociarse al rol correspondiente:

```sql
CREATE ROLE usuario_operacion LOGIN PASSWORD '<contraseña-segura>';
GRANT retail_operator TO usuario_operacion;
```

La contraseña anterior es únicamente un marcador. Nunca debe versionarse una credencial real.

## 2. Principio de mínimo privilegio

El script revoca privilegios genéricos de `PUBLIC` sobre tablas y secuencias y concede únicamente lo necesario a cada rol.

El rol operativo no recibe permisos para modificar catálogos maestros como categorías, productos, proveedores o sucursales.

## 3. Credenciales y autenticación

Para un entorno real se recomienda:

- `password_encryption = 'scram-sha-256'`;
- contraseñas únicas y rotación programada;
- almacenamiento mediante gestor de secretos o archivo `.pgpass` con permisos restrictivos;
- prohibición de contraseñas en scripts, código o repositorios;
- deshabilitar cuentas inactivas;
- revisar periódicamente membresías de roles.

La plantilla `.env.example` del proyecto utiliza exclusivamente valores ficticios.

## 4. Conexiones cifradas

En producción debe habilitarse TLS en PostgreSQL:

```conf
ssl = on
password_encryption = 'scram-sha-256'
```

Y en `pg_hba.conf` deben preferirse reglas `hostssl` con SCRAM:

```text
hostssl retail_inventory_db all 10.0.0.0/24 scram-sha-256
```

La red permitida debe ajustarse al entorno real. No se recomienda exponer PostgreSQL directamente a Internet.

## 5. Integridad de la información

El esquema ya implementa controles estructurales:

- claves primarias;
- claves foráneas;
- `UNIQUE`;
- `CHECK`;
- reglas `ON DELETE RESTRICT` y `CASCADE`;
- claves compuestas;
- validación de existencias no negativas.

Además, `sql/07_transactions.sql` demuestra atomicidad mediante:

- `COMMIT` de una venta válida;
- abortado por stock insuficiente;
- `ROLLBACK` ante una operación fallida.

Estas medidas reducen el riesgo de registros huérfanos, inventario negativo y ventas parcialmente aplicadas.

## 6. Auditoría

`sql/10_audit.sql` crea el esquema `audit` y una bitácora estándar PostgreSQL basada en triggers.

Se registran cambios `INSERT`, `UPDATE` y `DELETE` sobre:

- `inventario`;
- `movimiento_inventario`;
- `venta`;
- `detalle_venta`;
- `compra`;
- `detalle_compra`.

La bitácora conserva fecha/hora, usuario de sesión, usuario efectivo, aplicación cliente, dirección IP, operación, tabla, datos previos/posteriores e identificador de transacción.

El rol de operación no recibe permiso para alterar ni borrar la bitácora.

## 7. Respaldo

Política académica propuesta:

| Control | Frecuencia |
|---|---|
| Respaldo lógico de la base | Diario |
| Respaldo de roles/globales | Diario |
| Checksum SHA-256 | En cada respaldo |
| Prueba de restauración | Semanal |
| Retención local | 14 días |
| Copia externa/off-site | Al menos semanal |

El script `scripts/backup_database.ps1` genera un respaldo en formato custom de `pg_dump`, un respaldo de objetos globales mediante `pg_dumpall --globals-only` y archivos SHA-256.

La contraseña no se recibe como parámetro. Debe utilizarse autenticación interactiva, `.pgpass` o un mecanismo seguro del entorno.

## 8. Restauración y continuidad

`scripts/restore_database.ps1` restaura por defecto sobre `retail_inventory_restore_test`.

Esto permite verificar que un respaldo es utilizable sin sobrescribir la base principal.

Como objetivo académico de continuidad se propone:

- **RPO:** máximo 24 horas.
- **RTO:** máximo 4 horas.

Estos valores son metas de diseño para el ejercicio y deben ajustarse a requisitos reales del negocio.

## 9. Monitoreo y mantenimiento

El DBA debe revisar periódicamente:

- conexiones activas e intentos fallidos;
- sesiones bloqueadas y deadlocks;
- consultas lentas;
- crecimiento de tablas e índices;
- espacio disponible;
- resultados de `ANALYZE`;
- índices no utilizados o redundantes;
- logs de PostgreSQL;
- fallos de respaldo;
- errores de integridad.

También debe mantener PostgreSQL y pgAdmin actualizados dentro de versiones soportadas, aplicando parches primero en un ambiente de prueba.

## 10. Respuesta ante incidentes

Ante un incidente:

1. preservar evidencias y registros;
2. aislar el acceso afectado;
3. revocar o rotar credenciales comprometidas;
4. identificar alcance y tablas impactadas;
5. restaurar desde respaldo si existe corrupción o pérdida;
6. validar integridad y consistencia;
7. documentar causa raíz y acciones correctivas;
8. actualizar controles para evitar recurrencia.

## 11. Validación reproducible

Después de ejecutar los scripts de seguridad:

```bash
psql -U postgres -d retail_inventory_db -f sql/09_security_roles.sql
psql -U postgres -d retail_inventory_db -f sql/10_audit.sql
psql -U postgres -d retail_inventory_db -f sql/11_security_validation.sql
```

La validación debe ejecutarse en un entorno de prueba y conservar su salida como evidencia.

Para futuras pruebas de rendimiento, siguiendo la retroalimentación de la Unidad II, deben documentarse el número de ejecuciones y las condiciones de caché cuando se comparen tiempos.
