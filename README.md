# All Organizer

Une seule bibliothèque pour tout : **animes, films, séries, jeunesse et
musique**, qu'ils soient sur le téléphone ou sur un serveur.

## Le principe

**La source est un attribut, pas une catégorie.** Un film reste un film qu'il
vienne de la carte SD ou du PC. Les onglets suivent donc la nature du
contenu, et une petite marque sur la fiche indique ce qui vient d'un
serveur — donc lisible seulement quand le PC répond.

## Les sources de fiches

| Contenu | Sources, dans l'ordre |
|---|---|
| Animes | AniList, MyAnimeList, Kitsu, puis TMDB en dernier recours |
| Films et séries | TMDB, puis TVmaze pour les séries |
| Musique | les étiquettes du fichier, puis le chemin |

Un anime ne se cherche pas chez TMDB : AniList connaît les titres romaji,
les saisons et les OAV, ce que les bases généralistes rendent mal.

## Le serveur

Le PC fait tourner le script Python fourni à part. L'application le parcourt
et verse son contenu dans la bibliothèque, à côté des fichiers locaux.

Pour la musique distante, une astuce : le serveur répond aux **requêtes
partielles**, donc l'application demande les deux premiers mégaoctets d'un
fichier et y lit les étiquettes ID3 **sans le télécharger**. Artiste, album,
numéro de piste et pochette sont ainsi connus sans transférer cent
mégaoctets.

## Réveil du PC

Chaque serveur porte une adresse HTTP libre appelée pour l'allumer —
Tasmota, ESPHome ou un montage maison. Quand le serveur ne répond pas, elle
est appelée puis l'application attend le démarrage.

## Confidentialité

Aucun fichier n'est copié. Seuls les titres sont envoyés aux bases de
métadonnées, et à l'assistant IA si tu l'actives.
