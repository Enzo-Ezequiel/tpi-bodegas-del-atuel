# Etapa 4 — Índices y rendimiento

Índices en [`db/migrations/008_indices.sql`](../db/migrations/008_indices.sql). PostgreSQL 18 en Docker, carga completa de la etapa 3 (50.000 comprobantes y 125.135 renglones).

## 1. Cómo se midió

1. Base recreada sin `008_indices.sql`, con la carga completa, y `ANALYZE`.
2. Cada consulta con `EXPLAIN (ANALYZE, BUFFERS)`, 3 veces seguidas. Se anota la tercera, con los datos ya en caché.
3. Se aplicó `008_indices.sql` sobre la misma base y se corrió `ANALYZE` otra vez.
4. Se repitió el paso 2.

## 2. Resultados

| Consulta | Tiempo antes | Tiempo después | Recorrido antes | Recorrido después | Filas leídas de la tabla principal | Bloques |
|---|---:|---:|---|---|---:|---:|
| **S3** | 3,96 ms | **0,53 ms** | Seq Scan | Bitmap Heap Scan (compuesto) | 50.000 → 28 | 877 → 101 |
| **S5** | 0,96 ms | **0,61 ms** | Seq Scan | Bitmap Heap Scan (parcial) | 8.000 → 40 | 49 → 9 |
| **S8** | 11,00 ms | **6,62 ms** | Seq Scan | Bitmap Heap Scan (BRIN) | 50.000 → 17.318 | 790 → 155 |
| S4 | 0,40 ms | 0,47 ms | Index Scan (PK) | Bitmap Heap Scan (FK) | sin cambios | 106 → 57 |

**Mejoraron 3 consultas: S3, S5 y S8.** S5 reemplaza a S4 en esa cuenta.

**S4 no mejoró en tiempo.** Usa el índice y lee casi la mitad de bloques, pero ya tardaba menos de 1 ms: la diferencia es ruido de la medición. La fecha ya deja solo 32 transferencias y la PK encontraba rápido sus renglones.

**S8 mejoró menos que S3** porque BRIN no es exacto: descarta bloques enteros, y de las 17.318 filas que lee, 8.022 se vuelven a filtrar. Igual lee 5 veces menos bloques que el recorrido completo.

## 3. Por qué cada índice

| Índice | Tipo | Para qué |
|---|---|---|
| `idx_comprobante_sala_fecha` | Compuesto | S3: sala por igualdad y fecha por rango |
| `idx_comprobante_fecha_brin` | BRIN | S8: la tabla está ordenada por fecha (correlación 1) y ocupa 24 kB, contra 968 kB del compuesto |
| `idx_renglon_transf_vino` | Sobre FK | S4: buscar las transferencias de un vino |
| `idx_transferencia_pendientes` | Parcial | S5: solo 20 de las 4.000 transferencias están pendientes, y ocupa 16 kB |
| `idx_renglon_venta_vino` | Sobre FK | Buscar las ventas de un vino: de 6,3 ms a 0,48 ms y de 1.899 a 267 bloques |

## 4. Por qué `(id_sala, fecha)` y no `(fecha, id_sala)`

La sala se busca por igualdad y la fecha por rango. Con `(id_sala, fecha)`, el índice salta a la sala y dentro de ella las fechas están en orden, así que lee un solo tramo continuo. Con `(fecha, id_sala)` recorrería todas las fechas de la semana, de todas las salas, y descartaría las que no son.

## 5. Índice descartado: `vino (tipo)`

Hay solo 4 valores y `tinto` son 271 de 500 vinos. Se creó el índice y PostgreSQL igual eligió Seq Scan: traer más de la mitad de la tabla por índice cuesta más que leerla entera, y la tabla ocupa solo 7 bloques.

## 6. Casos en que el planificador no usa un índice

`idx_renglon_venta_vino` se había pensado para S2, S9 y S12, y la medición mostró otra cosa:

| Consulta | Antes | Después | Por qué |
|---|---:|---:|---|
| S2 | 243,6 ms | 246,2 ms | Necesita **todos** los renglones: lee la tabla entera y usa Hash Join |
| S12a | 353,4 ms | 362,4 ms | Igual que S2 |
| S9 | 2,35 ms | 2,47 ms | No lee `renglon_comprobante` |

Un índice sirve cuando la consulta trae pocas filas. Si necesita casi toda la tabla, leerla entera es más barato.

