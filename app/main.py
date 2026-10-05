"""VivriData CI — Observatoire des prix des produits vivriers en Côte d'Ivoire.

Des agents de collecte saisissent les prix relevés sur les marchés ;
l'API les stocke dans PostgreSQL et les expose sous forme de statistiques,
d'un tableau de bord et d'un export CSV.

Endpoints principaux
  GET  /                               tableau de bord web
  GET  /health                         santé de l'app et de la base (sondes)
  GET  /metrics                        métriques Prometheus
  GET  /api/info                       instance qui répond (démo de répartition de charge)
  GET  /api/produits | /api/marches    référentiels
  GET  /api/releves                    derniers relevés
  POST /api/releves                    nouveau relevé (en-tête X-API-Key obligatoire)
  GET  /api/stats/resume               indicateurs clés
  GET  /api/stats/prix-par-marche      prix moyen récent par marché pour un produit
  GET  /api/stats/evolution            évolution hebdomadaire nationale d'un produit
  GET  /api/export.csv                 export des relevés
"""
import csv
import io
import os
import socket
import time
from collections import defaultdict
from contextlib import asynccontextmanager
from datetime import date, timedelta
from typing import Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field
from sqlalchemy import Column, Date, ForeignKey, Integer, String, create_engine, func, text
from sqlalchemy.orm import Session, declarative_base, sessionmaker

from app.seed import seed_database

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./vivridata.db")
API_KEY = os.getenv("API_KEY", "demo-key-local")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
ENVIRONMENT = os.getenv("ENVIRONMENT", "local")
STARTED_AT = time.time()

connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, pool_pre_ping=True, connect_args=connect_args)
SessionLocal = sessionmaker(bind=engine)
Base = declarative_base()


class Marche(Base):
    __tablename__ = "marches"
    id = Column(Integer, primary_key=True)
    nom = Column(String(80), nullable=False, unique=True)
    ville = Column(String(60), nullable=False)


class Produit(Base):
    __tablename__ = "produits"
    id = Column(Integer, primary_key=True)
    nom = Column(String(80), nullable=False, unique=True)
    unite = Column(String(20), nullable=False)
    categorie = Column(String(40), nullable=False)


class Releve(Base):
    __tablename__ = "releves"
    id = Column(Integer, primary_key=True)
    produit_id = Column(Integer, ForeignKey("produits.id"), nullable=False, index=True)
    marche_id = Column(Integer, ForeignKey("marches.id"), nullable=False, index=True)
    prix = Column(Integer, nullable=False)  # FCFA par unité
    date_releve = Column(Date, nullable=False, index=True)
    source = Column(String(40), nullable=False, default="agent")


class ReleveIn(BaseModel):
    produit_id: int
    marche_id: int
    prix: int = Field(gt=0, le=1_000_000)
    date_releve: Optional[date] = None
    source: str = Field(default="agent", max_length=40)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def require_api_key(x_api_key: Optional[str] = Header(default=None)):
    if x_api_key != API_KEY:
        raise HTTPException(401, "Clé API invalide ou absente")


def init_db(retries: int = 15) -> None:
    """La base peut démarrer après l'application : on réessaie."""
    for attempt in range(retries):
        try:
            Base.metadata.create_all(bind=engine)
            return
        except Exception:
            if attempt == retries - 1:
                raise
            time.sleep(2)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    init_db()
    with SessionLocal() as db:
        try:
            seed_database(db, Marche, Produit, Releve)
        except Exception:
            # Plusieurs répliques démarrent en même temps : une seule réussit l'amorçage.
            db.rollback()
    yield


app = FastAPI(title="VivriData CI", version=APP_VERSION, lifespan=lifespan)
Instrumentator(excluded_handlers=["/metrics", "/health"]).instrument(app).expose(app, include_in_schema=False)
app.mount("/static", StaticFiles(directory=os.path.join(os.path.dirname(__file__), "static")), name="static")


# ---------------------------------------------------------------- pages et sondes
@app.get("/", include_in_schema=False)
def index():
    return FileResponse(os.path.join(os.path.dirname(__file__), "static", "index.html"))


@app.get("/health")
def health():
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "ok", "database": "up"}
    except Exception:
        raise HTTPException(503, {"status": "degraded", "database": "down"})


@app.get("/api/info")
def info():
    return {
        "app": "VivriData CI",
        "version": APP_VERSION,
        "environment": ENVIRONMENT,
        "instance": socket.gethostname(),
        "database": "PostgreSQL" if DATABASE_URL.startswith("postgres") else "SQLite",
        "uptime_seconds": int(time.time() - STARTED_AT),
    }


# ---------------------------------------------------------------- référentiels
@app.get("/api/produits")
def list_produits(db: Session = Depends(get_db)):
    return [{"id": p.id, "nom": p.nom, "unite": p.unite, "categorie": p.categorie}
            for p in db.query(Produit).order_by(Produit.nom)]


