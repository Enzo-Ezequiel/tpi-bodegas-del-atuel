#!/bin/sh
# =============================================================================
# 009_clave_api.sh
# TPI Bases de Datos - Bodegas del Atuel
# Solo para Docker. Al crear la base, PostgreSQL ejecuta en orden los .sql y
# tambien los .sh de esta carpeta. Este le pone al rol de la API (creado sin
# contrasenia en 007_roles.sql) la contrasenia API_DB_PASSWORD del .env, asi la
# API se puede conectar sin que la contrasenia quede escrita en el repositorio.
#
# En el PostgreSQL instalado en Windows no se usa (recrear_bd.ps1 solo corre
# los .sql): ahi la contrasenia se pone a mano una vez, ver README.md.
#
# :'clave' es una variable de psql: la escribe entre comillas y escapada.
# =============================================================================
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v clave="$API_DB_PASSWORD" <<'SQL'
ALTER ROLE bodegas_api PASSWORD :'clave';
SQL
