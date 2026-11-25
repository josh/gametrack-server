# Database

GameTrack 7 keeps its data in a Core Data store that mirrors to CloudKit:

```
~/Library/Containers/com.joekw.gametrack/Data/Library/Application Support/GameTrack/GameData.sqlite
```

The server reads it with SQLite and never writes: the store carries Core Data's
persistent history and CloudKit's bookkeeping, and a foreign write would corrupt
both. There is no supported read API; GameTrack has no scripting dictionary, and
its Shortcuts actions cannot list a library quickly.

Observations below are from GameTrack 7.0.3 on macOS 27.2, checked against
GameTrack's own export of the same library taken five minutes later: every exported
column of the in-scope files matched the database, apart from four games that
changed in between.

## Opening

The store is in WAL mode. Open `file:<path>?mode=ro`: a read-only connection reads
recent writes from the `-wal` file through the `-shm` file GameTrack leaves beside
it. Never open with `immutable=1` while a `-wal` file exists; that skips the log and
silently returns old rows. The server falls back to `immutable=1` only when the
read-only open fails and there is no `-wal` file, which is the state after a clean
quit.

Read every table inside one transaction so they agree with each other.

The file is about 320 MB for a library of 1,150 games, nearly all of it history
(`ACHANGE`, `ATRANSACTION`) and CloudKit tables (`ANSCK*`). The tables below are
small: reading all of them takes a few milliseconds, so the server keeps one
snapshot and reloads it when the size or modification time of the database or its
`-wal` file changes.

## Names move

Core Data numbers entities alphabetically and puts the numbers in the names of
many-to-many join tables and their columns. GameTrack adds entities between
versions, and the numbers shift: `Game` is entity 6 in 7.0.3, and leftover index
names such as `Z_4GAMETAGS_Z_9GAMETAGS_INDEX` show it was 4 before. Columns are added
between versions as well.

So nothing is hard-coded beyond entity and attribute names:

- `SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'Game'` gives the entity number.
- A join table is `Z_<n><RELATIONSHIP>`; its game column starts with
  `Z_<n>GAMES`, and the other column is the other side.
- `pragma_table_info` gives each table's columns; a wanted column that is missing
  is left out of the query and reads as absent.

| Join table (7.0.3) | Columns                       | Joins         |
| ------------------ | ----------------------------- | ------------- |
| `Z_6GAMEGENRES`    | `Z_6GAMES2`, `Z_13GAMEGENRES` | Game, Genre   |
| `Z_6GAMETAGS`      | `Z_6GAMES`, `Z_11GAMETAGS`    | Game, GameTag |
| `Z_6LIST`          | `Z_6GAMES1`, `Z_18LIST`       | Game, List    |

## Encodings

- **Dates** are seconds since 2001-01-01 UTC, with fractions. The export rounds to
  the millisecond.
- **UUIDs** (`ZID`) are 16-byte blobs. The export prints them in uppercase.
- **String arrays** (`ZGAME.ZPLATFORMS`, `ZADDITIONALPLATFORMS`,
  `ZSMARTFILTER.ZSELECTEDOPTIONS`) are `NSKeyedArchiver` archives of an `NSArray`
  of strings. The export joins them with `|`, though one platform is named
  `Series X|S`.
- **Colours** (`ZTINTCOLOUR`) are text: a base64 `NSKeyedArchiver` archive of a
  `UIColor`. They are passed through untouched.
- **Unset text** is NULL or empty; both export as empty.

## Tables

Columns are `Z` plus the attribute name in uppercase; `Z_PK` is the primary key
other tables refer to.

| Table          | Export file         | Notes                                                     |
| -------------- | ------------------- | --------------------------------------------------------- |
| `ZGAME`        | `games.csv`         | `ZID` UUID; `ZGAMEID` is the IGDB ID, unique.             |
| `ZPLAYTHROUGH` | `playthroughs.csv`  | `ZGAME` refers to the game. Most games have exactly one.  |
| `ZGENRE`       | `genres.csv`        | `ZID` is the IGDB genre ID; `ZNAME` starts with an emoji. |
| `ZGAMETAG`     | `tags.csv`          | Keyed by `ZTITLE` in the export; see below.               |
| `ZLIST`        | `lists.csv`         | `ZLISTNAME`, `ZLISTID`, sort and group settings.          |
| `ZSMARTFILTER` | `smart_filters.csv` | `ZLIST` refers to the list.                               |
| `ZPOSITION`    | `game_lists.csv`    | `ZGAME`, `ZLIST`, `ZINDEX`, `ZSECTION` for manual lists.  |

