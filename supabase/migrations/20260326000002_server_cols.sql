-- Store game server info when a match starts
ALTER TABLE public.lobbies ADD COLUMN IF NOT EXISTS server_address TEXT;
ALTER TABLE public.lobbies ADD COLUMN IF NOT EXISTS server_port INT;
