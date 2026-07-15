// ============================================================
// Spotify Knowledge Graph — Demo-Queries für die Präsentation
// Ausführen im Neo4j Browser: http://localhost:7474
//
// Alle Queries laufen mit purem Cypher (kein GDS/APOC nötig) und
// wurden gegen einen realen Datenbestand validiert.
//
// DATENMODELL-HINWEIS: Artist-Knoten tragen ein seed-Flag:
//   seed=true  → per Genre-Suche gesammelter Kern (z. B. 150)
//   seed=false → Feature-Artists, die über Tracks entdeckt wurden
// Mit Feature-Artists wächst der Graph deutlich (mehrere hundert
// zusätzliche Artist-Knoten, >5.000 Elemente gesamt möglich).
//
// WICHTIG: Konkrete Zahlen/Namen ändern sich mit jedem Pipeline-
// Lauf leicht (Spotify-Suchreihenfolge ist nicht deterministisch).
// Die hartkodierten Artist-Namen unten (Farruko, Pitbull, ...)
// vor der Demo einmal mit Query 2 gegenprüfen.
//
// HINWEIS VISUALISIERUNG: Der Neo4j Browser rendert standardmäßig
// max. ~1.000 Knoten (Einstellung "Visualization node limit" im
// Settings-Drawer). Das ist ein reines Anzeige-Limit — die Queries
// hier liefern bewusst kleine, lesbare Teilgraphen statt alles auf
// einmal zu rendern.
// ============================================================


// ------------------------------------------------------------
// 1) ÜBERBLICK: Was ist im Graphen?
// Zeigt: Anzahl Knoten pro Label und Kanten pro Typ.
// Warum interessant: Erster Beleg, dass der Lauf vollständig war;
// Einstieg in die Erklärung des Datenmodells.
// Erwartung: Track ~2.000; Artist = Seed (~150) + Feature (mehrere
// hundert); PERFORMED_ON und COLLABORATED_WITH entsprechend größer.
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
// Zeigt: Die 10 am stärksten vernetzten Artists nach Anzahl
// direkter Kollaborationsbeziehungen.
// Warum interessant: Kernergebnis des Projekts — im gesammelten
// Ausschnitt dominiert ein Latin-Cluster (Farruko, Ozuna, J Balvin,
// KAROL G, Bad Bunny); Latin-Pop ist ein extrem featurelastiges Genre.
// Erwartung: Tabelle, Spitzenwerte um ~14 Kollaborationen.
// ------------------------------------------------------------
MATCH (a:Artist)-[:COLLABORATED_WITH]-()
RETURN a.name AS artist, count(*) AS kollaborationen
ORDER BY kollaborationen DESC
LIMIT 10;


// ------------------------------------------------------------
// 3) EGO-GRAPH DES TOP-HUBS (Visualisierung!)
// Zeigt: Den am stärksten vernetzten Artist mit seiner direkten
// Nachbarschaft UND den Verbindungen der Nachbarn untereinander —
// als Graph-Ansicht ausführen.
// Warum interessant: Die schönste Visualisierung für die Demo:
// klein genug zum Lesen, zeigt echte Cluster-Struktur statt
// "Haarball". Findet den Hub dynamisch (kein hartkodierter Name).
// Erwartung: ~15-30 Knoten um den Hub (zuletzt: Farruko).
// ------------------------------------------------------------
MATCH (hub:Artist)-[:COLLABORATED_WITH]-()
WITH hub, count(*) AS deg ORDER BY deg DESC LIMIT 1
MATCH p = (hub)-[:COLLABORATED_WITH]-(nachbar:Artist)
OPTIONAL MATCH q = (nachbar)-[:COLLABORATED_WITH]-(anderer:Artist)
WHERE (anderer)-[:COLLABORATED_WITH]-(hub)
RETURN p, q;


// ------------------------------------------------------------
// 4) STÄRKSTE KOLLABORATIONS-PAARE (Kantengewicht)
// Zeigt: Artist-Paare mit den meisten gemeinsamen Tracks —
// das Gewicht steckt als track_ids-Liste auf der Kante.
// Warum interessant: Demonstriert Properties AUF Beziehungen
// (Alleinstellungsmerkmal des Property-Graph-Modells).
// Erwartung: z. B. Peso Pluma & Tito Double P (~12 gemeinsame
// Tracks), David Guetta & Sia (~4).
// ------------------------------------------------------------
MATCH (a:Artist)-[c:COLLABORATED_WITH]-(b:Artist)
WHERE a.name < b.name
RETURN a.name AS artist_1, b.name AS artist_2,
       size(c.track_ids) AS gemeinsame_tracks
ORDER BY gemeinsame_tracks DESC
LIMIT 10;


// ------------------------------------------------------------
// 5) KÜRZESTER PFAD: "Six Degrees of Spotify"
// Zeigt: Wie zwei Artists aus verschiedenen Welten über
// Kollaborationsketten verbunden sind — als Graph ausführen.
// Warum interessant: DIE Signature-Query einer Graphdatenbank;
// in SQL nur mit rekursiven CTEs machbar, in Cypher eine Zeile.
// Erwartung (letzter Lauf): Pitbull → Farruko → Tiësto → Peso Pluma
// (3 Hops). Namen ggf. anpassen, falls ein Artist im aktuellen
// Lauf fehlt (mit Query 2 prüfen).
// ------------------------------------------------------------
MATCH p = shortestPath(
  (a:Artist {name: "Pitbull"})-[:COLLABORATED_WITH*..10]-(b:Artist {name: "Peso Pluma"})
)
RETURN p;


