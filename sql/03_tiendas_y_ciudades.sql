-- =====================================================================================================
-- PREGUNTA 3 · ¿Qué tiendas y ciudades rinden mejor?
-- =====================================================================================================
-- Equivale a la Pregunta 3 del notebook 02_preguntas_de_negocio.ipynb.
--
-- Cómo ejecutarlo (desde la carpeta raíz del proyecto, con el entorno virtual activado):
--     python sql/ejecutar_consulta.py sql/03_tiendas_y_ciudades.sql
--
-- Métrica justa: VENTAS PROMEDIO POR DÍA desde el 1-ene-2016.
--   * 2016 ya está dentro del periodo confiable (desde jun-2015) y para entonces todas las tiendas, menos
--     la 52, estaban abiertas.
--   * Contamos los días que cada tienda estuvo abierta con transactions: si una tienda registró tickets ese
--     día, estaba abierta. Así la tienda 52 (abrió en abril de 2017) se divide solo por sus días abiertos.
-- =====================================================================================================


-- -----------------------------------------------------------------------------------------------------
-- Paso 3.1 · Ventas promedio por día de cada tienda
-- -----------------------------------------------------------------------------------------------------
-- Guardamos el resultado en una tabla temporal porque lo usamos en los pasos 3.2 y 3.3.

DROP TABLE IF EXISTS temp.tiendas;

CREATE TEMP TABLE tiendas AS
WITH ventas_tienda AS (
    -- 1) Ventas totales de cada tienda desde 2016
    SELECT store_nbr,
           SUM(sales) AS ventas
    FROM train
    WHERE date >= '2016-01-01'
    GROUP BY store_nbr
),
dias_abierta AS (
    -- 2) Días distintos en que cada tienda tuvo transacciones desde 2016.
    --    COUNT(DISTINCT date) cuenta cada fecha una sola vez.
    SELECT store_nbr,
           COUNT(DISTINCT date) AS dias_abierta
    FROM transactions
    WHERE date >= '2016-01-01'
    GROUP BY store_nbr
)
-- 3) Unimos ventas, días abiertos y datos de la tienda (ciudad, tipo, cluster) con JOIN.
SELECT s.store_nbr,
       s.city,
       s.state,
       s.type,
       s.cluster,
       v.ventas,
       d.dias_abierta,
       v.ventas / d.dias_abierta AS ventas_por_dia
FROM ventas_tienda AS v
JOIN dias_abierta  AS d ON d.store_nbr = v.store_nbr
JOIN stores        AS s ON s.store_nbr = v.store_nbr;

-- RESULTADO: Paso 3.1 · Top 10 tiendas por ventas promedio por día (2016-2017, unidades)
SELECT store_nbr,
       city,
       type,
       cluster,
       ROUND(ventas)            AS ventas,
       dias_abierta,
       ROUND(ventas_por_dia, 2) AS ventas_por_dia
FROM tiendas
ORDER BY ventas_por_dia DESC
LIMIT 10;                                          -- LIMIT muestra solo las primeras 10 filas


-- -----------------------------------------------------------------------------------------------------
-- Paso 3.2 · Por tipo de tienda
-- -----------------------------------------------------------------------------------------------------
-- Promedio simple de las ventas por día de las tiendas de cada tipo.

-- RESULTADO: Paso 3.2 · Ventas por día promedio según el tipo de tienda
SELECT type,
       COUNT(*)                     AS tiendas,
       ROUND(AVG(ventas_por_dia), 2) AS ventas_por_dia_promedio
FROM tiendas
GROUP BY type
ORDER BY ventas_por_dia_promedio DESC;


-- -----------------------------------------------------------------------------------------------------
-- Paso 3.3 · Por ciudad
-- -----------------------------------------------------------------------------------------------------
-- Dos miradas distintas:
--   * ventas_por_dia_total: suma de las tiendas de la ciudad -> ¿dónde está el negocio?
--   * ventas_por_dia_por_tienda: promedio por tienda -> ¿qué tan productiva es cada tienda?
--   * participacion_pct: la ciudad sobre el total del país (SUM(...) OVER () es el total de todas las filas).

-- RESULTADO: Paso 3.3 · Ciudades ordenadas por ventas por día totales
SELECT city,
       COUNT(*)                                                       AS tiendas,
       ROUND(SUM(ventas_por_dia), 2)                                  AS ventas_por_dia_total,
       ROUND(AVG(ventas_por_dia), 2)                                  AS ventas_por_dia_por_tienda,
       ROUND(SUM(ventas_por_dia) / SUM(SUM(ventas_por_dia)) OVER () * 100, 2) AS participacion_pct
FROM tiendas
GROUP BY city
ORDER BY ventas_por_dia_total DESC;
-- SUM(SUM(...)) OVER (): el SUM de adentro suma las tiendas de cada ciudad (GROUP BY) y el de afuera
-- suma todas las ciudades. Es la forma de calcular "% del total" en la misma consulta.
