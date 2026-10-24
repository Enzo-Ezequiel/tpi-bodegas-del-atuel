-- =============================================================================
-- 007_roles.sql
-- TPI Bases de Datos - Bodegas del Atuel
-- Roles y permisos con el principio de menor privilegio: cada rol tiene
-- exactamente los permisos que necesita para su tarea, ni mas ni menos.
--
--   bodegas_admin     todos los permisos: administra la base
--   bodegas_api       lee y escribe datos y ejecuta funciones y procedimientos;
--                     no crea ni borra tablas. Es con el que se conecta la API.
--   bodegas_reportes  solo lectura, para consultas y reportes
--
-- El duenio tecnico de las tablas es el usuario que corre las migraciones
-- (postgres en local). La API nunca se conecta con ese usuario.
--
-- Las contrasenias NO van en el repositorio. Los roles se crean sin
-- contrasenia y se les pone una a mano una sola vez, por ejemplo:
--     ALTER ROLE bodegas_api PASSWORD '...';
-- y esa contrasenia va en el archivo .env, que no se sube.
--
-- Esta migracion se corre despues de crear todas las tablas, vistas y
-- funciones, porque los GRANT ... ON ALL solo alcanzan a lo que ya existe.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Crear los roles
-- Los roles son del servidor, no de la base: si se borra y se vuelve a crear
-- la base (scripts/recrear_bd.ps1), los roles siguen existiendo. Por eso se
-- crean solo si no existen; un CREATE ROLE comun daria error la segunda vez.
-- DO ejecuta un bloque de codigo como el de una funcion, sin guardarlo.
-- -----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodegas_admin') THEN
        CREATE ROLE bodegas_admin WITH LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodegas_api') THEN
        CREATE ROLE bodegas_api WITH LOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bodegas_reportes') THEN
        CREATE ROLE bodegas_reportes WITH LOGIN;
    END IF;
END
$$;

-- -----------------------------------------------------------------------------
-- Quitar los permisos que PostgreSQL le da por defecto a cualquier usuario
-- (PUBLIC): conectarse a la base, usar el esquema y ejecutar funciones.
-- Despues se otorgan solo a los roles que los necesitan.
-- -----------------------------------------------------------------------------
REVOKE ALL ON DATABASE bodegas_atuel FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA public FROM PUBLIC;

-- Los tres pueden conectarse a la base y ver lo que hay en el esquema
GRANT CONNECT ON DATABASE bodegas_atuel TO bodegas_admin, bodegas_api, bodegas_reportes;
GRANT USAGE ON SCHEMA public TO bodegas_admin, bodegas_api, bodegas_reportes;

-- -----------------------------------------------------------------------------
-- bodegas_admin: todos los permisos sobre todos los objetos, y crear objetos
-- nuevos en el esquema
-- -----------------------------------------------------------------------------
GRANT CREATE ON SCHEMA public TO bodegas_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO bodegas_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO bodegas_admin;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO bodegas_admin;

-- -----------------------------------------------------------------------------
-- bodegas_api: leer y escribir datos, y llamar a funciones y procedimientos.
-- No recibe CREATE ni ALL PRIVILEGES: no puede crear, modificar ni borrar
-- tablas. Las secuencias son las que generan los codigos autonumericos.
-- -----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO bodegas_api;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO bodegas_api;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO bodegas_api;

-- RN-13: la auditoria de precios solo se agrega (lo hace el trigger T6), nunca
-- se corrige ni se borra. Aunque alguien tome el control de la API, no puede
-- borrar el historial de precios.
REVOKE UPDATE, DELETE ON auditoria_precio FROM bodegas_api;

-- -----------------------------------------------------------------------------
-- bodegas_reportes: solo lectura. "ALL TABLES" incluye las vistas.
-- Puede ejecutar funciones (por ejemplo fn_stock_sala en una consulta), pero
-- no procedimientos, que son los que modifican datos.
-- -----------------------------------------------------------------------------
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bodegas_reportes;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bodegas_reportes;
