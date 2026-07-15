// ============================================================
// Spotify Knowledge Graph — Analyse-Queries
// Ausführen im Neo4j Browser: http://localhost:7474
//
// Alle Queries laufen mit purem Cypher (kein GDS/APOC nötig) und
// sind RUN-UNABHÄNGIG: sie wählen Artists dynamisch (z. B. den am
// stärksten vernetzten Hub) statt fester Namen und funktionieren
// daher mit jedem Datenbestand.
//
// DATENMODELL: Artist-Knoten tragen ein seed-Flag:
//   seed=true  → per Genre-Suche gesammelter Kern
//   seed=false → Feature-Artists, über gemeinsame Tracks entdeckt
// Kanten: (Artist)-[:PERFORMED_ON]->(Track) und daraus abgeleitet
//   (Artist)-[:COLLABORATED_WITH]-(Artist) mit Property track_ids.
//
// VISUALISIERUNG: Der Neo4j Browser rendert per Default max. ~1.000
// Knoten ("Visualization node limit" im Settings-Drawer). Graph-
// Queries hier liefern bewusst lesbare Teilgraphen.
// ============================================================


// ------------------------------------------------------------
// 1) ÜBERBLICK: Was ist im Graphen?
// Zeigt: Knoten pro Label und Kanten pro Typ.
// Warum: Erster Beleg für einen vollständigen Lauf; Einstieg ins
// Datenmodell.
// ------------------------------------------------------------
MATCH (n)
RETURN labels(n)[0] AS typ, count(*) AS anzahl
UNION ALL
MATCH ()-[r]->()
RETURN type(r) AS typ, count(*) AS anzahl;

// Zusatz: Seed- vs. Feature-Artists getrennt zählen
MATCH (a:Artist)
RETURN CASE WHEN a.seed THEN 'Seed-Artist (gesucht)'
            ELSE 'Feature-Artist (über Tracks entdeckt)' END AS art,
       count(*) AS anzahl;


// ------------------------------------------------------------
// 2) TOP-KOLLABORATEURE (Degree Centrality)
// Zeigt: Die am stärksten vernetzten Artists nach Anzahl direkter
// Kollaborationsbeziehungen.
// Warum: Kernergebnis — wer ist im Netzwerk am aktivsten verlinkt?
// ------------------------------------------------------------
MATCH (a:Artist)-[:COLLABORATED_WITH]-()
RETURN a.name AS artist, count(*) AS kollaborationen
ORDER BY kollaborationen DESC
LIMIT 10;


// ------------------------------------------------------------
// 3) EGO-GRAPH DES TOP-HUBS (Visualisierung!)
// Zeigt: Den am stärksten vernetzten Artist mit seiner direkten
// Nachbarschaft UND den Verbindungen der Nachbarn untereinander.
// -> Als Graph-Ansicht ausführen.
// Warum: Lesbare Visualisierung mit echter Cluster-Struktur; der
// Hub wird dynamisch bestimmt (kein fester Name).
// ------------------------------------------------------------
MATCH (hub:Artist)-[:COLLABORATED_WITH]-()
WITH hub, count(*) AS deg ORDER BY deg DESC LIMIT 1
MATCH p = (hub)-[:COLLABORATED_WITH]-(nachbar:Artist)
OPTIONAL MATCH q = (nachbar)-[:COLLABORATED_WITH]-(anderer:Artist)
WHERE (anderer)-[:COLLABORATED_WITH]-(hub)
RETURN p, q;


// ------------------------------------------------------------
// 4) STÄRKSTE KOLLABORATIONS-PAARE (Kantengewicht)
// Zeigt: Artist-Paare mit den meisten gemeinsamen Tracks — das
// Gewicht steckt als track_ids-Liste auf der Kante.
// Warum: Demonstriert Properties AUF Beziehungen (Merkmal des
// Property-Graph-Modells).
// ------------------------------------------------------------
MATCH (a:Artist)-[c:COLLABORATED_WITH]-(b:Artist)
WHERE a.name < b.name
RETURN a.name AS artist_1, b.name AS artist_2,
       size(c.track_ids) AS gemeinsame_tracks
ORDER BY gemeinsame_tracks DESC
LIMIT 10;


