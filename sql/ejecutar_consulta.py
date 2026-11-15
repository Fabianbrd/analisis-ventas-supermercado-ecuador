"""
Ejecuta un archivo .sql sobre data/ventas.db y muestra cada resultado como una tabla.

Uso (desde la carpeta raíz del proyecto, con el entorno virtual activado):

    python sql/ejecutar_consulta.py sql/01_evolucion_y_estacionalidad.sql

Cada archivo .sql tiene varias consultas separadas por punto y coma. Este script las ejecuta en
orden e imprime el resultado de cada una. Si justo antes de una consulta hay una línea que empieza con
"-- RESULTADO:", ese texto se usa como título del resultado.

Requiere haber ejecutado antes: python sql/00_cargar_datos.py
"""

import sqlite3
import sys
import time
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DB = RAIZ / "data" / "ventas.db"
MARCA_TITULO = "-- RESULTADO:"


def separar_consultas(texto):
    """Divide el archivo en consultas completas. Devuelve una lista de (título, consulta)."""
    consultas, actual, titulo = [], "", None
    for linea in texto.splitlines(keepends=True):
        if linea.strip().startswith(MARCA_TITULO):
            titulo = linea.strip()[len(MARCA_TITULO):].strip()
        actual += linea
        # sqlite3.complete_statement indica si el texto acumulado ya es una sentencia completa (termina en ;)
        if sqlite3.complete_statement(actual):
            consultas.append((titulo, actual))
            actual, titulo = "", None
    return consultas


def formatear(valor, sin_decimales):
    if valor is None:
        return ""
    if isinstance(valor, float) and sin_decimales:
        valor = int(valor)                       # ROUND(x) devuelve 123.0: lo mostramos como 123
    if isinstance(valor, float):
        return f"{valor:,.2f}"
    if isinstance(valor, int):
        # Separador de miles solo desde 10.000, para que los años se vean como 2016 y no 2,016
        return f"{valor:,}" if abs(valor) >= 10_000 else str(valor)
    return str(valor)


def imprimir_tabla(columnas, filas):
    # Una columna se muestra sin decimales si todos sus números son enteros (ej. resultado de ROUND(x)).
    sin_decimales = [all(not isinstance(f[i], float) or f[i].is_integer() for f in filas)
                     for i in range(len(columnas))]
    celdas = [[formatear(v, sin_decimales[i]) for i, v in enumerate(fila)] for fila in filas]
    anchos = [max([len(c)] + [len(f[i]) for f in celdas]) for i, c in enumerate(columnas)]
    alinear_derecha = [all(isinstance(f[i], (int, float)) or f[i] is None for f in filas) for i in range(len(columnas))]

    def linea(valores):
        return "  ".join(v.rjust(a) if der else v.ljust(a)
                         for v, a, der in zip(valores, anchos, alinear_derecha))

    print(linea(columnas))
    print("  ".join("-" * a for a in anchos))
    for fila in celdas:
        print(linea(fila))
    print(f"({len(filas)} filas)\n")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Uso: python sql/ejecutar_consulta.py sql/<archivo>.sql")
    if not DB.exists():
        raise SystemExit("No existe data/ventas.db. Ejecuta primero: python sql/00_cargar_datos.py")

    archivo = Path(sys.argv[1])
    conexion = sqlite3.connect(DB)
    try:
        for titulo, consulta in separar_consultas(archivo.read_text(encoding="utf-8")):
            inicio = time.time()
            cursor = conexion.execute(consulta)
            if cursor.description is None:          # sentencia sin resultado (ej. CREATE TEMP TABLE)
                continue
            print("=" * 100)
            print(titulo or "Resultado")
            print("=" * 100)
            imprimir_tabla([c[0] for c in cursor.description], cursor.fetchall())
            print(f"[{time.time() - inicio:.1f} s]\n")
    finally:
        conexion.close()


if __name__ == "__main__":
    main()