**S11a tampoco mejora:** tarda entre 2 y 3 minutos con y sin índices. Usa el índice compuesto para encontrar los comprobantes de la sala, pero por cada vino vuelve a leer los 125.135 renglones. El problema es la forma de la consulta, no la falta de un índice. La versión con `RANK() OVER` (opcional) recorrería los datos una sola vez.

## 7. Costo de escritura

Se cargó la base dos veces sin índices y dos veces con índices, y se comparó el tiempo que imprime `cargar.py`:

| Tabla | Sin índices | Con índices |
|---|---:|---:|
| `comprobante` | 1,99 s y 2,88 s | 2,78 s y 3,48 s |
| `renglon_comprobante` | 4,17 s y 7,22 s | 6,60 s y 7,01 s |

Con índices tarda algo más, pero la variación entre dos cargas iguales (de 4,17 s a 7,22 s) es mayor que la diferencia, así que con esta medición no se puede dar un porcentaje. En tamaño, los 5 índices suman unos 2 MB.

Los índices cuestan en cada INSERT porque hay que actualizarlos. Por eso no conviene crearlos «por las dudas».

## 8. Anexo: planes completos

### S3, antes de los índices

```text
                                                                 QUERY PLAN                                                                  
---------------------------------------------------------------------------------------------------------------------------------------------
 GroupAggregate  (cost=1969.48..1969.70 rows=3 width=12) (actual time=3.840..3.842 rows=3.00 loops=1)
   Group Key: cl.tipo_cliente
   Buffers: shared hit=877
   ->  Sort  (cost=1969.48..1969.54 rows=26 width=8) (actual time=3.832..3.834 rows=28.00 loops=1)
         Sort Key: cl.tipo_cliente, c.id_cliente
         Sort Method: quicksort  Memory: 25kB
         Buffers: shared hit=877
         ->  Nested Loop  (cost=0.29..1968.87 rows=26 width=8) (actual time=3.488..3.782 rows=28.00 loops=1)
               Buffers: shared hit=869
               ->  Seq Scan on comprobante c  (cost=0.00..1785.00 rows=26 width=4) (actual time=3.435..3.499 rows=28.00 loops=1)
                     Filter: ((id_sala = 1) AND (fecha >= (CURRENT_DATE - 7)))
                     Rows Removed by Filter: 49972
                     Buffers: shared hit=785
               ->  Index Scan using pk_cliente on cliente cl  (cost=0.29..7.07 rows=1 width=8) (actual time=0.009..0.009 rows=1.00 loops=28)
                     Index Cond: (id_cliente = c.id_cliente)
                     Index Searches: 28
                     Buffers: shared hit=84
 Planning:
   Buffers: shared hit=161
 Planning Time: 0.950 ms
 Execution Time: 3.957 ms
(21 rows)

```

### S3, despues de los índices

```text
                                                                        QUERY PLAN                                                                        
----------------------------------------------------------------------------------------------------------------------------------------------------------
 GroupAggregate  (cost=260.24..260.45 rows=3 width=12) (actual time=0.381..0.383 rows=3.00 loops=1)
   Group Key: cl.tipo_cliente
   Buffers: shared hit=101
   ->  Sort  (cost=260.24..260.30 rows=24 width=8) (actual time=0.376..0.377 rows=28.00 loops=1)
         Sort Key: cl.tipo_cliente, c.id_cliente
         Sort Method: quicksort  Memory: 25kB
         Buffers: shared hit=101
         ->  Nested Loop  (cost=4.83..259.69 rows=24 width=8) (actual time=0.052..0.336 rows=28.00 loops=1)
               Buffers: shared hit=93
               ->  Bitmap Heap Scan on comprobante c  (cost=4.54..88.43 rows=24 width=4) (actual time=0.029..0.044 rows=28.00 loops=1)
                     Recheck Cond: ((id_sala = 1) AND (fecha >= (CURRENT_DATE - 7)))
                     Heap Blocks: exact=7
                     Buffers: shared hit=9
                     ->  Bitmap Index Scan on idx_comprobante_sala_fecha  (cost=0.00..4.54 rows=24 width=0) (actual time=0.011..0.011 rows=28.00 loops=1)
                           Index Cond: ((id_sala = 1) AND (fecha >= (CURRENT_DATE - 7)))
                           Index Searches: 1
                           Buffers: shared hit=2
               ->  Index Scan using pk_cliente on cliente cl  (cost=0.29..7.14 rows=1 width=8) (actual time=0.010..0.010 rows=1.00 loops=28)
                     Index Cond: (id_cliente = c.id_cliente)
                     Index Searches: 28
                     Buffers: shared hit=84
 Planning:
   Buffers: shared hit=213
 Planning Time: 0.986 ms
 Execution Time: 0.529 ms
(25 rows)

```

