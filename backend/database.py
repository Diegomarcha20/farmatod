"""
Capa de acceso a datos. Define el modelo Producto (SKU, principio activo,
laboratorio, ubicación en el planograma, stock local, etc.) sobre
SQLite + SQLAlchemy, y siembra un catálogo de ejemplo -varias marcas y
presentaciones por cada principio activo- la primera vez que se crea
la base.
"""

from datetime import datetime, timezone

from sqlalchemy import (
    Column,
    DateTime,
    Float,
    Integer,
    String,
    create_engine,
)
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

DATABASE_URL = "sqlite:///./farmacia.db"

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


class Producto(Base):
    __tablename__ = "productos"

    id = Column(Integer, primary_key=True, index=True)
    sku = Column(String(32), unique=True, index=True, nullable=False)
    codigo_barras = Column(String(20), unique=True, index=True, nullable=True)
    nombre = Column(String(150), index=True, nullable=False)
    principio_activo = Column(String(150), index=True, nullable=False)
    categoria = Column(String(100), nullable=True)
    descripcion = Column(String(500), nullable=True)
    laboratorio = Column(String(120), nullable=True)
    pais_origen = Column(String(80), nullable=True)
    precio = Column(Float, nullable=False, default=0.0)
    stock = Column(Integer, nullable=False, default=0)
    ubicacion_planograma = Column(String(100), nullable=False)
    sucursal = Column(String(100), nullable=False, default="Arbolitos, San Cristóbal")
    imagen_url = Column(String(300), nullable=True)
    actualizado_en = Column(
        DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc)
    )


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _sembrar_datos(db: Session) -> None:
    """Inserta un catálogo inicial de ejemplo si la tabla está vacía:
    varias marcas/presentaciones reales por cada principio activo, para
    que buscar por nombre genérico (p. ej. "Ibuprofeno") devuelva
    opciones de verdad para elegir."""
    if db.query(Producto).first() is not None:
        return

    SUCURSAL = "Arbolitos, San Cristóbal"

    productos_demo = [
        # ---------------------------------------------------------------
        # Paracetamol
        # ---------------------------------------------------------------
        Producto(
            sku="MED-0001",
            codigo_barras="7591234500017",
            nombre="Paracetamol 500mg x20 Tabletas",
            principio_activo="Paracetamol",
            categoria="Analgésico / Antipirético",
            descripcion="Analgésico y antipirético: alivia el dolor leve a moderado y reduce la fiebre.",
            laboratorio="Genven",
            pais_origen="Venezuela",
            precio=3.50,
            stock=42,
            ubicacion_planograma="Pasillo 2 - Estante A - Nivel 3",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/paracetamol-500.jpg",
        ),
        Producto(
            sku="MED-0002",
            codigo_barras="7591234500024",
            nombre="Acetaminofén Genérico 500mg x20",
            principio_activo="Paracetamol",
            categoria="Analgésico / Antipirético",
            descripcion="Analgésico y antipirético: alivia el dolor leve a moderado y reduce la fiebre.",
            laboratorio="Calox",
            pais_origen="Venezuela",
            precio=2.10,
            stock=0,
            ubicacion_planograma="Pasillo 2 - Estante A - Nivel 4",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/acetaminofen-generico.jpg",
        ),
        Producto(
            sku="MED-0003",
            codigo_barras="7591234500338",
            nombre="Paracetamol Elmor 500mg x20 Tabletas",
            principio_activo="Paracetamol",
            categoria="Analgésico / Antipirético",
            descripcion="Analgésico y antipirético: alivia el dolor leve a moderado y reduce la fiebre.",
            laboratorio="Elmor",
            pais_origen="Venezuela",
            precio=3.20,
            stock=18,
            ubicacion_planograma="Pasillo 2 - Estante A - Nivel 3",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/paracetamol-elmor.jpg",
        ),
        Producto(
            sku="MED-0004",
            codigo_barras="7591234500345",
            nombre="Paracetamol Gotas Pediátricas 100mg/ml",
            principio_activo="Paracetamol",
            categoria="Analgésico / Antipirético",
            descripcion="Presentación pediátrica en gotas para alivio del dolor y la fiebre en niños.",
            laboratorio="Vargas",
            pais_origen="Venezuela",
            precio=4.90,
            stock=11,
            ubicacion_planograma="Pasillo 5 - Estante Infantil - Nivel 1",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/paracetamol-gotas.jpg",
        ),
        # ---------------------------------------------------------------
        # Ibuprofeno
        # ---------------------------------------------------------------
        Producto(
            sku="MED-0010",
            codigo_barras="7591234500109",
            nombre="Ibuprofeno 400mg x10 Tabletas",
            principio_activo="Ibuprofeno",
            categoria="Antiinflamatorio no esteroideo",
            descripcion="Antiinflamatorio no esteroideo (AINE): alivia dolor, inflamación y fiebre.",
            laboratorio="Behrens",
            pais_origen="Venezuela",
            precio=4.20,
            stock=0,
            ubicacion_planograma="Pasillo 2 - Estante B - Nivel 1",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/ibuprofeno-400.jpg",
        ),
        Producto(
            sku="MED-0011",
            codigo_barras="7591234500116",
            nombre="Ibuprofeno Suspensión Infantil 100mg/5ml",
            principio_activo="Ibuprofeno",
            categoria="Antiinflamatorio no esteroideo",
            descripcion="Presentación pediátrica en jarabe para dolor, inflamación y fiebre en niños.",
            laboratorio="Genven",
            pais_origen="Venezuela",
            precio=6.75,
            stock=15,
            ubicacion_planograma="Pasillo 5 - Estante Infantil - Nivel 2",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/ibuprofeno-jarabe.jpg",
        ),
        Producto(
            sku="MED-0012",
            codigo_barras="7591234500123",
            nombre="Ibuprofeno Vargas 600mg x10 Tabletas",
            principio_activo="Ibuprofeno",
            categoria="Antiinflamatorio no esteroideo",
            descripcion="Antiinflamatorio no esteroideo (AINE): alivia dolor, inflamación y fiebre.",
            laboratorio="Vargas",
            pais_origen="Venezuela",
            precio=5.40,
            stock=9,
            ubicacion_planograma="Pasillo 2 - Estante B - Nivel 1",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/ibuprofeno-vargas.jpg",
        ),
        # ---------------------------------------------------------------
        # Loratadina
        # ---------------------------------------------------------------
        Producto(
            sku="MED-0020",
            codigo_barras="7591234500208",
            nombre="Loratadina 10mg x10 Tabletas",
            principio_activo="Loratadina",
            categoria="Antihistamínico",
            descripcion=(
                "Antihistamínico de segunda generación para síntomas alérgicos "
                "(rinitis, urticaria); no suele causar somnolencia."
            ),
            laboratorio="Leti",
            pais_origen="Venezuela",
            precio=5.00,
            stock=8,
            ubicacion_planograma="Pasillo 3 - Estante C - Nivel 2",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/loratadina-10.jpg",
        ),
        Producto(
            sku="MED-0022",
            codigo_barras="7591234500222",
            nombre="Loratadina Jarabe 5mg/5ml",
            principio_activo="Loratadina",
            categoria="Antihistamínico",
            descripcion=(
                "Antihistamínico de segunda generación en presentación líquida "
                "para síntomas alérgicos; no suele causar somnolencia."
            ),
            laboratorio="Calox",
            pais_origen="Venezuela",
            precio=5.60,
            stock=13,
            ubicacion_planograma="Pasillo 3 - Estante C - Nivel 2",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/loratadina-jarabe.jpg",
        ),
        # ---------------------------------------------------------------
        # Cetirizina (principio activo propio, distinto de la Loratadina
        # aunque de la misma familia de antihistamínicos)
        # ---------------------------------------------------------------
        Producto(
            sku="MED-0021",
            codigo_barras="7591234500215",
            nombre="Cetirizina 10mg x10 Tabletas",
            principio_activo="Cetirizina",
            categoria="Antihistamínico",
            descripcion=(
                "Antihistamínico de segunda generación para alergias; puede "
                "causar somnolencia leve en algunas personas."
            ),
            laboratorio="Elmor",
            pais_origen="Venezuela",
            precio=5.50,
            stock=20,
            ubicacion_planograma="Pasillo 3 - Estante C - Nivel 3",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/cetirizina-10.jpg",
        ),
        Producto(
            sku="MED-0023",
            codigo_barras="7591234500239",
            nombre="Cetirizina Gotas Pediátricas 10mg/ml",
            principio_activo="Cetirizina",
            categoria="Antihistamínico",
            descripcion="Presentación pediátrica en gotas para síntomas alérgicos en niños.",
            laboratorio="Genven",
            pais_origen="Venezuela",
            precio=6.10,
            stock=0,
            ubicacion_planograma="Pasillo 3 - Estante C - Nivel 3",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/cetirizina-gotas.jpg",
        ),
        # ---------------------------------------------------------------
        # Amoxicilina
        # ---------------------------------------------------------------
        Producto(
            sku="MED-0030",
            codigo_barras="7591234500307",
            nombre="Amoxicilina 500mg x12 Cápsulas",
            principio_activo="Amoxicilina",
            categoria="Antibiótico",
            descripcion="Antibiótico betalactámico de amplio espectro para infecciones bacterianas. Requiere receta médica.",
            laboratorio="Vargas",
            pais_origen="Venezuela",
            precio=8.90,
            stock=6,
            ubicacion_planograma="Pasillo 1 - Estante Controlados - Nivel 1",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/amoxicilina-500.jpg",
        ),
        Producto(
            sku="MED-0031",
            codigo_barras="7591234500314",
            nombre="Amoxicilina Suspensión Pediátrica 250mg/5ml",
            principio_activo="Amoxicilina",
            categoria="Antibiótico",
            descripcion="Antibiótico betalactámico en jarabe para infecciones bacterianas en niños. Requiere receta médica.",
            laboratorio="Behrens",
            pais_origen="Venezuela",
            precio=7.30,
            stock=10,
            ubicacion_planograma="Pasillo 1 - Estante Controlados - Nivel 1",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/amoxicilina-suspension.jpg",
        ),
        Producto(
            sku="MED-0032",
            codigo_barras="7591234500321",
            nombre="Amoxicilina + Ácido Clavulánico 875mg/125mg x14",
            principio_activo="Amoxicilina",
            categoria="Antibiótico",
            descripcion=(
                "Antibiótico betalactámico combinado con inhibidor de betalactamasas, "
                "para infecciones bacterianas resistentes. Requiere receta médica."
            ),
            laboratorio="Genven",
            pais_origen="Venezuela",
            precio=12.50,
            stock=0,
            ubicacion_planograma="Pasillo 1 - Estante Controlados - Nivel 2",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/amoxicilina-clavulanico.jpg",
        ),
        # ---------------------------------------------------------------
        # Omeprazol
        # ---------------------------------------------------------------
        Producto(
            sku="MED-0040",
            codigo_barras="7591234500406",
            nombre="Omeprazol 20mg x14 Cápsulas",
            principio_activo="Omeprazol",
            categoria="Inhibidor de bomba de protones",
            descripcion="Inhibidor de la bomba de protones: reduce la acidez estomacal para tratar gastritis, reflujo y úlceras.",
            laboratorio="Calox",
            pais_origen="Venezuela",
            precio=4.80,
            stock=30,
            ubicacion_planograma="Pasillo 4 - Estante A - Nivel 1",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/omeprazol-20.jpg",
        ),
        Producto(
            sku="MED-0041",
            codigo_barras="7591234500413",
            nombre="Omeprazol Leti 40mg x14 Cápsulas",
            principio_activo="Omeprazol",
            categoria="Inhibidor de bomba de protones",
            descripcion="Inhibidor de la bomba de protones, dosis reforzada, para casos de mayor acidez estomacal.",
            laboratorio="Leti",
            pais_origen="Venezuela",
            precio=6.20,
            stock=5,
            ubicacion_planograma="Pasillo 4 - Estante A - Nivel 1",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/omeprazol-leti.jpg",
        ),
        Producto(
            sku="MED-0042",
            codigo_barras="7591234500420",
            nombre="Omeprazol Suspensión 20mg/5ml",
            principio_activo="Omeprazol",
            categoria="Inhibidor de bomba de protones",
            descripcion="Presentación líquida del inhibidor de bomba de protones para pacientes con dificultad para tragar cápsulas.",
            laboratorio="Elmor",
            pais_origen="Venezuela",
            precio=7.00,
            stock=0,
            ubicacion_planograma="Pasillo 4 - Estante A - Nivel 2",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/omeprazol-suspension.jpg",
        ),
        # ---------------------------------------------------------------
        # Diclofenac
        # ---------------------------------------------------------------
        Producto(
            sku="MED-0050",
            codigo_barras="7591234500505",
            nombre="Diclofenac Sódico 50mg x10 Tabletas",
            principio_activo="Diclofenac",
            categoria="Antiinflamatorio no esteroideo",
            descripcion="Antiinflamatorio no esteroideo (AINE) para dolor e inflamación musculoesquelética.",
            laboratorio="Vargas",
            pais_origen="Venezuela",
            precio=4.60,
            stock=14,
            ubicacion_planograma="Pasillo 2 - Estante B - Nivel 2",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/diclofenac-50.jpg",
        ),
        Producto(
            sku="MED-0051",
            codigo_barras="7591234500512",
            nombre="Diclofenac Gel Tópico 1% x30g",
            principio_activo="Diclofenac",
            categoria="Antiinflamatorio no esteroideo",
            descripcion="Gel de uso tópico para dolor e inflamación localizados (golpes, esguinces, dolor muscular).",
            laboratorio="Genven",
            pais_origen="Venezuela",
            precio=6.80,
            stock=7,
            ubicacion_planograma="Pasillo 2 - Estante B - Nivel 3",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/diclofenac-gel.jpg",
        ),
        # ---------------------------------------------------------------
        # Vitamina C / Ácido ascórbico
        # ---------------------------------------------------------------
        Producto(
            sku="MED-0060",
            codigo_barras="7591234500604",
            nombre="Vitamina C 1g Efervescente x10 Tabletas",
            principio_activo="Ácido Ascórbico",
            categoria="Suplemento vitamínico",
            descripcion="Suplemento vitamínico que apoya el sistema inmunológico y actúa como antioxidante.",
            laboratorio="Calox",
            pais_origen="Venezuela",
            precio=3.90,
            stock=25,
            ubicacion_planograma="Pasillo 4 - Estante C - Nivel 1",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/vitamina-c-efervescente.jpg",
        ),
        Producto(
            sku="MED-0061",
            codigo_barras="7591234500611",
            nombre="Ácido Ascórbico Masticable 500mg x30",
            principio_activo="Ácido Ascórbico",
            categoria="Suplemento vitamínico",
            descripcion="Suplemento vitamínico masticable que apoya el sistema inmunológico y actúa como antioxidante.",
            laboratorio="Behrens",
            pais_origen="Venezuela",
            precio=3.30,
            stock=0,
            ubicacion_planograma="Pasillo 4 - Estante C - Nivel 1",
            sucursal=SUCURSAL,
            imagen_url="https://example-farmacia.com/img/vitamina-c-masticable.jpg",
        ),
    ]

    db.add_all(productos_demo)
    db.commit()


def init_db() -> None:
    """Crea las tablas (si no existen) y siembra datos de demostración."""
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        _sembrar_datos(db)
    finally:
        db.close()
