-- =============================================================================
-- PROYECTO: retail-postgresql-sgbd
-- ARCHIVO: 10_audit.sql
-- OBJETIVO: Bitácora de cambios DML sobre información crítica.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.change_log (
    audit_id           BIGSERIAL PRIMARY KEY,
    recorded_at        TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    transaction_id     BIGINT NOT NULL DEFAULT txid_current(),
    session_user_name  TEXT NOT NULL DEFAULT session_user,
    effective_user     TEXT NOT NULL DEFAULT current_user,
    application_name   TEXT DEFAULT current_setting('application_name', true),
    client_address     INET DEFAULT inet_client_addr(),
    schema_name        TEXT NOT NULL,
    table_name         TEXT NOT NULL,
    operation          TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    old_data           JSONB,
    new_data           JSONB
);

CREATE INDEX IF NOT EXISTS idx_audit_change_log_recorded_at
    ON audit.change_log (recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_change_log_table_time
    ON audit.change_log (table_name, recorded_at DESC);

CREATE OR REPLACE FUNCTION audit.log_row_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, audit
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit.change_log
            (schema_name, table_name, operation, old_data, new_data)
        VALUES
            (TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, NULL, to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF to_jsonb(OLD) IS DISTINCT FROM to_jsonb(NEW) THEN
            INSERT INTO audit.change_log
                (schema_name, table_name, operation, old_data, new_data)
            VALUES
                (TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit.change_log
            (schema_name, table_name, operation, old_data, new_data)
        VALUES
            (TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, to_jsonb(OLD), NULL);
        RETURN OLD;
    END IF;
    RETURN NULL;
END
$$;

REVOKE ALL ON SCHEMA audit FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA audit FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA audit FROM PUBLIC;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'retail_admin') THEN
        GRANT USAGE ON SCHEMA audit TO retail_admin;
        GRANT SELECT ON audit.change_log TO retail_admin;
        GRANT USAGE, SELECT ON SEQUENCE audit.change_log_audit_id_seq TO retail_admin;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION audit.ensure_table_trigger(p_table REGCLASS)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_trigger_name TEXT := 'trg_audit_' || replace(p_table::TEXT, '.', '_');
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = v_trigger_name
          AND tgrelid = p_table
          AND NOT tgisinternal
    ) THEN
        EXECUTE format(
            'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %s
             FOR EACH ROW EXECUTE FUNCTION audit.log_row_change()',
            v_trigger_name,
            p_table
        );
    END IF;
END
$$;

SELECT audit.ensure_table_trigger('public.inventario');
SELECT audit.ensure_table_trigger('public.movimiento_inventario');
SELECT audit.ensure_table_trigger('public.venta');
SELECT audit.ensure_table_trigger('public.detalle_venta');
SELECT audit.ensure_table_trigger('public.compra');
SELECT audit.ensure_table_trigger('public.detalle_compra');

SELECT c.relname AS tabla, t.tgname AS trigger
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND t.tgname LIKE 'trg_audit_%'
  AND NOT t.tgisinternal
ORDER BY c.relname;