### S4, antes de los índices

```text
                                                                                     QUERY PLAN                                                                                     
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=291.94..291.94 rows=1 width=12) (actual time=0.327..0.328 rows=5.00 loops=1)
   Buffers: shared hit=106
   InitPlan 1
     ->  Limit  (cost=0.27..10.55 rows=1 width=6) (actual time=0.067..0.067 rows=1.00 loops=1)
           Buffers: shared hit=9
           ->  Index Scan Backward using uq_vino_nombre_anada_volumen on vino  (cost=0.27..20.83 rows=2 width=6) (actual time=0.067..0.067 rows=1.00 loops=1)
                 Index Cond: (((nombre)::text = 'Malbec Reserva'::text) AND (volumen_ml = 750))
                 Index Searches: 1
                 Buffers: shared hit=9
   ->  Sort  (cost=281.38..281.39 rows=1 width=12) (actual time=0.326..0.326 rows=5.00 loops=1)
         Sort Key: (sum(r.cantidad)) DESC, t.id_sala
         Sort Method: quicksort  Memory: 25kB
         Buffers: shared hit=106
         ->  GroupAggregate  (cost=281.35..281.37 rows=1 width=12) (actual time=0.291..0.293 rows=5.00 loops=1)
               Group Key: t.id_sala
               Buffers: shared hit=100
               ->  Sort  (cost=281.35..281.36 rows=1 width=8) (actual time=0.288..0.289 rows=5.00 loops=1)
                     Sort Key: t.id_sala
                     Sort Method: quicksort  Memory: 25kB
                     Buffers: shared hit=100
                     ->  Nested Loop  (cost=0.29..281.34 rows=1 width=8) (actual time=0.257..0.279 rows=5.00 loops=1)
                           Buffers: shared hit=100
                           ->  Seq Scan on transferencia t  (cost=0.00..92.00 rows=29 width=8) (actual time=0.182..0.184 rows=32.00 loops=1)
                                 Filter: (fecha_confeccion >= (CURRENT_DATE - 15))
                                 Rows Removed by Filter: 3968
                                 Buffers: shared hit=22
                           ->  Index Scan using pk_renglon_transferencia on renglon_transferencia r  (cost=0.29..6.51 rows=1 width=8) (actual time=0.001..0.001 rows=0.16 loops=32)
                                 Index Cond: ((nro_solicitud = t.nro_solicitud) AND (cod_vino = (InitPlan 1).col1))
                                 Index Searches: 32
                                 Buffers: shared hit=69
 Planning:
   Buffers: shared hit=227
 Planning Time: 0.806 ms
 Execution Time: 0.399 ms
(34 rows)

```

### S4, despues de los índices

