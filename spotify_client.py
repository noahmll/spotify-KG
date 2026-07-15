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


# Throttle the rate-limit notice so long backoffs don't spam the terminal.
_last_rl_notice = 0.0
_RL_NOTICE_INTERVAL = 30  # seconds


def _retry(func, *args, max_retries: int = 5, **kwargs):
    global _last_rl_notice
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
                # Quiet backoff: at most one notice per _RL_NOTICE_INTERVAL, and
                # written via tqdm so it doesn't break active progress bars.
                now = time.monotonic()
                if now - _last_rl_notice > _RL_NOTICE_INTERVAL:
                    tqdm.write("  (Spotify rate limit – warte kurz, läuft weiter...)")
                    _last_rl_notice = now
                time.sleep(wait)
            else:
                raise
    raise RuntimeError("Max retries exceeded on Spotify API call")


SEED_GENRES = ["pop", "hip-hop", "rock", "latin", "r-n-b", "electronic", "country", "k-pop", "jazz", "metal", "reggae", "soul"]


def get_seed_artists(sp: spotipy.Spotify, target: int) -> list:
    """Collect up to `target` unique artists via genre search.

    Dev-mode search returns no popularity/followers/genres, so there is no
    ranking metric. Artists are gathered round-robin across SEED_GENRES (one
    page of 10 per genre per round) in Spotify's search-relevance order, which
    keeps the set balanced across genres. Collection stops as soon as `target`
    unique artists are reached, so request cost scales with `target` rather
    than fetching a large pool to discard most of it.
    """
    artists_by_id = {}
    # search offset caps at 1000 → at most 100 pages per genre
    for offset in tqdm(range(0, 1000, 10), desc="Collecting artists"):
        if len(artists_by_id) >= target:
            break
        progressed = False
        for genre in SEED_GENRES:
            if len(artists_by_id) >= target:
                break
            try:
                result = _retry(
                    sp.search,
                    q=f"genre:{genre}",
                    type="artist",
                    limit=10,
                    offset=offset,
                )
                items = result.get("artists", {}).get("items", [])
            except Exception:
                continue
            if items:
                progressed = True
            for artist in items:
                aid = artist.get("id")
                if aid and aid not in artists_by_id:
                    artists_by_id[aid] = _map_artist(artist)
        if not progressed:
            break  # every genre exhausted
    return list(artists_by_id.values())[:target]


def search_artist_tracks(
    sp: spotipy.Spotify, artist_name: str, artist_id: str, pages: int = 5
) -> list:
    """Get tracks for an artist via search (artist_top_tracks is 403 in Dev-Mode).
    `pages` search pages of 10 tracks each are scanned."""
    tracks = []
    seen_ids = set()
    for offset in range(0, pages * 10, 10):
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
                # Capture every artist on the track (id + name + uri) so featured
                # collaborators can become graph nodes too, not just seed artists.
                track_artists = [
                    {"id": a["id"], "name": a.get("name", ""), "uri": a.get("uri", "")}
                    for a in t.get("artists", [])
                    if a.get("id")
                ]
                # Only include tracks where this artist actually appears (avoids name matches)
                if artist_id not in [a["id"] for a in track_artists]:
                    continue
                seen_ids.add(tid)
                tracks.append({
                    "id": tid,
                    "name": t["name"],
                    "release_date": t.get("album", {}).get("release_date", ""),
                    "popularity": t.get("popularity", 0),
                    "uri": t.get("uri", ""),
                    "artists": track_artists,
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
