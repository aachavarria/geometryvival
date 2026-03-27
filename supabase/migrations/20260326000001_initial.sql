-- ─────────────────────────────────────────────────────────────────────────────
-- Schema
-- ─────────────────────────────────────────────────────────────────────────────

-- One account per auth user, storing the chosen display name.
CREATE TABLE public.accounts (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  username   TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id)
);

-- A lobby is a pre-game room. Status moves from 'waiting' → 'started'.
CREATE TABLE public.lobbies (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code           TEXT        NOT NULL UNIQUE,
  is_private     BOOLEAN     NOT NULL DEFAULT FALSE,
  owner_id       UUID        NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  status         TEXT        NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'started')),
  -- Populated by lobbies-start when GameFlow allocates a server.
  server_address TEXT,
  server_port    INT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row per player per lobby.
CREATE TABLE public.lobby_players (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  lobby_id   UUID        NOT NULL REFERENCES public.lobbies(id) ON DELETE CASCADE,
  account_id UUID        NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  username   TEXT        NOT NULL,
  team       TEXT        NOT NULL DEFAULT 'A' CHECK (team IN ('A', 'B')),
  ready      BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(lobby_id, account_id)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Row Level Security
-- All mutations go through edge functions using the service role key,
-- so client-facing RLS is permissive; the edge functions enforce business logic.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.accounts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lobbies       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lobby_players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "accounts_select" ON public.accounts FOR SELECT USING (true);
CREATE POLICY "accounts_insert" ON public.accounts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "accounts_update" ON public.accounts FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "lobbies_select" ON public.lobbies FOR SELECT USING (true);
CREATE POLICY "lobbies_insert" ON public.lobbies FOR INSERT WITH CHECK (true);
CREATE POLICY "lobbies_update" ON public.lobbies FOR UPDATE USING (true);
CREATE POLICY "lobbies_delete" ON public.lobbies FOR DELETE USING (true);

CREATE POLICY "lp_select" ON public.lobby_players FOR SELECT USING (true);
CREATE POLICY "lp_insert" ON public.lobby_players FOR INSERT WITH CHECK (true);
CREATE POLICY "lp_update" ON public.lobby_players FOR UPDATE USING (true);
CREATE POLICY "lp_delete" ON public.lobby_players FOR DELETE USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- Realtime
-- ─────────────────────────────────────────────────────────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE public.lobbies;
ALTER PUBLICATION supabase_realtime ADD TABLE public.lobby_players;
