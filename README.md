# spotify-KG — Spotify Knowledge Graph

**DIS18, Gruppe 6** · Johnson Gaspar Baptista, Noah Anton Müller

Eine Pipeline, die über die Spotify Web API Künstler und Tracks sammelt, daraus
in **Neo4j** einen Knowledge Graph aufbaut und ein **Kollaborationsnetzwerk**
zwischen Künstlern ableitet:

```
Spotify Web API ──> spotify_client.py ──> main.py ──> neo4j_loader.py ──> Neo4j
   (Suche)           (Fetch + Retry)     (Pipeline)     (Batch-Load)     (Graph)
```

**Datenmodell:**

```
(:Artist {id, name, uri, seed, …})-[:PERFORMED_ON]->(:Track {id, name, release_date, uri, …})
(:Artist)-[:COLLABORATED_WITH {track_ids}]-(:Artist)   ← abgeleitet aus gemeinsamen Tracks
```

`seed=true` sind die per Genre-Suche gesammelten Kern-Artists; `seed=false`
sind Feature-Artists, die über gemeinsame Tracks entdeckt und ohne zusätzliche
API-Requests als Knoten angelegt werden.

> **Hinweis Development-Mode:** Der Spotify-Zugang liefert keine
> `popularity`/`followers`/`genres`-Werte (immer 0 bzw. leer). Der Kern des
> Graphen ist das Kollaborationsnetzwerk — Details in [DOKUMENTATION.md](DOKUMENTATION.md).

---

## Voraussetzungen

| Was | Details |
|---|---|
| Python ≥ 3.11 | mit venv (`.venv/` im Projekt) |
| Neo4j ≥ 5.x | lokal auf `neo4j://127.0.0.1:7687`, Browser auf http://localhost:7474 (getestet mit 2026.06 Community) |
| Spotify-App | Client-ID/Secret aus dem [Developer Dashboard](https://developer.spotify.com/dashboard) |

**GDS/APOC werden nicht benötigt** — alle Demo-Queries laufen mit purem Cypher.

## Setup

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

`.env` im Projektverzeichnis anlegen (wird **nicht** committet):

```
SPOTIFY_CLIENT_ID=...
SPOTIFY_CLIENT_SECRET=...
NEO4J_PASSWORD=...
```

Neo4j starten (Neo4j Desktop: Instanz starten, oder `neo4j start`) und warten,
bis http://localhost:7474 erreichbar ist.

## Vollständiger Durchlauf

```bash
.venv/bin/python main.py
```

Keine Parameter nötig — die Stellschrauben (`TOP_N_ARTISTS`, `TRACK_SEARCH_PAGES`,
`MAX_REQUEST_BUDGET`) liegen in [config.py](config.py).

**Ablauf und erwartete Laufzeit (Default-Konfiguration, 150 Artists):**

| Phase | Was passiert | Dauer |
|---|---|---|
| 0/4 | Budget-Check + Quota-Probe (bricht ab, **bevor** etwas gelöscht wird) | Sekunden |
| 1/4 | Artists per Genre-Suche sammeln (round-robin über 12 Genres) | ~10 s |
| 2/4 | Tracks pro Artist per Suche holen (**längste Phase**, Fortschrittsbalken) | ~3–4 min |
| 3/4 | Datenbank leeren + Batch-Load nach Neo4j | Sekunden |
| 4/4 | `COLLABORATED_WITH` in der Datenbank ableiten | Sekunden |

**Gesamt: ca. 4–5 Minuten.** Einzelne `Netzwerk-Timeout — wiederhole …`- oder
`Rate limited …`-Meldungen sind **kein Fehler**: Der betroffene Request wird
automatisch wiederholt, der Lauf läuft weiter. Abgebrochen wird nur bei
erschöpfter Tages-Quota (klare `=== ABBRUCH`-Meldung) — in dem Fall bleibt die
Datenbank unverändert.

### Woran erkenne ich einen erfolgreichen Lauf?

1. Konsole/`run.log` endet mit `=== Lauf ERFOLGREICH abgeschlossen ===` plus Statistik.
2. `last_run_stats.json` existiert und enthält Zeitstempel + Knoten-/Kantenzahlen
   (wird **nur** nach vollständigem Lauf geschrieben).
3. Gegenprobe in Neo4j (http://localhost:7474):
   ```cypher
   MATCH (n) RETURN labels(n)[0] AS typ, count(*) AS anzahl;
   ```

### Schutzmechanismen

- **Kein Doppelstart:** Eine Lock-Datei (`.run.lock`) verhindert parallele Läufe
  (ein zweiter Lauf würde die Datenbank mitten im ersten leeren).
- **Request-Timeout (15 s)** + automatischer Retry bei Netzwerkfehlern.
- **Quota-Schutz:** Budget-Schätzung + 1-Request-Probe vor dem Start; die
  Datenbank wird erst geleert, wenn alle Daten vollständig geholt sind.

## Demo & Analyse

- **[docs/demo_queries.cypher](docs/demo_queries.cypher)** — kommentierte
  Cypher-Queries für die Präsentation (Überblick, Top-Kollaborateure,
  Teilgraphen, Pfade).
- **[docs/presentation_plan.md](docs/presentation_plan.md)** — Ablaufplan für
  die Live-Demo.
- [queries.cypher](queries.cypher) — ältere/vollständige Query-Sammlung.

> **Visualisierungs-Limit:** Der Neo4j Browser rendert standardmäßig nicht
> beliebig viele Elemente (Einstellung „Visualization node limit", Default 1000).
> Das ist ein reines Anzeige-Limit des Browsers — die Datenbank enthält immer
> alle Daten. Für die Demo sind gezielte Teilgraph-Queries (siehe
> `docs/demo_queries.cypher`) ohnehin aussagekräftiger als ein Voll-Rendering.

## Tests

```bash
.venv/bin/python -m unittest discover tests
```

Testet die netzwerkfreie Logik: Request-Schätzung, Artist-Mapping,
Retry-/Timeout-Verhalten, Lock-Mechanismus.

## Projektstruktur

```
main.py               Pipeline-Orchestrierung (Einstiegspunkt)
spotify_client.py     Spotify-API-Zugriff, Retry-/Quota-Logik
neo4j_loader.py       Neo4j-Persistenz (Constraints, Batch-Load, Ableitung)
config.py             Alle Stellschrauben
queries.cypher        Analyse-Queries (Sammlung)
docs/                 Demo-Queries, Präsentationsplan, Anforderungs-Check
tests/                Unit-Tests (ohne Netzwerk/DB lauffähig)
DOKUMENTATION.md      Entwicklungsgeschichte & API-Einschränkungen
```
