# SECURITY — Retail PostgreSQL SGBD

La documentación académica y los controles de seguridad de este proyecto se encuentran en:

**[docs/security/README.md](docs/security/README.md)**

Incluye roles y mínimo privilegio, SCRAM/TLS, integridad, auditoría, respaldo con checksum, restauración segura, monitoreo y respuesta ante incidentes.

Scripts principales:

- `sql/09_security_roles.sql`
- `sql/10_audit.sql`
- `sql/11_security_validation.sql`
- `scripts/backup_database.ps1`
- `scripts/restore_database.ps1`

> Los scripts no contienen contraseñas reales ni secretos productivos.
