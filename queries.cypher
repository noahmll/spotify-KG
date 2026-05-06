// ============================================================
// Spotify Knowledge Graph – Analyse-Queries
// Ausführen im Neo4j Browser: http://localhost:7474
// ============================================================

// --- Überblick ---

// Alle Knoten und Kanten zählen
MATCH (n) RETURN labels(n) AS label, count(n) AS anzahl;

MATCH ()-[r]->() RETURN type(r) AS kante, count(r) AS anzahl;

// --- Artists ---

// Top 10 Artists nach Popularity
MATCH (a:Artist)
RETURN a.name, a.popularity, a.followers
ORDER BY a.popularity DESC
LIMIT 10;

// Artists mit den meisten Kollaborationen (Degree Centrality)
MATCH (a:Artist)-[:COLLABORATED_WITH]-()
RETURN a.name, a.popularity, count(*) AS kollaborationen
ORDER BY kollaborationen DESC
LIMIT 10;

// Alle Kollaborationen eines bestimmten Artists
MATCH (a:Artist {name: "Taylor Swift"})-[:COLLABORATED_WITH]-(b:Artist)
RETURN b.name, b.popularity
ORDER BY b.popularity DESC;

// --- Tracks ---

// Top 10 Tracks nach Popularity
MATCH (t:Track)
RETURN t.name, t.popularity, t.release_date
ORDER BY t.popularity DESC
LIMIT 10;

// Artists auf einem bestimmten Track
MATCH (a:Artist)-[:PERFORMED_ON]->(t:Track {name: "Blinding Lights"})
RETURN a.name, a.popularity;

// --- Kollaborationen ---

// Alle COLLABORATED_WITH-Beziehungen visualisieren (kleine Datenmenge empfohlen)
MATCH p=(a:Artist)-[:COLLABORATED_WITH]-(b:Artist)
RETURN p
LIMIT 50;

// Kürzester Weg zwischen zwei Artists
MATCH p = shortestPath(
    (a:Artist {name: "Drake"})-[:COLLABORATED_WITH*]-(b:Artist {name: "Ed Sheeran"})
)
RETURN p;

// --- Genre-Analyse ---

// Artists eines bestimmten Genres
MATCH (a:Artist)
WHERE "pop" IN a.genres
RETURN a.name, a.popularity
ORDER BY a.popularity DESC
LIMIT 20;

// Genres mit den meisten Artists
MATCH (a:Artist)
UNWIND a.genres AS genre
RETURN genre, count(*) AS anzahl
ORDER BY anzahl DESC
LIMIT 15;

// --- Community / Cluster (GDS Plugin benötigt) ---

// Pagerank auf Kollaborationsgraph
// CALL gds.pageRank.stream({
//   nodeProjection: 'Artist',
//   relationshipProjection: 'COLLABORATED_WITH'
// })
// YIELD nodeId, score
// RETURN gds.util.asNode(nodeId).name AS name, score
// ORDER BY score DESC LIMIT 10;