// ------------------------------------------------------------
// 6) BRÜCKEN-ARTISTS (Broker im Netzwerk)
// Zeigt: Artists, die die meisten Paare von Künstlern verbinden,
// die selbst NICHT direkt kollaborieren (Betweenness-Idee,
// ohne GDS-Plugin in purem Cypher).
// Warum interessant: Wer hält das Netzwerk zusammen? Diese
// Artists sind die "Vermittler" zwischen Subszenen (z. B. verbindet
// David Guetta den Pop/EDM-Bereich mit dem Latin-Cluster).
// Erwartung: Farruko (~69 Paare), Ozuna, J Balvin, KAROL G,
// David Guetta.
// ------------------------------------------------------------
MATCH (x:Artist)-[:COLLABORATED_WITH]-(mitte:Artist)-[:COLLABORATED_WITH]-(y:Artist)
WHERE x <> y AND NOT (x)-[:COLLABORATED_WITH]-(y)
WITH mitte, count(DISTINCT [x.id, y.id]) AS paare
RETURN mitte.name AS bruecken_artist, paare / 2 AS verbundene_paare
ORDER BY verbundene_paare DESC
LIMIT 10;


// ------------------------------------------------------------
// 7) FEATURE-DICHTESTE TRACKS
// Zeigt: Tracks, auf denen die meisten der gesammelten Artists
// gemeinsam stehen (Mega-Features/Remixes).
// Warum interessant: Verbindet beide Knotentypen; erklärt, WORAUS
// die COLLABORATED_WITH-Kanten abgeleitet werden. Hinweis für die
// Demo: Derselbe Songtitel kann doppelt erscheinen (verschiedene
// Spotify-Releases = verschiedene Track-IDs) — guter Anlass, über
// Datenqualität zu sprechen.
// Erwartung: z. B. "China" und "Baila Baila Baila - Remix" mit je
// 5 beteiligten Artists.
// ------------------------------------------------------------
MATCH (a:Artist)-[:PERFORMED_ON]->(t:Track)
WITH t, count(a) AS beteiligte, collect(a.name) AS artists
WHERE beteiligte >= 3
RETURN t.name AS track, t.release_date AS datum, beteiligte, artists
ORDER BY beteiligte DESC
LIMIT 10;


// ------------------------------------------------------------
// 8) CLUSTER-VISUALISIERUNG: Das gesamte Kollaborationsnetzwerk
// Zeigt: NUR die Artist-Knoten mit ihren Kollaborationskanten
// (ohne die ~2.000 Track-Knoten) — als Graph ausführen.
// Warum interessant: ~85 vernetzte Artists / ~160 Kanten sind
// problemlos renderbar und zeigen die Community-Struktur auf einen
// Blick: eine Riesenkomponente (~76 Artists, Latin/Pop/EDM) plus
// kleine Inseln (z. B. Billie Eilish–Charli xcx). Das ist die
// richtige Antwort auf das Browser-Anzeige-Limit: nicht alles
// rendern, sondern die aussagekräftige Projektion.
// Erwartung: Ein großer zusammenhängender Cluster + 3-4 Mini-Inseln.
// ------------------------------------------------------------
MATCH p = (:Artist)-[:COLLABORATED_WITH]-(:Artist)
RETURN p;


// ------------------------------------------------------------
// 9) NEUESTE KOLLABORATIONEN (Aktualität der Daten)
// Zeigt: Die jüngsten gemeinsamen Releases im Datenbestand.
// Warum interessant: Beweist, dass die Pipeline live aktuelle
// Daten zieht (Releases aus dem laufenden Jahr).
// Erwartung: Tracks mit Release-Datum der letzten Wochen/Monate.
// ------------------------------------------------------------
MATCH (a1:Artist)-[:PERFORMED_ON]->(t:Track)<-[:PERFORMED_ON]-(a2:Artist)
WHERE a1.name < a2.name
WITH t, collect(DISTINCT a1.name) + collect(DISTINCT a2.name) AS beteiligte
RETURN DISTINCT t.name AS track, t.release_date AS datum, beteiligte[0..4] AS artists
ORDER BY datum DESC
LIMIT 10;


// ------------------------------------------------------------
// 10) STICHPROBEN-CHECK: Solo- vs. vernetzte Seed-Artists
// Zeigt: Wie viele der GESUCHTEN Artists (seed=true) im Sample
// (k)eine Kollaboration haben. Feature-Artists haben per
// Konstruktion immer mindestens eine Kollaboration und werden
// daher hier ausgeklammert.
// Warum interessant: Ehrliche methodische Einordnung: "solo"
// heißt nur "keine Kollaboration in unseren gesammelten Tracks",
// nicht "hat nie kollaboriert".
// Erwartung: grob hälftige Verteilung bei den Seed-Artists.
// ------------------------------------------------------------
MATCH (a:Artist) WHERE a.seed
RETURN
  CASE WHEN (a)-[:COLLABORATED_WITH]-() THEN 'vernetzt' ELSE 'solo (im Sample)' END AS status,
  count(*) AS anzahl;