@app.get("/api/marches")
def list_marches(db: Session = Depends(get_db)):
    return [{"id": m.id, "nom": m.nom, "ville": m.ville} for m in db.query(Marche).order_by(Marche.nom)]


# ---------------------------------------------------------------- relevés
def _releve_dict(r, produit, marche):
    return {"id": r.id, "produit": produit.nom, "unite": produit.unite, "marche": marche.nom,
            "ville": marche.ville, "prix": r.prix, "date_releve": r.date_releve.isoformat(), "source": r.source}


@app.get("/api/releves")
def list_releves(produit_id: Optional[int] = None, marche_id: Optional[int] = None,
                 limit: int = Query(20, ge=1, le=500), db: Session = Depends(get_db)):
    q = db.query(Releve, Produit, Marche).join(Produit).join(Marche)
    if produit_id:
        q = q.filter(Releve.produit_id == produit_id)
    if marche_id:
        q = q.filter(Releve.marche_id == marche_id)
    rows = q.order_by(Releve.date_releve.desc(), Releve.id.desc()).limit(limit)
    return [_releve_dict(r, p, m) for r, p, m in rows]


@app.post("/api/releves", status_code=201, dependencies=[Depends(require_api_key)])
def create_releve(payload: ReleveIn, db: Session = Depends(get_db)):
    produit = db.get(Produit, payload.produit_id)
    marche = db.get(Marche, payload.marche_id)
    if not produit or not marche:
        raise HTTPException(404, "Produit ou marché inconnu")
    r = Releve(produit_id=produit.id, marche_id=marche.id, prix=payload.prix,
               date_releve=payload.date_releve or date.today(), source=payload.source)
    db.add(r)
    db.commit()
    db.refresh(r)
    return _releve_dict(r, produit, marche)


# ---------------------------------------------------------------- statistiques
def _week_start(d: date) -> date:
    return d - timedelta(days=d.weekday())


@app.get("/api/stats/resume")
def stats_resume(db: Session = Depends(get_db)):
    return {
        "releves": db.query(func.count(Releve.id)).scalar(),
        "marches": db.query(func.count(Marche.id)).scalar(),
        "produits": db.query(func.count(Produit.id)).scalar(),
        "derniere_mise_a_jour": (db.query(func.max(Releve.date_releve)).scalar() or date.today()).isoformat(),
    }


@app.get("/api/stats/prix-par-marche")
def prix_par_marche(produit_id: int, jours: int = Query(14, ge=1, le=365), db: Session = Depends(get_db)):
    produit = db.get(Produit, produit_id)
    if not produit:
        raise HTTPException(404, "Produit inconnu")
    depuis = date.today() - timedelta(days=jours)
    rows = (db.query(Marche.nom, func.avg(Releve.prix), func.count(Releve.id))
            .join(Releve, Releve.marche_id == Marche.id)
            .filter(Releve.produit_id == produit_id, Releve.date_releve >= depuis)
            .group_by(Marche.nom).order_by(Marche.nom).all())
    return {"produit": produit.nom, "unite": produit.unite, "periode_jours": jours,
            "marches": [{"marche": n, "prix_moyen": round(float(a)), "nb_releves": c} for n, a, c in rows]}


@app.get("/api/stats/evolution")
def evolution(produit_id: int, db: Session = Depends(get_db)):
    produit = db.get(Produit, produit_id)
    if not produit:
        raise HTTPException(404, "Produit inconnu")
    semaines = defaultdict(list)
    for prix, d in db.query(Releve.prix, Releve.date_releve).filter(Releve.produit_id == produit_id):
        semaines[_week_start(d)].append(prix)
    serie = [{"semaine": s.isoformat(), "prix_moyen": round(sum(v) / len(v))} for s, v in sorted(semaines.items())]
    variation = None
    if len(serie) >= 2 and serie[0]["prix_moyen"]:
        variation = round(100 * (serie[-1]["prix_moyen"] - serie[0]["prix_moyen"]) / serie[0]["prix_moyen"], 1)
    return {"produit": produit.nom, "unite": produit.unite, "serie": serie, "variation_pct": variation}


@app.get("/api/export.csv")
def export_csv(produit_id: Optional[int] = None, db: Session = Depends(get_db)):
    q = db.query(Releve, Produit, Marche).join(Produit).join(Marche)
    if produit_id:
        q = q.filter(Releve.produit_id == produit_id)
    buf = io.StringIO()
    w = csv.writer(buf, delimiter=";")
    w.writerow(["date", "produit", "unite", "marche", "ville", "prix_fcfa", "source"])
    for r, p, m in q.order_by(Releve.date_releve, Releve.id):
        w.writerow([r.date_releve.isoformat(), p.nom, p.unite, m.nom, m.ville, r.prix, r.source])
    buf.seek(0)
    return StreamingResponse(iter([buf.getvalue()]), media_type="text/csv; charset=utf-8",
                             headers={"Content-Disposition": "attachment; filename=vivridata_releves.csv"})
