-- =====================================================================================================
-- PREGUNTA 4 · ¿Las promociones aumentan las ventas?
-- =====================================================================================================
-- Equivale a la Pregunta 4 del notebook 02_preguntas_de_negocio.ipynb.
--
-- Cómo ejecutarlo (desde la carpeta raíz del proyecto, con el entorno virtual activado):
--     python sql/ejecutar_consulta.py sql/04_promociones.sql
--
-- Idea: comparar "manzanas con manzanas". Para cada combinación TIENDA + FAMILIA comparamos la venta
-- promedio en días CON promoción contra la venta promedio en días SIN promoción:
--
--     lift = venta promedio con promoción / venta promedio sin promoción
--
-- Un lift de 1,24 significa que con promoción se vende un 24% más. Después tomamos la MEDIANA de los lifts.
--
-- Usamos el PERIODO CONFIABLE (desde el 1-jun-2015): en los meses con huecos una familia podía tener
-- promociones registradas pero ventas en cero, y eso distorsionaría la comparación.
--
-- Recordatorio: es un análisis OBSERVACIONAL (asociación, no causalidad).
-- =====================================================================================================


-- -----------------------------------------------------------------------------------------------------
-- Paso 4.1 · ¿Qué porcentaje de las filas tiene alguna promoción?
-- -----------------------------------------------------------------------------------------------------
-- onpromotion > 0 es una condición: vale 1 si es verdadera y 0 si es falsa. Su promedio es la proporción.

-- RESULTADO: Paso 4.1 · % de filas (tienda-familia-día) con alguna promoción desde jun-2015
SELECT ROUND(AVG(onpromotion > 0) * 100, 1) AS filas_con_promo_pct
FROM train
WHERE date >= '2015-06-01';


-- -----------------------------------------------------------------------------------------------------
-- Paso 4.2 · Lift de cada combinación tienda + familia
-- -----------------------------------------------------------------------------------------------------
-- AVG(CASE WHEN onpromotion > 0 THEN sales END): promedio solo de los días con promoción.
-- AVG(CASE WHEN onpromotion = 0 THEN sales END): promedio solo de los días sin promoción.
-- Si una combinación nunca tuvo promoción (o nunca estuvo sin ella), el promedio queda NULL y la
-- descartamos. También descartamos las que venden 0 sin promoción, para no dividir por cero.

DROP TABLE IF EXISTS temp.lift_tienda_familia;

CREATE TEMP TABLE lift_tienda_familia AS
WITH promedios AS (
    SELECT store_nbr,
           family,
           AVG(CASE WHEN onpromotion > 0 THEN sales END) AS con_promo,
           AVG(CASE WHEN onpromotion = 0 THEN sales END) AS sin_promo
    FROM train
    WHERE date >= '2015-06-01'
    GROUP BY store_nbr, family
)
SELECT store_nbr,
       family,
       con_promo,
       sin_promo,
       con_promo / sin_promo AS lift
FROM promedios
WHERE con_promo IS NOT NULL
  AND sin_promo > 0;                    -- "> 0" también descarta los NULL


-- -----------------------------------------------------------------------------------------------------
-- Paso 4.3 · Mediana del lift (todas las combinaciones)
-- -----------------------------------------------------------------------------------------------------
-- SQLite no tiene una función MEDIAN, así que la calculamos a mano:
--   1) Ordenamos los lifts de menor a mayor y numeramos cada fila (ROW_NUMBER) -> posicion.
--   2) Contamos cuántas filas hay (COUNT(*) OVER ()) -> n.
--   3) La mediana es el valor del medio. Si n es impar hay una fila central; si es par, promediamos
--      las dos centrales. Las posiciones (n + 1) / 2 y (n + 2) / 2 (división entera) cubren ambos casos:
--      n = 5 -> posiciones 3 y 3 | n = 6 -> posiciones 3 y 4.

-- RESULTADO: Paso 4.3 · Lift mediano y % de combinaciones donde la promoción vende más
WITH ordenados AS (
    SELECT lift,
           ROW_NUMBER() OVER (ORDER BY lift) AS posicion,
           COUNT(*)     OVER ()              AS n
    FROM lift_tienda_familia
)
SELECT MAX(n)                                                     AS combinaciones_tienda_familia,
       ROUND(AVG(CASE WHEN posicion IN ((n + 1) / 2, (n + 2) / 2) THEN lift END), 2) AS lift_mediano,
       ROUND(AVG(lift > 1) * 100)                                 AS pct_combinaciones_lift_mayor_a_1
FROM ordenados;


-- -----------------------------------------------------------------------------------------------------
-- Paso 4.4 · Lift mediano por familia (solo familias relevantes)
-- -----------------------------------------------------------------------------------------------------
-- Igual que antes, pero la numeración se reinicia en cada familia: PARTITION BY family.
-- Familias relevantes = las que pesan al menos 0,5% de las ventas desde jun-2015 (como en la pregunta 2).

-- RESULTADO: Paso 4.4 · Lift mediano por familia (% extra de ventas en días con promoción)
WITH ordenados AS (
    SELECT family,
           lift,
           ROW_NUMBER() OVER (PARTITION BY family ORDER BY lift) AS posicion,
           COUNT(*)     OVER (PARTITION BY family)               AS n
    FROM lift_tienda_familia
),
mediana_familia AS (
    SELECT family,
           AVG(CASE WHEN posicion IN ((n + 1) / 2, (n + 2) / 2) THEN lift END) AS lift_mediano
    FROM ordenados
    GROUP BY family
),
relevantes AS (
    SELECT family
    FROM train
    WHERE date >= '2015-06-01'
    GROUP BY family
    HAVING SUM(sales) >= 0.005 * (SELECT SUM(sales) FROM train WHERE date >= '2015-06-01')
)
SELECT family,
       ROUND(lift_mediano, 2)               AS lift_mediano,
       ROUND((lift_mediano - 1) * 100)      AS ventas_extra_con_promo_pct
FROM mediana_familia
WHERE family IN (SELECT family FROM relevantes)
ORDER BY lift_mediano DESC;
