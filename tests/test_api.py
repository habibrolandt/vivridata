import os

os.environ["DATABASE_URL"] = "sqlite:///./test_vivridata.db"
os.environ["API_KEY"] = "cle-de-test"
if os.path.exists("test_vivridata.db"):
    os.remove("test_vivridata.db")

from fastapi.testclient import TestClient  # noqa: E402
from app.main import app  # noqa: E402


def client():
    return TestClient(app)


def test_sondes_et_metriques():
    with client() as c:
        assert c.get("/health").json()["status"] == "ok"
        assert c.get("/api/info").json()["app"] == "VivriData CI"
        c.get("/api/produits")
        assert "http_requests_total" in c.get("/metrics").text


def test_donnees_initiales_et_statistiques():
    with client() as c:
        resume = c.get("/api/stats/resume").json()
        assert resume["produits"] == 10 and resume["marches"] == 7 and resume["releves"] == 700
        pid = c.get("/api/produits").json()[0]["id"]
        evo = c.get(f"/api/stats/evolution?produit_id={pid}").json()
        assert len(evo["serie"]) == 10 and evo["variation_pct"] is not None
        par_marche = c.get(f"/api/stats/prix-par-marche?produit_id={pid}").json()
        assert len(par_marche["marches"]) == 7


def test_saisie_protegee_par_cle_api():
    with client() as c:
        pid = c.get("/api/produits").json()[0]["id"]
        mid = c.get("/api/marches").json()[0]["id"]
        body = {"produit_id": pid, "marche_id": mid, "prix": 600}
        assert c.post("/api/releves", json=body).status_code == 401
        assert c.post("/api/releves", json=body, headers={"X-API-Key": "mauvaise"}).status_code == 401
        r = c.post("/api/releves", json=body, headers={"X-API-Key": "cle-de-test"})
        assert r.status_code == 201 and r.json()["source"] == "agent"
        assert c.get("/api/releves?limit=1").json()[0]["id"] == r.json()["id"]


def test_validation_et_export():
    with client() as c:
        bad = {"produit_id": 1, "marche_id": 1, "prix": -10}
        assert c.post("/api/releves", json=bad, headers={"X-API-Key": "cle-de-test"}).status_code == 422
        assert c.post("/api/releves", json={"produit_id": 999, "marche_id": 1, "prix": 10},
                      headers={"X-API-Key": "cle-de-test"}).status_code == 404
        csv = c.get("/api/export.csv")
        assert csv.status_code == 200 and csv.text.startswith("date;produit")