// ------------------------------------------------------------
// 5) WIE VIELE GETRENNTE NETZWERKE GIBT ES? (Connected Components)
// Zeigt: Anzahl voneinander unabhängiger Kollaborations-Netzwerke.
// Methode (rein Cypher, ohne GDS): Jeder vernetzte Artist erhält
// als "Netzwerk-ID" die kleinste elementId, die über beliebig
// lange COLLABORATED_WITH-Pfade erreichbar ist (per shortestPath =
// BFS, terminiert sauber). Gleiche ID = gleiches Netzwerk.
// Warum: Struktureller Gesamtblick — meist eine große Community
// plus mehrere kleine Inseln.
// Hinweis: Läuft auf ~1.000 Knoten in wenigen Sekunden.
// ------------------------------------------------------------
MATCH (a:Artist) WHERE (a)-[:COLLABORATED_WITH]-()
MATCH p = shortestPath((a)-[:COLLABORATED_WITH*]-(b:Artist))
WHERE a <> b
WITH a, min(elementId(b)) AS mb
WITH DISTINCT CASE WHEN mb < elementId(a) THEN mb ELSE elementId(a) END AS netzwerk_id
RETURN count(netzwerk_id) AS anzahl_netzwerke;

// Größenverteilung der Netzwerke (größte zuerst)
MATCH (a:Artist) WHERE (a)-[:COLLABORATED_WITH]-()
MATCH p = shortestPath((a)-[:COLLABORATED_WITH*]-(b:Artist))
WHERE a <> b
WITH a, min(elementId(b)) AS mb
WITH CASE WHEN mb < elementId(a) THEN mb ELSE elementId(a) END AS netzwerk_id
WITH netzwerk_id, count(*) AS groesse
RETURN groesse AS artists_im_netzwerk, count(*) AS anzahl_netzwerke_dieser_groesse
ORDER BY artists_im_netzwerk DESC;


// ------------------------------------------------------------
// 6) LONGEST PATH: Die längste Kollaborationskette
// Zeigt: Zwei weit auseinander liegende Artists und die kürzeste
// Kette zwischen ihnen — nahe am Durchmesser des Netzwerks.
// -> Als Graph-Ansicht ausführen.
// Methode: 2-Sweep-Heuristik (Standardverfahren für Graph-
// Durchmesser, rein Cypher): (1) vom Top-Hub den entferntesten
// Artist u suchen, (2) von u aus den entferntesten Artist v. Der
// Pfad u–v ist eine der längsten Ketten im Graphen.
// Warum: Gegenstück zur Zentralität — wie "gestreckt" ist das
// Netz? Schöne, ungewöhnliche Visualisierung.
// ------------------------------------------------------------
MATCH (h:Artist)-[:COLLABORATED_WITH]-()
WITH h, count(*) AS deg ORDER BY deg DESC LIMIT 1
MATCH p1 = shortestPath((h)-[:COLLABORATED_WITH*..40]-(u:Artist))
WHERE u <> h
WITH u, length(p1) AS d1 ORDER BY d1 DESC LIMIT 1
MATCH p2 = shortestPath((u)-[:COLLABORATED_WITH*..40]-(v:Artist))
WHERE v <> u
WITH p2, length(p2) AS hops ORDER BY hops DESC LIMIT 1
RETURN p2 AS longest_path, hops;


// ------------------------------------------------------------
// 7) KÜRZESTER PFAD zwischen den zwei größten Hubs
// Zeigt: Wie eng die beiden am stärksten vernetzten Artists
// verbunden sind — als Graph-Ansicht ausführen.
// Warum: DIE Signature-Query einer Graphdatenbank; in SQL nur mit
// rekursiven CTEs, in Cypher eine Zeile. Endpunkte dynamisch
// gewählt (kein fester Name).
// ------------------------------------------------------------
MATCH (a:Artist)-[:COLLABORATED_WITH]-()
WITH a, count(*) AS deg ORDER BY deg DESC LIMIT 2
WITH collect(a) AS hubs
WITH hubs[0] AS hub1, hubs[1] AS hub2
MATCH p = shortestPath((hub1)-[:COLLABORATED_WITH*..15]-(hub2))
RETURN p;


// ------------------------------------------------------------
// 8) BRÜCKEN-ARTISTS (Broker im Netzwerk)
// Zeigt: Artists, die viele Paare von Künstlern verbinden, die
// selbst NICHT direkt kollaborieren (Betweenness-Idee, rein
// Cypher ohne GDS).
// Warum: Wer hält das Netzwerk zusammen und vermittelt zwischen
// Subszenen (z. B. EDM ↔ Latin)?
// ------------------------------------------------------------
MATCH (x:Artist)-[:COLLABORATED_WITH]-(mitte:Artist)-[:COLLABORATED_WITH]-(y:Artist)
WHERE x <> y AND NOT (x)-[:COLLABORATED_WITH]-(y)
WITH mitte, count(DISTINCT [x.id, y.id]) AS paare
RETURN mitte.name AS bruecken_artist, paare / 2 AS verbundene_paare
ORDER BY verbundene_paare DESC
LIMIT 10;


