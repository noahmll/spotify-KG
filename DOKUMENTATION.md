# Spotify Knowledge Graph – Dokumentation der Pipeline-Änderungen

**DIS18 – Gruppe 6**
Mitglieder: Johnson Gaspar Baptista, Noah Anton Müller

Diese Datei fasst zusammen, wie die Artist-Sammlung der Pipeline ursprünglich
funktionierte, welchen Optimierungsweg wir zwischendurch ausprobiert (und wieder
verworfen) haben, und wie die aktuelle, effizientere Lösung arbeitet.

---

## 1. Alter Stand

Die Pipeline sammelt Künstler über die **Genre-Suche** der Spotify Web API
(8 Seed-Genres: pop, hip-hop, rock, latin, r-n-b, electronic, country, k-pop),
lädt pro Künstler dessen Tracks und leitet daraus ein Kollaborationsnetzwerk in
Neo4j ab (`Artist -[:PERFORMED_ON]-> Track`, daraus `COLLABORATED_WITH`).

Für die Auswahl der „Top N" Künstler wurde **jedes Genre vollständig durchsucht**
(je 20 Such-Seiten à 10 Treffer = bis zu 160 Anfragen), alle ~1.000 gefundenen
Künstler eingesammelt, **nach Followerzahl sortiert** und die ersten 50 behalten.
Followers diente als Ranking-Ersatz, weil die `popularity` in Suchergebnissen als
unzuverlässig galt.

**Problem:** Es wurden immer ~1.000 Künstler beschafft, nur um 50 zu behalten –
unabhängig davon, wie viele tatsächlich gebraucht wurden.

## 2. Verworfenes Experiment

Wir wollten die Anfragen senken und das Ranking verbessern und probierten drei
Hebel aus der API-Dokumentation:

- **`limit=50`** statt `limit=10` bei der Suche (weniger Seiten),
- **Batch-Abruf** `GET /v1/artists?ids=` (50 Künstler in 1 Anfrage, mit echter
  popularity/followers),
- **`GET /v1/artists/{id}/top-tracks`** statt Track-Suche.

**Das funktionierte nicht.** Tests gegen die Live-API zeigten, dass unser Account
im **Development-Mode** stärker eingeschränkt ist, als die Doku angibt
(Verschärfungen von Spotify ab Nov 2024 / Feb 2026):

- `limit > 10` → `400 Invalid limit`,
- `/artists?ids=` und `/top-tracks` → `403 Forbidden`,
- und entscheidend: **`popularity`, `followers` und `genres` kommen über jeden
  Endpoint als `null` zurück.** Eine Sortierung nach Followern oder Popularität
  ist also gar nicht möglich – die Felder existieren für uns nicht.

Damit war klar: Das ursprüngliche Follower-Ranking war faktisch wirkungslos
(es sortierte lauter Nullen), und unsere Optimierung über andere Endpoints ist
für unseren Zugang gesperrt.

## 3. Aktueller Stand – was jetzt anders ist

Da es **kein Ranking-Kriterium** gibt, müssen wir auch keinen großen Pool
beschaffen, um daraus auszuwählen. Die Sammlung wurde deshalb auf **Round-Robin
mit Early-Stop** umgestellt (`get_seed_artists(sp, target)`):

- Es wird abwechselnd je eine Suchseite (10 Treffer) pro Genre geholt,
- doppelte Künstler werden über die ID herausgefiltert,
- und **sobald `target` eindeutige Künstler erreicht sind, stoppt die Sammlung**.

Dadurch wird nur noch beschafft, was tatsächlich gebraucht wird, **balanciert über
alle Genres**. Die Auswahl entspricht nun ehrlich Spotifys
**Such-Relevanz-Reihenfolge** statt einem scheinbaren Follower-Ranking.

**Effekt (bei 50 Künstlern):** Die Sammelphase sank von **160 auf ~8–16 Anfragen**;
das Gesamtbudget von ~410 auf ~260. Die Künstlerzahl (`TOP_N_ARTISTS`) und die
Track-Tiefe (`TRACK_SEARCH_PAGES`) sind jetzt in `config.py` einstellbar, sodass
größere Läufe gezielt skaliert werden können.

Begleitend wurde aufgeräumt: irreführende „0 Follower"-Ausgaben entfernt, ungenutzte
Konfiguration gelöscht und in `queries.cypher` die funktionierenden
Kollaborations-Queries (Degree Centrality, kürzeste Pfade, Community-Detection) nach
vorne gestellt, während popularity-/genre-abhängige Abfragen klar als „nur mit
Extended Access" markiert sind. Der eigentliche Wert des Graphen liegt im
**Kollaborationsnetzwerk**, das im Development-Mode vollständig erhalten bleibt.
