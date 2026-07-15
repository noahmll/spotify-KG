import os
import sys
from dotenv import load_dotenv
from tqdm import tqdm

from config import TOP_N_ARTISTS, TRACK_SEARCH_PAGES
from spotify_client import (
    create_spotify_client,
    get_seed_artists,
    search_artist_tracks,
)
from neo4j_loader import Neo4jLoader


def main():
    load_dotenv()

    client_id = os.getenv("SPOTIFY_CLIENT_ID")
    client_secret = os.getenv("SPOTIFY_CLIENT_SECRET")
    neo4j_password = os.getenv("NEO4J_PASSWORD")

    if not client_id or not client_secret:
        print("ERROR: SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET fehlen in .env")
        print("Setup: https://developer.spotify.com/dashboard → Create App → Settings")
        sys.exit(1)

    if not neo4j_password:
        print("ERROR: NEO4J_PASSWORD fehlt in .env")
        sys.exit(1)

    print(f"=== Spotify Knowledge Graph (TOP_N_ARTISTS={TOP_N_ARTISTS}) ===\n")

    sp = create_spotify_client(client_id, client_secret)
    loader = Neo4jLoader(neo4j_password)

    try:
        loader.test_connection()
        loader.setup_constraints()

        print(f"\n[1/4] Artists sammeln (Ziel: {TOP_N_ARTISTS}, balanciert über Genres)...")
        # Dev-Mode-Suche liefert keine popularity/followers/genres → kein Ranking
        # möglich. Auswahl = Spotifys Such-Relevanz-Reihenfolge, round-robin über Genres.
        top_artists = get_seed_artists(sp, TOP_N_ARTISTS)
        print(f"      {len(top_artists)} Artists gesammelt:")
        for a in top_artists[:15]:
            print(f"        {a['name']}")
        if len(top_artists) > 15:
            print(f"        ... (+{len(top_artists) - 15} weitere)")

        print(f"\n[2/4] Tracks für {len(top_artists)} Artists per Suche abrufen...")
        tracks_by_artist = {}
        for artist in tqdm(top_artists, desc="Tracks fetching"):
            tracks_by_artist[artist["id"]] = search_artist_tracks(
                sp, artist["name"], artist["id"], pages=TRACK_SEARCH_PAGES
            )

        print(f"\n[3/4] Daten in Neo4j laden...")
        loader.clear_database()
        loader.load_artists(top_artists)
        loader.load_tracks_and_relationships(tracks_by_artist)

        print(f"\n[4/4] Kollaborationen ableiten...")
        loader.derive_collaborations()

        stats = loader.get_stats()
        print(f"\n=== Fertig! ===")
        print(f"  Artist-Knoten:      {stats['artists']}"
              f" (davon {stats['seed_artists']} Seed, {stats['feature_artists']} Feature)")
        print(f"  Track-Knoten:       {stats['tracks']}")
        print(f"  PERFORMED_ON:       {stats['performed_on']}")
        print(f"  COLLABORATED_WITH:  {stats['collaborated_with']}")
        print(f"\nNeo4j Browser öffnen: http://localhost:7474")
        print(f"Einstiegspunkt:  MATCH (a:Artist) RETURN a LIMIT 25")

    finally:
        loader.close()


if __name__ == "__main__":
    main()
