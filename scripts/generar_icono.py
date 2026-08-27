"""
Genera los assets del ícono de la app (ejecutar una sola vez, o cuando
se quiera cambiar el diseño del ícono). Produce:
  - frontend/assets/icon/icon.png              (1024x1024, con fondo)
  - frontend/assets/icon/icon_foreground.png    (1024x1024, transparente)

Estos dos archivos los consume el paquete flutter_launcher_icons
(configurado en pubspec.yaml) para generar automáticamente todos los
mipmaps de Android (adaptive icon: fondo sólido + foreground) al
correr:
    flutter pub run flutter_launcher_icons
"""

from PIL import Image, ImageDraw

PRIMARIO = (10, 37, 64, 255)      # #0A2540
ACENTO = (56, 189, 248, 255)      # #38BDF8
TRANSPARENTE = (0, 0, 0, 0)

TAMANO = 1024


def _cruz_farmacia(draw: ImageDraw.ImageDraw, centro: tuple[int, int], brazo: int, grosor: int, color) -> None:
    cx, cy = centro
    radio_esquina = grosor * 0.28
    draw.rounded_rectangle(
        [cx - grosor / 2, cy - brazo / 2, cx + grosor / 2, cy + brazo / 2],
        radius=radio_esquina,
        fill=color,
    )
    draw.rounded_rectangle(
        [cx - brazo / 2, cy - grosor / 2, cx + brazo / 2, cy + grosor / 2],
        radius=radio_esquina,
        fill=color,
    )


def generar_icono_con_fondo(ruta: str) -> None:
    img = Image.new("RGBA", (TAMANO, TAMANO), TRANSPARENTE)
    draw = ImageDraw.Draw(img)

    margen = TAMANO * 0.08
    draw.rounded_rectangle(
        [margen, margen, TAMANO - margen, TAMANO - margen],
        radius=TAMANO * 0.22,
        fill=PRIMARIO,
    )

    centro = (TAMANO // 2, TAMANO // 2)
    _cruz_farmacia(draw, centro, brazo=TAMANO * 0.46, grosor=TAMANO * 0.16, color=ACENTO)

    img.save(ruta, "PNG")


def generar_icono_foreground(ruta: str) -> None:
    img = Image.new("RGBA", (TAMANO, TAMANO), TRANSPARENTE)
    draw = ImageDraw.Draw(img)

    centro = (TAMANO // 2, TAMANO // 2)
    # La "safe zone" del ícono adaptativo de Android es ~66% central,
    # así que el brazo de la cruz se dimensiona más chico que en la
    # versión con fondo para que ningún launcher lo recorte.
    _cruz_farmacia(draw, centro, brazo=TAMANO * 0.34, grosor=TAMANO * 0.12, color=ACENTO)

    img.save(ruta, "PNG")


if __name__ == "__main__":
    import os

    destino = os.path.join(
        os.path.dirname(__file__), "..", "frontend", "assets", "icon"
    )
    destino = os.path.abspath(destino)
    os.makedirs(destino, exist_ok=True)

    ruta_fondo = os.path.join(destino, "icon.png")
    ruta_foreground = os.path.join(destino, "icon_foreground.png")

    generar_icono_con_fondo(ruta_fondo)
    generar_icono_foreground(ruta_foreground)

    print(f"Generado: {ruta_fondo}")
    print(f"Generado: {ruta_foreground}")
