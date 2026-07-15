from neo4j import GraphDatabase
from tqdm import tqdm
from config import NEO4J_URI, NEO4J_USER


class Neo4jLoader:
    def __init__(self, password: str):
        self.driver = GraphDatabase.driver(NEO4J_URI, auth=(NEO4J_USER, password))

    def close(self):
        self.driver.close()

    def test_connection(self):
        with self.driver.session() as session:
            session.run("RETURN 1")
        print("Neo4j connection OK.")

    def setup_constraints(self):
        with self.driver.session() as session:
            session.run(
                "CREATE CONSTRAINT artist_id IF NOT EXISTS "
                "FOR (a:Artist) REQUIRE a.id IS UNIQUE"
            )
            session.run(
                "CREATE CONSTRAINT track_id IF NOT EXISTS "
                "FOR (t:Track) REQUIRE t.id IS UNIQUE"
            )

    def clear_database(self):
        with self.driver.session() as session:
            session.run("MATCH (n) DETACH DELETE n")

    def load_artists(self, artists: list):
        """Load the collected seed artists. Marked seed=true to distinguish the
        searched core from featured collaborators discovered via tracks."""
        with self.driver.session() as session:
            for artist in tqdm(artists, desc="Loading artists"):
                session.run(
                    """
                    MERGE (a:Artist {id: $id})
                    SET a.name       = $name,
                        a.genres     = $genres,
                        a.popularity = $popularity,
                        a.followers  = $followers,
                        a.uri        = $uri,
                        a.seed       = true
                    """,
                    **artist,
                )

    def load_tracks_and_relationships(self, tracks_by_artist: dict):
        """Create Track nodes and PERFORMED_ON edges for EVERY artist on each
        track. Featured collaborators that were not seed artists are created as
        nodes on the fly (seed=false), widening and densifying the graph without
        any extra API calls."""
        with self.driver.session() as session:
            for artist_id, tracks in tqdm(
                tracks_by_artist.items(), desc="Loading tracks & edges"
            ):
                for track in tracks:
                    session.run(
                        """
                        MERGE (t:Track {id: $id})
                        SET t.name         = $name,
                            t.release_date = $release_date,
                            t.popularity   = $popularity,
                            t.uri          = $uri
                        """,
                        id=track["id"],
                        name=track["name"],
                        release_date=track["release_date"],
                        popularity=track["popularity"],
                        uri=track["uri"],
                    )
                    for a in track["artists"]:
                        session.run(
                            """
                            MERGE (ar:Artist {id: $aid})
                              ON CREATE SET ar.name       = $aname,
                                            ar.uri        = $auri,
                                            ar.seed       = false,
                                            ar.genres     = [],
                                            ar.popularity = 0,
                                            ar.followers  = 0
                            WITH ar
                            MATCH (t:Track {id: $track_id})
                            MERGE (ar)-[:PERFORMED_ON]->(t)
                            """,
                            aid=a["id"],
                            aname=a["name"],
                            auri=a["uri"],
                            track_id=track["id"],
                        )

    def derive_collaborations(self) -> int:
        with self.driver.session() as session:
            result = session.run(
                """
                MATCH (a1:Artist)-[:PERFORMED_ON]->(t:Track)<-[:PERFORMED_ON]-(a2:Artist)
                WHERE a1 <> a2 AND elementId(a1) < elementId(a2)
                MERGE (a1)-[c:COLLABORATED_WITH]-(a2)
                  ON CREATE SET c.track_ids = [t.id]
                  ON MATCH  SET c.track_ids = c.track_ids + [t.id]
                RETURN count(*) AS n
                """
            )
            record = result.single()
            return record["n"] if record else 0

    def get_stats(self) -> dict:
        with self.driver.session() as session:
            def count(q):
                return session.run(q).single()[0]

            return {
                "artists": count("MATCH (a:Artist) RETURN count(a)"),
                "seed_artists": count("MATCH (a:Artist) WHERE a.seed RETURN count(a)"),
                "feature_artists": count(
                    "MATCH (a:Artist) WHERE a.seed = false RETURN count(a)"
                ),
                "tracks": count("MATCH (t:Track) RETURN count(t)"),
                "performed_on": count("MATCH ()-[r:PERFORMED_ON]->() RETURN count(r)"),
                "collaborated_with": count(
                    "MATCH ()-[r:COLLABORATED_WITH]-() RETURN count(r) / 2"
                ),
            }