```text
                                                                               QUERY PLAN                                                                                
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=155.93..155.94 rows=1 width=12) (actual time=0.386..0.387 rows=5.00 loops=1)
   Buffers: shared hit=57
   InitPlan 1
     ->  Limit  (cost=0.27..10.55 rows=1 width=6) (actual time=0.062..0.062 rows=1.00 loops=1)
           Buffers: shared hit=9
           ->  Index Scan Backward using uq_vino_nombre_anada_volumen on vino  (cost=0.27..20.83 rows=2 width=6) (actual time=0.061..0.061 rows=1.00 loops=1)
                 Index Cond: (((nombre)::text = 'Malbec Reserva'::text) AND (volumen_ml = 750))
                 Index Searches: 1
                 Buffers: shared hit=9
   ->  Sort  (cost=145.38..145.38 rows=1 width=12) (actual time=0.385..0.386 rows=5.00 loops=1)
         Sort Key: (sum(r.cantidad)) DESC, t.id_sala
         Sort Method: quicksort  Memory: 25kB
         Buffers: shared hit=57
         ->  GroupAggregate  (cost=145.35..145.37 rows=1 width=12) (actual time=0.362..0.364 rows=5.00 loops=1)
               Group Key: t.id_sala
               Buffers: shared hit=51
               ->  Sort  (cost=145.35..145.35 rows=1 width=8) (actual time=0.359..0.360 rows=5.00 loops=1)
                     Sort Key: t.id_sala
                     Sort Method: quicksort  Memory: 25kB
                     Buffers: shared hit=51
                     ->  Hash Join  (cost=53.26..145.34 rows=1 width=8) (actual time=0.347..0.351 rows=5.00 loops=1)
                           Hash Cond: (t.nro_solicitud = r.nro_solicitud)
                           Buffers: shared hit=51
                           ->  Seq Scan on transferencia t  (cost=0.00..92.00 rows=29 width=8) (actual time=0.170..0.172 rows=32.00 loops=1)
                                 Filter: (fecha_confeccion >= (CURRENT_DATE - 15))
                                 Rows Removed by Filter: 3968
                                 Buffers: shared hit=22
                           ->  Hash  (cost=52.96..52.96 rows=24 width=8) (actual time=0.151..0.152 rows=28.00 loops=1)
                                 Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                 Buffers: shared hit=29
                                 ->  Bitmap Heap Scan on renglon_transferencia r  (cost=4.47..52.96 rows=24 width=8) (actual time=0.082..0.145 rows=28.00 loops=1)
                                       Recheck Cond: (cod_vino = (InitPlan 1).col1)
                                       Heap Blocks: exact=18
                                       Buffers: shared hit=29
                                       ->  Bitmap Index Scan on idx_renglon_transf_vino  (cost=0.00..4.46 rows=24 width=0) (actual time=0.075..0.075 rows=28.00 loops=1)
                                             Index Cond: (cod_vino = (InitPlan 1).col1)
                                             Index Searches: 1
                                             Buffers: shared hit=11
 Planning:
   Buffers: shared hit=254
 Planning Time: 0.952 ms
 Execution Time: 0.467 ms
(42 rows)

```

### S5, antes de los índices

```text
                                                                 QUERY PLAN                                                                 
--------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=148.85..148.85 rows=1 width=31) (actual time=0.705..0.709 rows=16.00 loops=1)
   Sort Key: s.id_sala
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=49
   InitPlan 1
     ->  Aggregate  (cost=74.56..74.57 rows=1 width=8) (actual time=0.279..0.281 rows=1.00 loops=1)
           Buffers: shared hit=23
           ->  HashAggregate  (cost=73.89..74.19 rows=30 width=12) (actual time=0.271..0.277 rows=30.00 loops=1)
                 Group Key: s2.id_sala
                 Batches: 1  Memory Usage: 32kB
                 Buffers: shared hit=23
                 ->  Hash Right Join  (cost=1.68..73.74 rows=30 width=8) (actual time=0.253..0.264 rows=36.00 loops=1)
                       Hash Cond: (t2.id_sala = s2.id_sala)
                       Buffers: shared hit=23
                       ->  Seq Scan on transferencia t2  (cost=0.00..72.00 rows=20 width=8) (actual time=0.206..0.210 rows=20.00 loops=1)
                             Filter: (estado <> 'procesado'::estado_documento)
                             Rows Removed by Filter: 3980
                             Buffers: shared hit=22
                       ->  Hash  (cost=1.30..1.30 rows=30 width=4) (actual time=0.018..0.018 rows=30.00 loops=1)
                             Buckets: 1024  Batches: 1  Memory Usage: 10kB
                             Buffers: shared hit=1
                             ->  Seq Scan on sala_venta s2  (cost=0.00..1.30 rows=30 width=4) (actual time=0.010..0.012 rows=30.00 loops=1)
                                   Buffers: shared hit=1
   ->  HashAggregate  (cost=73.89..74.26 rows=1 width=31) (actual time=0.641..0.645 rows=16.00 loops=1)
         Group Key: s.id_sala
         Filter: (count(t.nro_solicitud) = (InitPlan 1).col1)
         Batches: 1  Memory Usage: 32kB
         Rows Removed by Filter: 14
         Buffers: shared hit=46
         ->  Hash Right Join  (cost=1.68..73.74 rows=30 width=27) (actual time=0.337..0.347 rows=36.00 loops=1)
               Hash Cond: (t.id_sala = s.id_sala)
               Buffers: shared hit=23
               ->  Seq Scan on transferencia t  (cost=0.00..72.00 rows=20 width=8) (actual time=0.263..0.266 rows=20.00 loops=1)
                     Filter: (estado <> 'procesado'::estado_documento)
                     Rows Removed by Filter: 3980
                     Buffers: shared hit=22
               ->  Hash  (cost=1.30..1.30 rows=30 width=23) (actual time=0.044..0.044 rows=30.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.30 rows=30 width=23) (actual time=0.023..0.026 rows=30.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=144
 Planning Time: 1.431 ms
 Execution Time: 0.958 ms
(45 rows)

```

