# Number of Artist nodes to build. Dev-mode Spotify search returns no
# popularity/followers/genres, so there is no ranking metric — artists are
# taken in Spotify's search-relevance order, balanced round-robin across
# SEED_GENRES (see spotify_client.get_seed_artists). Collection stops as soon
# as this many unique artists are gathered, so cost scales with the target.
TOP_N_ARTISTS = 500

# Search pages (10 tracks each) pulled per artist in the track phase.
# More pages = more tracks and more discovered collaborations, but the track
# phase costs roughly TOP_N_ARTISTS * TRACK_SEARCH_PAGES requests.
TRACK_SEARCH_PAGES = 5

NEO4J_URI = "neo4j://127.0.0.1:7687"
NEO4J_USER = "neo4j"
