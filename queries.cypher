// ============================================================
// Spotify Knowledge Graph – Analyse-Queries
// Ausführen im Neo4j Browser: http://localhost:7474
// ============================================================
//
// HINWEIS ZUM DATENBESTAND:
// Im Spotify Development-Mode liefert die API keine popularity-,
// followers- oder genres-Werte mehr (alles null → im Graph 0 bzw. []).
// Der Kern dieses Graphen ist daher das KOLLABORATIONS-NETZWERK
// (PERFORMED_ON / COLLABORATED_WITH), nicht die Metadaten.
// Queries, die popularity/followers/genres brauchen, sind unten unter
// "NUR MIT EXTENDED ACCESS" gesammelt und liefern aktuell leere/0-Werte.
// ============================================================

// --- Überblick ---

// Alle Knoten und Kanten zählen
MATCH (n) RETURN labels(n) AS label, count(n) AS anzahl;

MATCH ()-[r]->() RETURN type(r) AS kante, count(r) AS anzahl;

// ============================================================
// KOLLABORATIONS-NETZWERK  (funktioniert im Dev-Mode)
// ============================================================

// Artists mit den meisten Kollaborationen (Degree Centrality)
MATCH (a:Artist)-[:COLLABORATED_WITH]-()
RETURN a.name AS artist, count(*) AS kollaborationen
ORDER BY kollaborationen DESC
LIMIT 10;

// Alle Kollaborationen eines bestimmten Artists
MATCH (a:Artist {name: "David Guetta"})-[:COLLABORATED_WITH]-(b:Artist)
RETURN b.name AS kollaborateur
ORDER BY kollaborateur;

// Gemeinsame Tracks zweier Artists (track_ids steckt auf der Kante)
MATCH (a:Artist {name: "David Guetta"})-[c:COLLABORATED_WITH]-(b:Artist)
RETURN b.name AS kollaborateur, size(c.track_ids) AS gemeinsame_tracks
ORDER BY gemeinsame_tracks DESC;

// Kollaborationsgraph visualisieren (kleine Menge empfohlen)
MATCH p=(a:Artist)-[:COLLABORATED_WITH]-(b:Artist)
RETURN p
LIMIT 50;

// Kürzester Weg zwischen zwei Artists über Kollaborationen
MATCH p = shortestPath(
    (a:Artist {name: "David Guetta"})-[:COLLABORATED_WITH*]-(b:Artist {name: "Sia"})
)
RETURN p;

// Artists, die NICHT kollaborieren (isolierte Knoten im Netzwerk)
MATCH (a:Artist)
WHERE NOT (a)-[:COLLABORATED_WITH]-()
RETURN a.name AS solo_artist
ORDER BY solo_artist;

// --- Tracks ---

// Tracks mit den meisten beteiligten Top-Artists (Feature-dichte Tracks)
MATCH (a:Artist)-[:PERFORMED_ON]->(t:Track)
RETURN t.name AS track, count(a) AS beteiligte_artists
ORDER BY beteiligte_artists DESC
LIMIT 10;

// Artists auf einem bestimmten Track
MATCH (a:Artist)-[:PERFORMED_ON]->(t:Track {name: "Titanium"})
RETURN a.name AS artist;

// ============================================================
// COMMUNITY / CLUSTER  (Neo4j GDS-Plugin benötigt)
// ============================================================

// PageRank auf dem Kollaborationsgraph
// CALL gds.graph.project('collab', 'Artist', {COLLABORATED_WITH: {orientation: 'UNDIRECTED'}});
// CALL gds.pageRank.stream('collab')
// YIELD nodeId, score
// RETURN gds.util.asNode(nodeId).name AS name, score
// ORDER BY score DESC LIMIT 10;

// Louvain Community Detection (Cluster im Netzwerk)
// CALL gds.louvain.stream('collab')
// YIELD nodeId, communityId
// RETURN communityId, collect(gds.util.asNode(nodeId).name) AS artists
// ORDER BY size(artists) DESC;

// ============================================================
// NUR MIT EXTENDED ACCESS  (Dev-Mode liefert hier 0 / leer)
// ============================================================

// Top Artists nach popularity  — popularity ist im Dev-Mode 0
// MATCH (a:Artist) RETURN a.name, a.popularity ORDER BY a.popularity DESC LIMIT 10;

// Top Tracks nach popularity  — popularity ist im Dev-Mode 0
// MATCH (t:Track) RETURN t.name, t.popularity ORDER BY t.popularity DESC LIMIT 10;

// Genre-Verteilung  — genres ist im Dev-Mode leer
// MATCH (a:Artist) UNWIND a.genres AS genre
// RETURN genre, count(*) AS anzahl ORDER BY anzahl DESC LIMIT 15;
