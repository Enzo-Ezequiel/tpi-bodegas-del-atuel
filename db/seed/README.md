# Carga de datos de prueba (etapa 3)

`cargar.py` llena la base con datos simulados, reproducibles y coherentes con
las reglas del negocio. El detalle (orden de carga, triggers, volúmenes y
controles) está en [`docs/carga.md`](../../docs/carga.md).

## 1. Preparar Python (una sola vez)

En la raíz del repo, en PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r db\seed\requirements.txt
```

No hace falta «activar» el entorno: se usa el `python.exe` de adentro.

## 2. Tener la base vacía

Usá **una** de las dos opciones:

| | PostgreSQL instalado en Windows | Docker |
|---|---|---|
| Recrear la base vacía | `$env:PGPASSWORD = 'tu_contraseña'; .\scripts\recrear_bd.ps1` | `docker compose down -v` y después `docker compose up -d` |
| Puerto | 5432 | 5433 |
| Contraseña de `postgres` | La que pusiste al instalar | La de `POSTGRES_PASSWORD` en tu `.env` (copiá `.env.example` como `.env`) |

El script se niega a cargar si la base ya tiene datos («La base ya tiene datos:
recreala antes de cargar»).

## 3. Indicar la conexión

El script no tiene contraseñas en el código: lee las variables de entorno
estándar de PostgreSQL. En la misma terminal:

```powershell
$env:PGHOST = 'localhost'
$env:PGPORT = '5432'          # 5433 si usás Docker
$env:PGUSER = 'postgres'
$env:PGPASSWORD = 'tu_contraseña'
$env:PGDATABASE = 'bodegas_atuel'
```

Se conecta como `postgres` porque tiene que deshabilitar triggers, y eso solo
lo puede hacer el dueño de las tablas.

## 4. Correr la carga

```powershell
.\.venv\Scripts\python.exe db\seed\cargar.py --chico     # pocos datos, unos segundos
.\.venv\Scripts\python.exe db\seed\cargar.py             # volumen completo, menos de 1 minuto
```

Opciones:

- `--fecha-referencia AAAA-MM-DD`: el «hoy» de los datos. Por defecto, la fecha del día.
- `--medir`: no carga nada. Compara 5.000 inserciones de a una contra 5.000 con
  `executemany`, en una tabla temporal.

## 5. Qué tenés que ver si salió bien

1. La tabla «Filas cargadas y tiempo por tabla», con todas las tablas.
2. Los controles de `control.sql`: el 1 lista las filas de cada tabla y del 2 al 7
   **todos dan 0**.

Si algo falla, el script no deja nada a medias: corre en una sola transacción.

Los controles también se pueden correr solos:

```powershell
# PostgreSQL local
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d bodegas_atuel -f db\seed\control.sql
# Docker
Get-Content db\seed\control.sql | docker compose exec -T db psql -U postgres -d bodegas_atuel
```

## 6. Si algo falla

| Problema | Qué hacer |
|---|---|
| `python` no se reconoce | Instalar Python 3.12 desde python.org, marcando «Add python.exe to PATH» |
| `connection refused` | La base no está levantada o el puerto es otro: 5432 local, 5433 Docker |
| `password authentication failed` | Revisar `$env:PGPASSWORD`. En Docker es la del `.env` |
| `La base ya tiene datos` | Recrear la base (paso 2) y volver a correr |
| Un control no da 0 | No seguir: buscar con la consulta qué filas fallan y corregir el generador |
