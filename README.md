# Bodegas del Atuel

Trabajo Práctico Integrador de Bases de Datos · Ingeniería en Sistemas · UTN FRSR · 2026

Grupo: Ezequiel Buttini, Matías Cano y Manuel Gómez.

Base de datos PostgreSQL para una red de bodegas: producción de uva, vinos, depósito central, salas de venta, clientes y ventas. Las reglas de negocio viven en la base (restricciones, triggers, funciones y procedimientos). La API y el front solo las usan.

| Parte | Tecnología | Carpeta |
|---|---|---|
| Base de datos | PostgreSQL 18 | `db/migrations/` |
| Carga de datos de prueba | Python + Faker | `db/seed/` |
| Consultas de la sección 8 | SQL | `consultas/` |
| API REST | Python + FastAPI + psycopg 3 (sin ORM) | `api/` |
| Front | HTML, CSS y JavaScript sin framework | `front/` |

## Levantar todo con Docker

Hace falta Docker Desktop.

1. Copiar `.env.example` como `.env` y cambiar las dos contraseñas (`POSTGRES_PASSWORD` y `API_DB_PASSWORD`). El `.env` no se sube al repositorio.

2. Levantar la base, la API y el front:

   ```powershell
   docker compose up -d --build
   ```

   La primera vez PostgreSQL crea la base y corre en orden todo `db/migrations/`: el esquema (001 a 008) y `009_clave_api.sh`, que le pone al rol de la API la contraseña del `.env`.

3. Cargar los datos de prueba (ver [`db/seed/README.md`](db/seed/README.md)):

   ```powershell
   python -m venv .venv
   .\.venv\Scripts\python.exe -m pip install -r db\seed\requirements.txt
   $env:PGHOST='localhost'; $env:PGPORT='5433'; $env:PGUSER='postgres'; $env:PGDATABASE='bodegas_atuel'
   $env:PGPASSWORD='la POSTGRES_PASSWORD del .env'
   .\.venv\Scripts\python.exe db\seed\cargar.py           # o --chico para pocos datos
   ```

4. Abrir:

   | Qué | Dónde |
   |---|---|
   | Front | http://localhost:8080 |
   | API (documentación Swagger) | http://localhost:8000/docs |
   | Base (DBeaver, pgAdmin) | `localhost:5433`, usuario `postgres` |

Para empezar de cero (borra los datos): `docker compose down -v` y de nuevo `docker compose up -d --build`. Las migraciones solo corren cuando el volumen está vacío, así que también hay que hacerlo después de cambiar un archivo de `db/migrations/`.

## Sin Docker (PostgreSQL instalado en Windows)

1. Crear la base y aplicar las migraciones:

   ```powershell
   $env:PGPASSWORD = 'tu contraseña de postgres'
   .\scripts\recrear_bd.ps1
   ```

2. Ponerle contraseña al rol de la API, una sola vez (los roles son del servidor y sobreviven a la recreación de la base):

   ```powershell
   & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d bodegas_atuel -c "ALTER ROLE bodegas_api PASSWORD 'otra contraseña'"
   ```

   Esa contraseña va en el `.env` como `API_DB_PASSWORD`, junto con `DB_PORT=5432`.

3. Cargar los datos como en el paso 3 de Docker, con `PGPORT=5432`.

4. Levantar la API y el front en dos terminales:

   ```powershell
   .\.venv\Scripts\python.exe -m pip install -r api\requirements.txt
   cd api
   ..\.venv\Scripts\python.exe -m uvicorn main:app --reload
   ```

   ```powershell
   python -m http.server 8080 -d front
   ```

## Pruebas

| Qué | Cómo |
|---|---|
| Reglas RN-01 a RN-15 en la base | `psql -U postgres -d bodegas_atuel -f db/tests/db_tests.sql` (corre dentro de `BEGIN … ROLLBACK`: deja la base como estaba) |
| Controles de la carga | `psql -U postgres -d bodegas_atuel -f db/seed/control.sql` |
| API (16 pruebas, 7 provocan errores de la base) | Con la API configurada en el `.env`: `cd api` y `..\.venv\Scripts\python.exe -m pytest -v` |

## Estructura

```
db/migrations/   001 esquema · 002 restricciones · 003 funciones · 004 procedimientos
                 005 triggers · 006 vistas · 007 roles · 008 índices · 009 clave de la API (Docker)
db/seed/         catálogos CSV, cargar.py y control.sql
db/tests/        db_tests.sql
consultas/       update.sql, insert.sql, delete.sql, select.sql
api/             main.py (rutas), db.py (todo el SQL), tests/
front/           index (catálogo), vino, venta, transferencias, tablero
docs/            modelo, esquema, decisiones, diccionario, trazabilidad, carga, rendimiento, API y front
```

## Documentación

| Tema | Archivo |
|---|---|
| Informe final (índice de todo) | [`docs/00_informe.md`](docs/00_informe.md) |
| Modelo conceptual y DER | [`docs/01_modelo_conceptual.md`](docs/01_modelo_conceptual.md), [`docs/der/`](docs/der/) |
| Esquema relacional y normalización | [`docs/02_esquema_relacional.md`](docs/02_esquema_relacional.md) |
| Decisiones de diseño y límites conocidos | [`docs/03_decisiones_de_diseno.md`](docs/03_decisiones_de_diseno.md) |
| Diccionario de datos | [`docs/04_diccionario_de_datos.md`](docs/04_diccionario_de_datos.md) |
| Regla → mecanismo → prueba | [`docs/trazabilidad.md`](docs/trazabilidad.md) |
| Carga masiva | [`docs/carga.md`](docs/carga.md) |
| Índices y rendimiento | [`docs/rendimiento.md`](docs/rendimiento.md) |
| API y front | [`docs/05_api_y_front.md`](docs/05_api_y_front.md) |
| Plan de trabajo | [`PLAN.md`](PLAN.md) |
