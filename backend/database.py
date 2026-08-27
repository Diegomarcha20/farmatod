"""
Capa de acceso a datos. Define el modelo Producto (SKU, principio activo,
ubicacion en el planograma, stock local, etc.) sobre SQLite + SQLAlchemy,
y siembra datos de ejemplo la primera vez que se crea la base.
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
    """Inserta un catálogo inicial de ejemplo si la tabla está vacía."""
    if db.query(Producto).first() is not None:
        return

    productos_demo = [
        Producto(
            sku="MED-0001",
            codigo_barras="7591234500017",
            nombre="Paracetamol 500mg x20 Tabletas",
            principio_activo="Paracetamol",
            categoria="Analgésico / Antipirético",
            descripcion="Alivio del dolor leve a moderado y reducción de la fiebre.",
            precio=3.50,
            stock=42,
            ubicacion_planograma="Pasillo 2 - Estante A - Nivel 3",
            sucursal="Arbolitos, San Cristóbal",
            imagen_url="https://example-farmacia.com/img/paracetamol-500.jpg",
        ),
        Producto(
            sku="MED-0002",
            codigo_barras="7591234500024",
            nombre="Acetaminofén Genérico 500mg x20",
            principio_activo="Paracetamol",
            categoria="Analgésico / Antipirético",
            descripcion="Alternativa genérica de paracetamol de alta rotación.",
            precio=2.10,
            stock=0,
            ubicacion_planograma="Pasillo 2 - Estante A - Nivel 4",
            sucursal="Arbolitos, San Cristóbal",
            imagen_url="https://example-farmacia.com/img/acetaminofen-generico.jpg",
        ),
        Producto(
            sku="MED-0010",
            codigo_barras="7591234500109",
            nombre="Ibuprofeno 400mg x10 Tabletas",
            principio_activo="Ibuprofeno",
            categoria="Antiinflamatorio no esteroideo",
            descripcion="Antiinflamatorio, analgésico y antipirético.",
            precio=4.20,
            stock=0,
            ubicacion_planograma="Pasillo 2 - Estante B - Nivel 1",
            sucursal="Arbolitos, San Cristóbal",
            imagen_url="https://example-farmacia.com/img/ibuprofeno-400.jpg",
        ),
        Producto(
            sku="MED-0011",
            codigo_barras="7591234500116",
            nombre="Ibuprofeno Suspensión Infantil 100mg/5ml",
            principio_activo="Ibuprofeno",
            categoria="Antiinflamatorio no esteroideo",
            descripcion="Presentación pediátrica en jarabe.",
            precio=6.75,
            stock=15,
            ubicacion_planograma="Pasillo 5 - Estante Infantil - Nivel 2",
            sucursal="Arbolitos, San Cristóbal",
            imagen_url="https://example-farmacia.com/img/ibuprofeno-jarabe.jpg",
        ),
        Producto(
            sku="MED-0020",
            codigo_barras="7591234500208",
            nombre="Loratadina 10mg x10 Tabletas",
            principio_activo="Loratadina",
            categoria="Antihistamínico",
            descripcion="Tratamiento de síntomas alérgicos, no causa somnolencia.",
            precio=5.00,
            stock=8,
            ubicacion_planograma="Pasillo 3 - Estante C - Nivel 2",
            sucursal="Arbolitos, San Cristóbal",
            imagen_url="https://example-farmacia.com/img/loratadina-10.jpg",
        ),
        Producto(
            sku="MED-0021",
            codigo_barras="7591234500215",
            nombre="Cetirizina 10mg x10 Tabletas",
            principio_activo="Loratadina",
            categoria="Antihistamínico",
            descripcion="Alternativa antihistamínica de segunda generación.",
            precio=5.50,
            stock=20,
            ubicacion_planograma="Pasillo 3 - Estante C - Nivel 3",
            sucursal="Arbolitos, San Cristóbal",
            imagen_url="https://example-farmacia.com/img/cetirizina-10.jpg",
        ),
        Producto(
            sku="MED-0030",
            codigo_barras="7591234500307",
            nombre="Amoxicilina 500mg x12 Cápsulas",
            principio_activo="Amoxicilina",
            categoria="Antibiótico",
            descripcion="Antibiótico betalactámico de amplio espectro. Requiere receta.",
            precio=8.90,
            stock=6,
            ubicacion_planograma="Pasillo 1 - Estante Controlados - Nivel 1",
            sucursal="Arbolitos, San Cristóbal",
            imagen_url="https://example-farmacia.com/img/amoxicilina-500.jpg",
        ),
        Producto(
            sku="MED-0040",
            codigo_barras="7591234500406",
            nombre="Omeprazol 20mg x14 Cápsulas",
            principio_activo="Omeprazol",
            categoria="Inhibidor de bomba de protones",
            descripcion="Tratamiento de acidez, gastritis y reflujo.",
            precio=4.80,
            stock=30,
            ubicacion_planograma="Pasillo 4 - Estante A - Nivel 1",
            sucursal="Arbolitos, San Cristóbal",
            imagen_url="https://example-farmacia.com/img/omeprazol-20.jpg",
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
