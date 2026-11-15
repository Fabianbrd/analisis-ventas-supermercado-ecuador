# Resumen ejecutivo: ventas de Corporación Favorita (2013–2017)

**Datos:** 3 millones de registros diarios · 54 tiendas · 33 familias de producto · ene-2013 a ago-2017.
**Unidad:** unidades vendidas (no dólares).

## Hallazgos clave

| # | Pregunta | Hallazgo | Dato clave |
|---|---|---|---|
| 1 | Evolución y estacionalidad | Crecimiento sostenido que se desacelera; estacionalidad anual, semanal y mensual. | +20% (2014) → +9% (2017); diciembre ≈ +30%; domingo +28%, jueves −21% vs. promedio |
| 2 | Familias | Alta concentración. Crecen lácteos, huevos y bebidas; caen comidas preparadas y congelados. | Top 3 = 67% de las ventas; total +6,3% en el último año |
| 3 | Tiendas y ciudades | Quito domina; el formato de tienda es determinante. | Quito = 50% de las ventas con 33% de las tiendas; tipo A ≈ 4 × tipo C |
| 4 | Promociones | Asociadas a más ventas en casi todas las tiendas y familias. | +24% (mediana); 91% de los casos |
| 5 | Feriados / petróleo / terremoto | Feriados con efectos mixtos; petróleo sin efecto directo; terremoto = pico de una semana. | Navidad +35%, 1-ene −22%; corr. de cambios +0,04; 18-abr-2016: ×2 |

## Recomendaciones

1. Ajustar inventario y personal al calendario: diciembre, fines de semana y días de pago (30 al 5).
2. Concentrar la inversión promocional en `GROCERY I`, `FROZEN FOODS` y bebidas; revisar las promociones de
   `PREPARED FOODS`, `DELI` y `HOME CARE`.
3. Investigar la caída de `PREPARED FOODS` y `FROZEN FOODS`.
4. Analizar la brecha de productividad entre las tiendas de Guayaquil y las de Quito.
5. Corregir los huecos de registro anteriores a junio de 2015 antes de construir modelos de predicción.

## Advertencias metodológicas

- Hasta mayo de 2015, 12 familias tienen meses sin registrar. Las tendencias largas usan solo las 20 familias
  completas, y el resto del análisis usa datos desde junio de 2015.
- Los feriados trasladados (`transferred = True`) se tratan como días normales y el día `Transfer` como feriado.
- El efecto de las promociones es una asociación, no un efecto causal demostrado.

Detalle completo y código: `notebooks/02_preguntas_de_negocio.ipynb`.
