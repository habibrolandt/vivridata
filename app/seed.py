"""Données de démonstration SIMULÉES (pas de vrais prix officiels).

Elles servent uniquement à alimenter le tableau de bord au premier démarrage.
En production, les relevés viennent des agents de collecte via POST /api/releves.
"""
import random
from datetime import date, timedelta

MARCHES = [
    ("Adjamé", "Abidjan"), ("Yopougon Siporex", "Abidjan"), ("Treichville", "Abidjan"),
    ("Grand marché de Bouaké", "Bouaké"), ("Marché de Daloa", "Daloa"),
    ("Marché de Korhogo", "Korhogo"), ("Marché de San-Pédro", "San-Pédro"),
]

# (nom, unité, catégorie, prix de base simulé en FCFA, tendance hebdo en %)
PRODUITS = [
    ("Riz local", "kg", "Céréales", 550, 0.6),
    ("Riz importé", "kg", "Céréales", 475, 0.3),
    ("Maïs grain", "kg", "Céréales", 250, -0.4),
    ("Attiéké", "kg", "Tubercules", 400, 0.8),
    ("Igname", "kg", "Tubercules", 450, -0.6),
    ("Banane plantain", "kg", "Tubercules", 350, 1.2),
    ("Tomate", "kg", "Légumes", 700, 2.0),
    ("Oignon", "kg", "Légumes", 600, 1.0),
    ("Huile de palme", "litre", "Huiles", 1100, 0.4),
    ("Poisson chinchard", "kg", "Protéines", 1500, 0.5),
]

SEMAINES = 10


def seed_database(db, Marche, Produit, Releve) -> None:
    if db.query(Produit).count() > 0:
        return
    rng = random.Random(2026)
    marches = [Marche(nom=n, ville=v) for n, v in MARCHES]
    produits = [Produit(nom=n, unite=u, categorie=c) for n, u, c, _, _ in PRODUITS]
    db.add_all(marches + produits)
    db.flush()

    # écart de prix aléatoire propre à chaque marché (simulation)
    ecart_marche = {m.id: rng.uniform(-0.12, 0.12) for m in marches}
    today = date.today()
    lundi = today - timedelta(days=today.weekday())
    releves = []
    for (nom, _, _, base, tendance), p in zip(PRODUITS, produits):
        for semaine in range(SEMAINES, 0, -1):
            # un relevé par semaine calendaire, jamais dans le futur
            jour = min(today, lundi - timedelta(weeks=semaine - 1) + timedelta(days=rng.randint(0, 3)))
            facteur_temps = (1 + tendance / 100) ** (SEMAINES - semaine)
            for m in marches:
                prix = base * facteur_temps * (1 + ecart_marche[m.id]) * rng.uniform(0.95, 1.05)
                releves.append(Releve(produit_id=p.id, marche_id=m.id, prix=int(round(prix / 5) * 5),
                                      date_releve=jour, source="simulation"))
    db.add_all(releves)
    db.commit()