### S5, despues de los índices

```text
                                                                             QUERY PLAN                                                                             
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=66.82..66.83 rows=1 width=31) (actual time=0.335..0.340 rows=16.00 loops=1)
   Sort Key: s.id_sala
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=9
   InitPlan 1
     ->  Aggregate  (cost=33.55..33.56 rows=1 width=8) (actual time=0.086..0.088 rows=1.00 loops=1)
           Buffers: shared hit=3
           ->  HashAggregate  (cost=32.88..33.18 rows=30 width=12) (actual time=0.079..0.084 rows=30.00 loops=1)
                 Group Key: s2.id_sala
                 Batches: 1  Memory Usage: 32kB
                 Buffers: shared hit=3
                 ->  Hash Right Join  (cost=9.92..32.73 rows=30 width=8) (actual time=0.062..0.071 rows=36.00 loops=1)
                       Hash Cond: (t2.id_sala = s2.id_sala)
                       Buffers: shared hit=3
                       ->  Bitmap Heap Scan on transferencia t2  (cost=8.24..30.99 rows=20 width=8) (actual time=0.008..0.010 rows=20.00 loops=1)
                             Recheck Cond: (estado <> 'procesado'::estado_documento)
                             Heap Blocks: exact=1
                             Buffers: shared hit=2
                             ->  Bitmap Index Scan on idx_transferencia_pendientes  (cost=0.00..8.24 rows=20 width=0) (actual time=0.002..0.002 rows=20.00 loops=1)
                                   Index Searches: 1
                                   Buffers: shared hit=1
                       ->  Hash  (cost=1.30..1.30 rows=30 width=4) (actual time=0.020..0.021 rows=30.00 loops=1)
                             Buckets: 1024  Batches: 1  Memory Usage: 10kB
                             Buffers: shared hit=1
                             ->  Seq Scan on sala_venta s2  (cost=0.00..1.30 rows=30 width=4) (actual time=0.006..0.008 rows=30.00 loops=1)
                                   Buffers: shared hit=1
   ->  HashAggregate  (cost=32.88..33.25 rows=1 width=31) (actual time=0.220..0.229 rows=16.00 loops=1)
         Group Key: s.id_sala
         Filter: (count(t.nro_solicitud) = (InitPlan 1).col1)
         Batches: 1  Memory Usage: 32kB
         Rows Removed by Filter: 14
         Buffers: shared hit=6
         ->  Hash Right Join  (cost=9.92..32.73 rows=30 width=27) (actual time=0.104..0.115 rows=36.00 loops=1)
               Hash Cond: (t.id_sala = s.id_sala)
               Buffers: shared hit=3
               ->  Bitmap Heap Scan on transferencia t  (cost=8.24..30.99 rows=20 width=8) (actual time=0.044..0.046 rows=20.00 loops=1)
                     Recheck Cond: (estado <> 'procesado'::estado_documento)
                     Heap Blocks: exact=1
                     Buffers: shared hit=2
                     ->  Bitmap Index Scan on idx_transferencia_pendientes  (cost=0.00..8.24 rows=20 width=0) (actual time=0.011..0.011 rows=20.00 loops=1)
                           Index Searches: 1
                           Buffers: shared hit=1
               ->  Hash  (cost=1.30..1.30 rows=30 width=23) (actual time=0.037..0.037 rows=30.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 10kB
                     Buffers: shared hit=1
                     ->  Seq Scan on sala_venta s  (cost=0.00..1.30 rows=30 width=23) (actual time=0.016..0.019 rows=30.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=156
 Planning Time: 0.965 ms
 Execution Time: 0.610 ms
(51 rows)

```

### S8, antes de los índices

