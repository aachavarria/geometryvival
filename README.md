# Geometry Survival

A multiplayer Vampire Survivors-like game built with **Godot 4.6**, **Supabase**, and **GameFlow**. Players choose a geometric shape (Circle, Square, Triangle) and survive waves of enemies using a rock-paper-scissors kill mechanic.

This repo is intended as a **reference project** showing how to build a complete multiplayer game with a dedicated server backend — from local development to production deployment.

---

## Stack

| Layer | Technology |
|---|---|
| Game client + server | Godot 4.6 (ENet UDP multiplayer) |
| Backend / Auth | Supabase (PostgreSQL + Auth + Realtime + Edge Functions) |
| Game server hosting | GameFlow (Agones/Kubernetes) |
| Edge Functions runtime | Deno (TypeScript) |

---

## How it works

```
Player logs in (anonymous auth via Supabase)
        ↓
Creates or joins a lobby (Edge Functions + DB)
        ↓
All players mark ready → owner presses Start
        ↓
Edge Function calls GameFlow → allocates a dedicated game server
        ↓
GameFlow returns IP:port → stored in DB
        ↓
Supabase Realtime notifies all clients
        ↓
Clients connect to game server via ENet (UDP)
        ↓
Game runs — server authoritative for enemies and collisions
        ↓
All players die → Agones shuts down the server
```

---

## Project structure

```
geometryvival/
├── scenes/                        # Godot scenes
│   ├── main_menu.tscn             # Login screen
│   ├── lobby_menu.tscn            # Lobby list + waiting room
│   ├── game.tscn                  # Main game scene
│   ├── player.tscn                # Player node (MultiplayerSynchronizer)
│   └── enemy.tscn                 # Enemy node (MultiplayerSynchronizer)
│
├── scripts/
│   ├── game_constants.gd          # Shared: shape names, colors, kill rule
│   ├── network_manager.gd         # Autoload: ENet host/join
│   ├── supabase_manager.gd        # Autoload: auth, lobbies, Realtime
│   ├── game.gd                    # Game loop: spawning, collisions, difficulty
│   ├── player.gd                  # Movement, shape cycling, damage
│   ├── enemy.gd                   # AI: moves toward nearest player
│   ├── main_menu.gd               # Login flow
│   └── lobby_menu.gd              # Lobby UI
│
├── addons/
│   ├── supabase/                  # godot-engine/supabase addon (4.x branch)
│   └── agones/                    # Agones SDK for GameFlow lifecycle
│
├── supabase/
│   ├── config.toml                # Local Supabase config
│   ├── migrations/
│   │   └── 20260326000001_initial.sql   # Full DB schema
│   └── functions/
│       ├── _shared/cors.ts        # Shared CORS headers
│       ├── auth-anonymous/        # Create account after anonymous login
│       ├── accounts-me/           # Get current user's account
│       ├── lobbies-list/          # List public lobbies
│       ├── lobbies-create/        # Create a lobby
│       ├── lobbies-join/          # Join by ID or invite code
│       ├── lobbies-ready/         # Toggle ready state
│       ├── lobbies-leave/         # Leave lobby
│       └── lobbies-start/         # Allocate game server via GameFlow
│
└── export_presets.cfg             # Linux Server export preset for GameFlow
```

---

## Prerequisites

