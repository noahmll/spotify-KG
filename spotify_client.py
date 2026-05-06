import time
import spotipy
from spotipy.oauth2 import SpotifyClientCredentials
from tqdm import tqdm


def create_spotify_client(client_id: str, client_secret: str) -> spotipy.Spotify:
    auth_manager = SpotifyClientCredentials(
        client_id=client_id,
        client_secret=client_secret,
    )
    # retries=0 disables spotipy's built-in retry (which waits the full Retry-After header,
    # up to 24h for daily quota limits). Our _retry() handles short backoff instead.
    return spotipy.Spotify(auth_manager=auth_manager, retries=0)


def _retry(func, *args, max_retries: int = 5, **kwargs):
    for attempt in range(max_retries):
        try:
            return func(*args, **kwargs)
        except spotipy.exceptions.SpotifyException as e:
            if e.http_status == 429:
                retry_after = int(e.headers.get("Retry-After", 1)) if e.headers else 1
                if retry_after > 60:
                    raise RuntimeError(
                        f"Spotify Tages-Quota erreicht. "
                        f"Bitte {retry_after // 3600:.0f}h {(retry_after % 3600) // 60:.0f}min warten "
                        f"oder Anzahl der Requests reduzieren (TOP_N_ARTISTS senken)."
                    )
                wait = min(retry_after, 2 ** attempt)
                print(f"\n  Rate limited, waiting {wait}s...")
                time.sleep(wait)
            else:
                raise
    raise RuntimeError("Max retries exceeded on Spotify API call")


SEED_GENRES = ["pop", "hip-hop", "rock", "latin", "r-n-b", "electronic", "country", "k-pop"]


def get_seed_artists(sp: spotipy.Spotify) -> list:
    """Collect artist objects via genre search.
    Sorts by followers (popularity is unreliable in Dev-Mode search results)."""
    artists_by_id = {}
    for genre in tqdm(SEED_GENRES, desc="Searching genres"):
        for offset in range(0, 200, 10):
            try:
                result = _retry(
                    sp.search,
                    q=f"genre:{genre}",
                    type="artist",
                    limit=10,
                    offset=offset,
                )
                items = result.get("artists", {}).get("items", [])
                if not items:
                    break
                for artist in items:
                    aid = artist.get("id")
                    if aid and aid not in artists_by_id:
                        artists_by_id[aid] = _map_artist(artist)
            except Exception:
                break
    return list(artists_by_id.values())


def search_artist_tracks(sp: spotipy.Spotify, artist_name: str, artist_id: str) -> list:
    """Get tracks for an artist via search (artist_top_tracks is 403 in Dev-Mode)."""
    tracks = []
    seen_ids = set()
    for offset in range(0, 50, 10):
        try:
            result = _retry(
                sp.search,
                q=f"artist:{artist_name}",
                type="track",
                limit=10,
                offset=offset,
            )
            items = result.get("tracks", {}).get("items", [])
            if not items:
                break
            for t in items:
                tid = t.get("id")
                if not tid or tid in seen_ids:
                    continue
                track_artist_ids = [a["id"] for a in t.get("artists", []) if a.get("id")]
                # Only include tracks where this artist actually appears (avoids name matches)
                if artist_id not in track_artist_ids:
                    continue
                seen_ids.add(tid)
                tracks.append({
                    "id": tid,
                    "name": t["name"],
                    "release_date": t.get("album", {}).get("release_date", ""),
                    "popularity": t.get("popularity", 0),
                    "uri": t.get("uri", ""),
                    "artist_ids": track_artist_ids,
                })
        except Exception:
            break
    return tracks


def _map_artist(a: dict) -> dict:
    return {
        "id": a["id"],
        "name": a["name"],
        "genres": a.get("genres", []),
        "popularity": a.get("popularity", 0),
        "followers": a.get("followers", {}).get("total", 0),
        "uri": a.get("uri", ""),
    }