Things that are not what they seem:

- **`ZGAME.ZGENRES`** is an archived array that repeats entries. The export's
  `genres` column is the join-table set instead, in no stable order. The server
  uses the join table and orders by genre ID.
- **`ZGAME.ZSTATUS`** is a label from older versions (`A Now Playing`, `Finished`,
  …) that is no longer updated and often contradicts `ZGAMESTATE`. The export still
  writes it as `status`.
- **`ZGAME.ZRELEASEYEAR`** is 0 for most games, which carry only `ZRELEASEDATE`.
  A date to be announced is `4001-01-01` with year 3000; a known year alone is
  the last second of that year in Pacific time, such as `2028-01-01T07:59:59Z` with
  year 2027.
- **`user_rating_value`** in the export is `ZUSERRATINGVALUE` when above 0, else
  `ZUSERRATING`.
- **Tag UUIDs** in the export differ from `ZGAMETAG.ZID`, and `game_tags.csv` refers
  to tags by title. Treat the title as the identity.
- **Lists**: a list with `ZSMARTFILTER` rows is a smart list. GameTrack computes
  its games from the rules and stores none: `Z_6LIST` and `ZPOSITION` hold rows only
  for manual lists. Not verified against a library with manual lists.
- **`ZPLAYTHROUGH.ZDURATION`** is whole days between start and finish;
  `ZHOURSPLAYED` is exported as `play_hours`.

## Integers

| Column                       | Values seen                                                               |
| ---------------------------- | ------------------------------------------------------------------------- |
| `ZGAME.ZGAMESTATE`           | 1 In Progress, 2 Queued, 3 Collection, 4 Completed, 5 Abandoned, 6 Wanted |
| `ZGAME.ZCOMPLETIONSTATE`     | 0; 1, 2, or 3 on completed games. Meanings not confirmed.                 |
| `ZGAME.ZUSERRATING`          | 0 unrated, else 1–10.                                                     |
| `ZGAME.ZCRITICRATING`        | 0–100; 0 and -1 both appear for no score.                                 |
| `ZGAME.ZFORMAT`              | 0, and 2 on some console games. Meanings not confirmed.                   |
| `ZGAME.ZTIMETOBEATTYPE`      | 0, 1, 2. Meanings not confirmed.                                          |
| `ZGAME.ZSTEAMDECKSTATUS`     | -1, 0, 1, 2, 3. Meanings not confirmed.                                   |
| `ZGAME.ZPRIORITY`            | -1 on every game.                                                         |
| `ZGAME.ZCOMPLETIONMODE`      | 0 on every game.                                                          |
| `ZPLAYTHROUGH.ZSTATE`        | As `ZGAMESTATE`, and 0 for a game on the wishlist.                        |
| `ZPLAYTHROUGH.ZPROGRESS`     | 0–100, -1 unset.                                                          |
| `ZSMARTFILTER.ZTYPE` (text)  | `status`, `tags`, `releaseDate` seen.                                     |
| `ZSMARTFILTER.ZFILTEROPTION` | `exclude`, `before`, or empty seen.                                       |

The states are confirmed by the labels GameTrack shows and by the counts: the
wishlist is state 6, and GameTrack's "All Games" is every other state.

## Not read

`ZSTEAMGAME`, `ZXBOXGAME`, `ZPLAYSTATIONGAME`, `ZNINTENDOGAME`, `ZEPICGAME`,
`ZGOGGAME`, `ZRETROGAME` and their achievement and trophy tables; `ZDIARYENTRY`;
`ZFRANCHISE`; `ZGAMERELEASE`; `ZHIDDENGAME`; `ZCHALLENGE`; `ZGAMEGRID`; news and
shared-list tables. GameTrack's export covers all of them, and its file and column
names are the place to start when adding one.
