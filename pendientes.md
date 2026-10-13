# Pendientes

Tareas abiertas que no bloquean el avance pero hay que cerrar antes de la entrega.

## Docker: probar el esquema en un contenedor (etapa 1, paso 7)

**Responsable:** a definir (Matías o Manuel).

**Por qué:** el enunciado pide «verificar que la base se crea desde cero y sin errores en un contenedor de PostgreSQL». Hasta ahora el esquema se probó en un PostgreSQL 18 instalado en Windows, no en Docker. Además, la entrega final exige que `docker compose up` levante todo en una máquina limpia.

**Estado:** el `docker-compose.yml` del repo levanta solo la base y está **sin probar**. Puede necesitar ajustes.

### Pasos

- [ ] Instalar Docker Desktop (en Windows pide WSL 2; el instalador lo ofrece).
- [ ] Clonar el repo y, en la raíz, copiar `.env.example` como `.env` y cambiar `POSTGRES_PASSWORD` por una contraseña propia. El `.env` no se sube: ya está en el `.gitignore`.
- [ ] Levantar la base:

  ```bash
  docker compose up -d
  ```

- [ ] Ver que las migraciones corrieron sin errores:

  ```bash
  docker compose logs db
  ```

  Al arrancar con el volumen vacío, PostgreSQL ejecuta en orden alfabético todos los `.sql` de `db/migrations/`. No tiene que aparecer ningún `ERROR`.

- [ ] Verificar que están las 30 tablas:

  ```bash
  docker compose exec db psql -U postgres -d bodegas_atuel -c "\dt"
  ```

- [ ] Guardar una captura de ese resultado en `docs/capturas/` para el informe.
- [ ] Probar que se recrea desde cero (borra el volumen y vuelve a aplicar todo):

  ```bash
  docker compose down -v
  ```

  ```bash
  docker compose up -d
  ```

- [ ] Si hubo que tocar el `docker-compose.yml`, commitear el cambio con una explicación.
- [ ] Marcar esta tarea como hecha y avisar al grupo.

### Cosas a tener en cuenta

- El contenedor publica el puerto **5433** en la máquina, para no chocar con un PostgreSQL instalado en Windows (5432). Desde DBeaver o pgAdmin se conecta a `localhost:5433`.
- La imagen es `postgres:18`, la misma versión que se usa en local.
- Las migraciones solo se aplican la primera vez, cuando el volumen está vacío. Después de cambiar un `.sql` hay que hacer `docker compose down -v` para que se vuelvan a ejecutar.
- A partir de la etapa 2 habrá más archivos en `db/migrations/` (002 a 008): conviene repetir la prueba al cerrar cada etapa.
- En las etapas 6 y 7 hay que sumar la API y el front al mismo `docker-compose.yml`.
