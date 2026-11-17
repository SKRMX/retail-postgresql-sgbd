-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- ARCHIVO: 11_security_validation.sql
-- OBJETIVO: Validar controles de seguridad, auditoría e integridad.
-- =============================================================================

\echo '=== 1. ROLES DE SEGURIDAD ==='
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles
WHERE rolname IN ('retail_readonly', 'retail_operator', 'retail_admin')
ORDER BY rolname;

\echo '=== 2. PRIVILEGIOS DE PUBLIC SOBRE TABLAS ==='
SELECT table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'PUBLIC'
  AND table_schema IN ('public', 'audit')
ORDER BY table_schema, table_name, privilege_type;

\echo '=== 3. PRIVILEGIOS DE LOS ROLES DE APLICACION ==='
SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('retail_readonly', 'retail_operator', 'retail_admin')
  AND table_schema IN ('public', 'audit')
ORDER BY grantee, table_schema, table_name, privilege_type;

\echo '=== 4. TRIGGERS DE AUDITORIA ==='
SELECT n.nspname AS esquema, c.relname AS tabla, t.tgname AS trigger
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE t.tgname LIKE 'trg_audit_%'
  AND NOT t.tgisinternal
ORDER BY c.relname;

\echo '=== 5. CONTEO DE RESTRICCIONES DE INTEGRIDAD ==='
SELECT constraint_type, COUNT(*) AS total
FROM information_schema.table_constraints
WHERE table_schema = 'public'
GROUP BY constraint_type
ORDER BY constraint_type;

\echo '=== 6. CHEQUEOS IMPORTANTES ==='
SELECT conname, pg_get_constraintdef(oid) AS definicion
FROM pg_constraint
WHERE connamespace = 'public'::regnamespace
  AND contype = 'c'
ORDER BY conname;

\echo '=== 7. ULTIMOS EVENTOS DE AUDITORIA ==='
SELECT audit_id, recorded_at, session_user_name, effective_user,
       operation, table_name, transaction_id
FROM audit.change_log
ORDER BY audit_id DESC
LIMIT 20;

\echo '=== 8. INTEGRIDAD OPERATIVA: INVENTARIO NEGATIVO ==='
SELECT COUNT(*) AS inventarios_negativos
FROM inventario
WHERE existencia < 0;

\echo '=== 9. INTEGRIDAD REFERENCIAL BASICA ==='
SELECT COUNT(*) AS detalles_venta_huerfanos
FROM detalle_venta dv
LEFT JOIN venta v ON v.id_venta = dv.id_venta
WHERE v.id_venta IS NULL;

SELECT COUNT(*) AS detalles_compra_huerfanos
FROM detalle_compra dc
LEFT JOIN compra c ON c.id_compra = dc.id_compra
WHERE c.id_compra IS NULL;
