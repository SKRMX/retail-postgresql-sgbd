-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- ARCHIVO: 09_security_roles.sql
-- OBJETIVO: Separación de funciones y mínimo privilegio mediante roles NOLOGIN.
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'retail_readonly') THEN
        CREATE ROLE retail_readonly NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'retail_operator') THEN
        CREATE ROLE retail_operator NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'retail_admin') THEN
        CREATE ROLE retail_admin NOLOGIN;
    END IF;
END
$$;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT CONNECT ON DATABASE retail_inventory_db
    TO retail_readonly, retail_operator, retail_admin;

GRANT USAGE ON SCHEMA public
    TO retail_readonly, retail_operator, retail_admin;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO retail_readonly;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO retail_operator;
GRANT INSERT, UPDATE ON venta, detalle_venta, compra, detalle_compra, movimiento_inventario
    TO retail_operator;
GRANT UPDATE (existencia, updated_at) ON inventario TO retail_operator;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO retail_operator;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO retail_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO retail_admin;

GRANT retail_readonly TO retail_operator;
GRANT retail_operator TO retail_admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO retail_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO retail_operator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO retail_operator;

SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles
WHERE rolname IN ('retail_readonly', 'retail_operator', 'retail_admin')
ORDER BY rolname;
