# Pendientes

Tareas abiertas que no bloquean el avance pero hay que cerrar antes de la entrega.

## Docker: probar el esquema en un contenedor (etapa 1, paso 7)

**Responsable:** Manuel.

**Por qué:** el enunciado pide «verificar que la base se crea desde cero y sin errores en un contenedor de PostgreSQL». Hasta ahora el esquema se probó en un PostgreSQL 18 instalado en Windows, no en Docker. Además, la entrega final exige que `docker compose up` levante todo en una máquina limpia.

**Estado:** ✅ **probado el 28/10/2026.** `docker compose up -d` crea la base desde cero con las migraciones 001 a 007 sin errores: 30 tablas, 4 vistas, 13 funciones, 2 procedimientos, 10 triggers y los 3 roles. También se recreó con `down -v` + `up -d` y dio lo mismo. No hizo falta tocar el `docker-compose.yml`. La salida está en `docs/capturas/docker_prueba.txt`.

### Pasos

- [x] Instalar Docker Desktop (en Windows pide WSL 2; el instalador lo ofrece).
- [x] Clonar el repo y, en la raíz, copiar `.env.example` como `.env` y cambiar `POSTGRES_PASSWORD` por una contraseña propia. El `.env` no se sube: ya está en el `.gitignore`.
- [x] Levantar la base:

  ```bash
  docker compose up -d
  ```

- [x] Ver que las migraciones corrieron sin errores:

  ```bash
  docker compose logs db
  ```

  Al arrancar con el volumen vacío, PostgreSQL ejecuta en orden alfabético todos los `.sql` de `db/migrations/`. No tiene que aparecer ningún `ERROR`.

- [x] Verificar que están las 30 tablas:

  ```bash
  docker compose exec db psql -U postgres -d bodegas_atuel -c "\dt"
  ```

- [x] Guardar una captura de ese resultado en `docs/capturas/` para el informe (salida en `docs/capturas/docker_prueba.txt`).
- [x] Probar que se recrea desde cero (borra el volumen y vuelve a aplicar todo):

  ```bash
  docker compose down -v
  ```

  ```bash
  docker compose up -d
  ```

- [x] Si hubo que tocar el `docker-compose.yml`, commitear el cambio con una explicación (no hizo falta).
- [x] Marcar esta tarea como hecha y avisar al grupo.

### Cosas a tener en cuenta

- El contenedor publica el puerto **5433** en la máquina, para no chocar con un PostgreSQL instalado en Windows (5432). Desde DBeaver o pgAdmin se conecta a `localhost:5433`.
- La imagen es `postgres:18`, la misma versión que se usa en local.
- Las migraciones solo se aplican la primera vez, cuando el volumen está vacío. Después de cambiar un `.sql` hay que hacer `docker compose down -v` para que se vuelvan a ejecutar.
- A partir de la etapa 2 habrá más archivos en `db/migrations/` (002 a 008): conviene repetir la prueba al cerrar cada etapa.
- En las etapas 6 y 7 hay que sumar la API y el front al mismo `docker-compose.yml`.