// ------------------------------------------------------------
// 9) FEATURE-DICHTESTE TRACKS
// Zeigt: Tracks, auf denen die meisten Artists gemeinsam stehen
// (Mega-Features / Remixe).
// Warum: Verbindet beide Knotentypen und erklärt, WORAUS die
// COLLABORATED_WITH-Kanten abgeleitet werden.
// Hinweis: Derselbe Songtitel kann doppelt auftauchen (mehrere
// Spotify-Releases = mehrere Track-IDs) — Anlass, über Daten-
// qualität zu sprechen.
// ------------------------------------------------------------
MATCH (a:Artist)-[:PERFORMED_ON]->(t:Track)
WITH t, count(a) AS beteiligte, collect(a.name) AS artists
WHERE beteiligte >= 3
RETURN t.name AS track, t.release_date AS datum, beteiligte, artists
ORDER BY beteiligte DESC
LIMIT 10;


// ------------------------------------------------------------
// 10) CLUSTER-VISUALISIERUNG: Das Kollaborationsnetzwerk
// Zeigt: NUR die Artist-Knoten mit ihren Kollaborationskanten
// (ohne die Track-Knoten) — als Graph-Ansicht ausführen.
// Warum: Die richtige Antwort auf das Browser-Anzeige-Limit —
// nicht alles rendern, sondern die aussagekräftige Projektion:
// eine große zusammenhängende Community plus kleine Inseln.
// ------------------------------------------------------------
MATCH p = (:Artist)-[:COLLABORATED_WITH]-(:Artist)
RETURN p;


// ------------------------------------------------------------
// 11) NEUESTE KOLLABORATIONEN (Aktualität der Daten)
// Zeigt: Die jüngsten gemeinsamen Releases im Datenbestand.
// Warum: Beleg, dass die Pipeline aktuelle Daten zieht.
// ------------------------------------------------------------
MATCH (a1:Artist)-[:PERFORMED_ON]->(t:Track)<-[:PERFORMED_ON]-(a2:Artist)
WHERE a1.name < a2.name
WITH t, collect(DISTINCT a1.name) + collect(DISTINCT a2.name) AS beteiligte
RETURN DISTINCT t.name AS track, t.release_date AS datum, beteiligte[0..4] AS artists
ORDER BY datum DESC
LIMIT 10;


// ------------------------------------------------------------
// 12) STICHPROBEN-CHECK: Solo- vs. vernetzte Seed-Artists
// Zeigt: Wie viele der GESUCHTEN Artists (seed=true) im Sample
// (k)eine Kollaboration haben. Feature-Artists haben per
// Konstruktion immer mindestens eine Kollaboration.
// Warum: Ehrliche methodische Einordnung — "solo" heißt nur
// "keine Kollaboration in unseren gesammelten Tracks", nicht
// "hat nie kollaboriert".
// ------------------------------------------------------------
MATCH (a:Artist) WHERE a.seed
RETURN
  CASE WHEN (a)-[:COLLABORATED_WITH]-() THEN 'vernetzt' ELSE 'solo (im Sample)' END AS status,
  count(*) AS anzahl;


// ------------------------------------------------------------
// 13) SIX DEGREES OF SEPARATION (Small-World-Test)
// Zeigt: Für ALLE erreichbaren Artist-Paare die kürzeste
// Kollaborationsdistanz — und wie groß der Anteil ist, der in
// höchstens 6 Schritten verbunden ist.
// Methode: All-Pairs shortestPath (rein Cypher, ohne GDS). Jedes
// Paar wird über elementId(a) < elementId(b) genau einmal gezählt.
// Warum: Prüft die berühmte "Six Degrees"-Hypothese am realen
// Kollaborationsnetz. Ein hoher Anteil ≤ 6 und ein niedriger
// Durchschnitt belegen die Small-World-Eigenschaft.
// Hinweis: Läuft auf ~1.000 Knoten in wenigen Sekunden.
// ------------------------------------------------------------
MATCH (a:Artist) WHERE (a)-[:COLLABORATED_WITH]-()
MATCH p = shortestPath((a)-[:COLLABORATED_WITH*..15]-(b:Artist))
WHERE elementId(a) < elementId(b)
WITH length(p) AS hops
RETURN
  count(*) AS paare_gesamt,
  sum(CASE WHEN hops <= 6 THEN 1 ELSE 0 END) AS innerhalb_6_hops,
  round(100.0 * sum(CASE WHEN hops <= 6 THEN 1 ELSE 0 END) / count(*), 1) AS prozent_innerhalb_6,
  round(avg(hops), 2) AS durchschnitt_hops,
  max(hops) AS max_hops;

// Verteilung der kürzesten Pfadlängen (das "Small-World"-Histogramm)
    MATCH (a:Artist) WHERE (a)-[:COLLABORATED_WITH]-()
    MATCH p = shortestPath((a)-[:COLLABORATED_WITH*..15]-(b:Artist))
    WHERE elementId(a) < elementId(b)
    WITH length(p) AS hops
    RETURN hops, count(*) AS anzahl_paare
    ORDER BY hops;
