ALTER TABLE :keyspace.to2_sessions
ALTER COLUMN sevk TYPE session_key,
ALTER COLUMN svk TYPE session_key,
ALTER COLUMN sek TYPE session_key;