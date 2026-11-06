# Informe final — Bodegas del Atuel

TPI de Bases de Datos · Ingeniería en Sistemas · UTN FRSR · 2026
Grupo: Ezequiel Buttini, Matías Cano y Manuel Gómez.

Este informe sigue la estructura de la sección 10.2 del enunciado. Cada sección resume lo central y remite al documento con el detalle, para no repetir el mismo texto en dos lugares.

## 1. Introducción y alcance

Base de datos para la red «Bodegas del Atuel»: fincas y parcelas, cosechas, bodegas y vinos con su composición de cepas, depósito central, salas de venta, clientes de tres tipos, ventas, ingresos y transferencias de stock.

El criterio del trabajo fue el que pidió la cátedra: **que las reglas de negocio vivan en la base** y que el modelo se pueda justificar. La API y el front existen para mostrar esas reglas funcionando dentro de un sistema, no para reemplazarlas.

| Incluido | No incluido |
|---|---|
| Esquema, restricciones, funciones, procedimientos, triggers, vistas, roles e índices (`db/migrations/`) | Despliegue en la nube (etapa 8, opcional para el grupo) |
| Carga masiva reproducible y consultas de control | Constraint trigger diferido para RN-05 y bloqueos `FOR UPDATE` (temas no vistos en clase, ver sección 3) |
| Las consultas de la sección 8 | |
| API REST, front de cinco pantallas y Docker Compose | |

## 2. Modelo de datos

| Tema | Documento |
|---|---|
| Entidades, relaciones, cardinalidades y DER | [`01_modelo_conceptual.md`](01_modelo_conceptual.md) y [`der/`](der/) |
| Pasaje a tablas, dependencias funcionales y normalización (3FN, con las redundancias que se conservan a propósito) | [`02_esquema_relacional.md`](02_esquema_relacional.md) |
| Diccionario de datos | [`04_diccionario_de_datos.md`](04_diccionario_de_datos.md) |
| Decisiones de diseño y alternativas descartadas: jerarquía de clientes, claves naturales o subrogadas, tipos de datos, atributos derivados, acciones referenciales | [`03_decisiones_de_diseno.md`](03_decisiones_de_diseno.md), secciones 1 a 6 |

## 3. Integridad y lógica en la base

| Tema | Documento |
|---|---|
| Tabla regla → mecanismo → caso de prueba, para RN-01 a RN-15, y la guía «¿dónde va cada regla?» | [`trazabilidad.md`](trazabilidad.md) |
| Pruebas de cada regla (un caso que funciona y uno que falla) | [`../db/tests/db_tests.sql`](../db/tests/db_tests.sql) |
| Lo que la base no garantiza y qué haría falta | [`03_decisiones_de_diseno.md`](03_decisiones_de_diseno.md), sección 7 |

**Concurrencia.** No se implementó (transacciones es un tema que la cátedra declaró opcional). El caso está analizado como límite en `03`, sección 7: si dos personas procesan la misma transferencia al mismo tiempo, las dos leen el estado `terminado` antes de que la otra lo cambie. Se resolvería bloqueando la fila al leerla (`SELECT … FOR UPDATE`). Lo que sí está cubierto: si el segundo procesamiento deja el stock negativo, el `CHECK cantidad >= 0` lo rechaza y deshace.

## 4. Carga masiva

Catálogos reales en CSV, generador con semilla fija, orden de carga según las claves foráneas, triggers apagados solo durante la carga del historial (y por qué), tiempos por tabla, fila por fila contra por lotes, volcado y consultas de control: [`carga.md`](carga.md).

## 5. Índices y rendimiento

Cinco índices (compuesto, parcial, BRIN y dos sobre claves foráneas), mediciones con `EXPLAIN ANALYZE` antes y después, un índice descartado, el costo de escritura y un caso donde PostgreSQL no usa el índice: [`rendimiento.md`](rendimiento.md).

## 6. Consultas SQL

Las consignas de la sección 8 están en [`../consultas/`](../consultas/): `update.sql`, `insert.sql`, `delete.sql` y `select.sql`. Cada una tiene un comentario con la estrategia y el resultado con la carga completa. Los UPDATE, INSERT y DELETE corren dentro de `BEGIN … ROLLBACK` y muestran el antes y el después.

Las más interesantes para el oral:

- **S2 y S12a** (división relacional): «vendido en todas las salas» se dice al revés, con doble `NOT EXISTS`: no existe una sala donde no se haya vendido.
- **S5**: el `LEFT JOIN` con la condición en el `ON` y no en el `WHERE`, para no perder las salas sin pendientes.
- **S9**: cepas y maridajes en subconsultas, porque como `JOIN` se multiplicarían entre sí.
- **S11a**: el ranking por sala resuelto con una subconsulta correlacionada en vez de funciones de ventana (tema no visto); tarda entre 2 y 3 minutos con la carga completa.
- **U4**: intercambiar lunes y miércoles en una sola sentencia con `CASE`; con dos `UPDATE` seguidos no se puede.

## 7. API y front

Arquitectura, consultas parametrizadas, demostración de inyección SQL fallida, transacciones, traducción de errores SQLSTATE → HTTP, endpoints, pruebas automáticas y pantallas: [`05_api_y_front.md`](05_api_y_front.md).

## 8. Despliegue en la nube

No realizado. Quedó como «si da el tiempo» en el plan, porque no está dentro del mínimo que pidió la cátedra (la base se crea desde cero, la API responde y el front se conecta). Todo el sistema se levanta en local con `docker compose up -d --build`.

## 9. Conclusiones

*A completar por el grupo:* dificultades que encontramos, decisiones que cambiaríamos y qué aprendimos. Algunos temas para arrancar:

- Por qué algunas reglas no se pueden resolver con un `CHECK` (RN-05, RN-09, RN-11) y qué cuesta resolverlas con triggers.
- Los límites de la sección 7 de `03`: cuáles dejaríamos así y cuáles cerraríamos con más tiempo.
- Lo que mostraron las mediciones de índices: cuándo un índice ayuda y cuándo no.