```text
                                                                 QUERY PLAN                                                                 
--------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=1822.15..1823.50 rows=540 width=65) (actual time=10.803..10.833 rows=30.00 loops=1)
   Sort Key: (sum(c.total)) DESC
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=790
   ->  HashAggregate  (cost=1790.89..1797.64 rows=540 width=65) (actual time=10.758..10.794 rows=30.00 loops=1)
         Group Key: s.id_sala, l.nombre
         Batches: 1  Memory Usage: 57kB
         Buffers: shared hit=787
         ->  Hash Join  (cost=3.08..1721.12 rows=9303 width=39) (actual time=5.229..9.138 rows=9296.00 loops=1)
               Hash Cond: (s.id_localidad = l.id_localidad)
               Buffers: shared hit=787
               ->  Hash Join  (cost=1.68..1689.54 rows=9303 width=33) (actual time=5.191..8.055 rows=9296.00 loops=1)
                     Hash Cond: (c.id_sala = s.id_sala)
                     Buffers: shared hit=786
                     ->  Seq Scan on comprobante c  (cost=0.00..1660.00 rows=9303 width=10) (actual time=5.120..6.535 rows=9296.00 loops=1)
                           Filter: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                           Rows Removed by Filter: 40704
                           Buffers: shared hit=785
                     ->  Hash  (cost=1.30..1.30 rows=30 width=27) (actual time=0.038..0.038 rows=30.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 10kB
                           Buffers: shared hit=1
                           ->  Seq Scan on sala_venta s  (cost=0.00..1.30 rows=30 width=27) (actual time=0.018..0.020 rows=30.00 loops=1)
                                 Buffers: shared hit=1
               ->  Hash  (cost=1.18..1.18 rows=18 width=14) (actual time=0.019..0.020 rows=18.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on localidad l  (cost=0.00..1.18 rows=18 width=14) (actual time=0.009..0.011 rows=18.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=193
 Planning Time: 1.091 ms
 Execution Time: 10.996 ms
(32 rows)

```

### S8, despues de los índices

```text
                                                                              QUERY PLAN                                                                              
----------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=1210.61..1211.96 rows=540 width=65) (actual time=6.483..6.486 rows=30.00 loops=1)
   Sort Key: (sum(c.total)) DESC
   Sort Method: quicksort  Memory: 26kB
   Buffers: shared hit=155
   ->  HashAggregate  (cost=1179.36..1186.11 rows=540 width=65) (actual time=6.439..6.448 rows=30.00 loops=1)
         Group Key: s.id_sala, l.nombre
         Batches: 1  Memory Usage: 57kB
         Buffers: shared hit=152
         ->  Hash Join  (cost=17.46..1110.09 rows=9236 width=39) (actual time=0.931..4.734 rows=9296.00 loops=1)
               Hash Cond: (s.id_localidad = l.id_localidad)
               Buffers: shared hit=152
               ->  Hash Join  (cost=16.05..1078.73 rows=9236 width=33) (actual time=0.900..3.605 rows=9296.00 loops=1)
                     Hash Cond: (c.id_sala = s.id_sala)
                     Buffers: shared hit=151
                     ->  Bitmap Heap Scan on comprobante c  (cost=14.38..1049.38 rows=9236 width=10) (actual time=0.842..2.143 rows=9296.00 loops=1)
                           Recheck Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                           Rows Removed by Index Recheck: 8022
                           Heap Blocks: lossy=145
                           Buffers: shared hit=150
                           ->  Bitmap Index Scan on idx_comprobante_fecha_brin  (cost=0.00..12.07 rows=14286 width=0) (actual time=0.033..0.033 rows=1450.00 loops=1)
                                 Index Cond: (fecha >= (CURRENT_DATE - '3 mons'::interval))
                                 Index Searches: 1
                                 Buffers: shared hit=5
                     ->  Hash  (cost=1.30..1.30 rows=30 width=27) (actual time=0.014..0.014 rows=30.00 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 10kB
                           Buffers: shared hit=1
                           ->  Seq Scan on sala_venta s  (cost=0.00..1.30 rows=30 width=27) (actual time=0.004..0.006 rows=30.00 loops=1)
                                 Buffers: shared hit=1
               ->  Hash  (cost=1.18..1.18 rows=18 width=14) (actual time=0.016..0.017 rows=18.00 loops=1)
                     Buckets: 1024  Batches: 1  Memory Usage: 9kB
                     Buffers: shared hit=1
                     ->  Seq Scan on localidad l  (cost=0.00..1.18 rows=18 width=14) (actual time=0.007..0.008 rows=18.00 loops=1)
                           Buffers: shared hit=1
 Planning:
   Buffers: shared hit=245
 Planning Time: 0.973 ms
 Execution Time: 6.618 ms
(37 rows)

```