- [Godot 4.6](https://godotengine.org/download) (standard, not .NET)
- [Supabase CLI](https://supabase.com/docs/guides/cli/getting-started)
- [Docker](https://www.docker.com/) (required by Supabase CLI for local dev)
- A [GameFlow](https://gameflow.gg) account with a game created

---

## Local development setup

### 1. Clone the repo

```bash
git clone https://github.com/aachavarria/geometryvival.git
cd geometryvival
```

### 2. Start Supabase locally

```bash
supabase start
```

This starts a local Supabase stack (PostgreSQL, Auth, Realtime, Edge Functions) via Docker and applies the migration automatically.

Once running, it will print your local credentials:
```
API URL:      http://127.0.0.1:54321
anon key:     eyJhbGci...
```

### 3. Configure the Supabase addon

Edit `addons/supabase/.env` with the local credentials:

```ini
[supabase/config]

supabaseUrl="http://127.0.0.1:54321"
supabaseKey="<your local anon key>"
```

> The local anon key is always the same for every Supabase local project — check the output of `supabase start` or run `supabase status`.

### 4. Configure GameFlow credentials

Edit `supabase/functions/.env.local`:

```
GAMEFLOW_GAME_ID=<your game id>
GAMEFLOW_API_KEY=<your api key>
```

Get these from the [GameFlow dashboard](https://dashboard.gameflow.gg).

### 5. Start Edge Functions

```bash
supabase functions serve --env-file supabase/functions/.env.local
```

Leave this running in a terminal. It hot-reloads on file changes.

### 6. Open the project in Godot

Open `project.godot` in Godot 4.6. Hit **Play** — the game will start as a client (it shows the login screen).

---

## Running the game locally

You need at least two instances: a **server** and a **client**.

### Start the server

In Godot, open a terminal and run:

```bash
# macOS / Linux
/path/to/godot --path /path/to/geometryvival --headless -- --server

# Or use the Godot editor: Project → Export → Linux Server
# then run: ./build/game.pck --server
```

Or simply press **Play** in the editor — the main menu detects the `--server` flag and auto-hosts.

### Start a client

Press **Play** in the Godot editor (or open a second Godot instance). Enter a username and click **Play Online**.

> For local testing without GameFlow, you can bypass the lobby by having a host player and connecting directly. The lobby system requires the full Supabase + GameFlow stack.

---

## Building the dedicated server

The dedicated server is exported as a `.pck` file (Godot's packaged resource format) and runs headlessly.

### 1. Install the Linux Server export template

In Godot: **Editor → Manage Export Templates → Download**

Select the **Linux** template.

### 2. Export

**Project → Export → Linux Server → Export PCK/Zip**

The output is `build/game.pck` (as configured in `export_presets.cfg`).

### 3. Upload to GameFlow

Go to the [GameFlow dashboard](https://dashboard.gameflow.gg), select your game, and upload `build/game.pck`.

> Every time you change server-side code (anything in `scripts/`), you need to re-export and re-upload the `.pck`. The game ID may change with each new upload — update `GAMEFLOW_GAME_ID` in `.env.local` accordingly.

---

## Production deployment

### Supabase

#### 1. Create a Supabase project

Go to [supabase.com](https://supabase.com), create a new project, and note your:
- **Project URL**: `https://<ref>.supabase.co`
- **Anon key**: Settings → API → Project API keys → `anon public`
- **Project ref**: the string in your dashboard URL

#### 2. Enable anonymous sign-ins

Dashboard → **Authentication → Providers → Anonymous** → Enable.

#### 3. Apply the database schema

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

Or paste `supabase/migrations/20260326000001_initial.sql` directly in **Dashboard → SQL Editor**.

#### 4. Deploy Edge Functions

```bash
supabase functions deploy
```

Or paste each `index.ts` in **Dashboard → Edge Functions → New Function**.

#### 5. Set secrets

```bash
supabase secrets set GAMEFLOW_GAME_ID=<your-game-id>
supabase secrets set GAMEFLOW_API_KEY=<your-api-key>
```

Or go to **Dashboard → Settings → Edge Functions → Secrets**.

> `SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected automatically — do not set them manually.

#### 6. Update the game client

Edit `addons/supabase/.env`:

```ini
[supabase/config]

supabaseUrl="https://<your-project-ref>.supabase.co"
supabaseKey="<your anon key>"
```

Then rebuild and redistribute the client.

---

## Environment variables reference

### `supabase/functions/.env.local` (local dev only)

| Variable | Description |
|---|---|
| `GAMEFLOW_GAME_ID` | Your GameFlow game ID (changes on each upload) |
| `GAMEFLOW_API_KEY` | Your GameFlow API key |

### Supabase secrets (production)

Same variables as above, set via `supabase secrets set` or the dashboard.

### Auto-injected by Supabase (do not set manually)

| Variable | Description |
|---|---|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | Your Supabase anon key |

---

## GameFlow integration

This project uses GameFlow's fleet allocation endpoint to spin up dedicated servers on demand.

**Endpoint:** `POST https://dev.api.gameflow.gg/v1/fleets/{gameId}/allocate`

**Called by:** `supabase/functions/lobbies-start/index.ts` when the lobby owner starts the match.

**Flow:**
1. Edge function sends player list and region to GameFlow
2. GameFlow returns `{ allocation: { address, port, serverName } }`
3. Edge function stores `server_address` and `server_port` in the lobby row
4. Supabase Realtime fires an `UPDATE` event on the lobbies table
5. All clients in the lobby receive the event and connect via ENet

The game server uses the **Agones SDK** (`addons/agones/`) to communicate its lifecycle to GameFlow:
- `ready()` — server is ready to receive players
- `health()` — heartbeat ping every 5 seconds
- `player_connect(id)` / `player_disconnect(id)` — player tracking
- `shutdown()` — server requests termination when the game ends

---

## Gameplay

- **WASD / Arrow keys** — move
- **SPACE** — cycle shape (Circle → Square → Triangle → Circle)
- **ESC** — surrender (press twice to confirm) or exit if already dead

**Kill rule:** Circle kills Square, Square kills Triangle, Triangle kills Circle.

Enemies spawn from screen edges and move toward the nearest living player. Difficulty increases every 10 seconds. The game ends when all players are dead.

---

## License

MIT
