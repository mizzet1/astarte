CREATE TYPE :keyspace.session_key (
  alg text,
  k blob,
  kty text
);

ALTER TABLE :keyspace.to2_sessions DROP sevk;
ALTER TABLE :keyspace.to2_sessions DROP svk;
ALTER TABLE :keyspace.to2_sessions DROP sek;
ALTER TABLE :keyspace.to2_sessions ADD sevk frozen<session_key>;
ALTER TABLE :keyspace.to2_sessions ADD svk frozen<session_key>;
ALTER TABLE :keyspace.to2_sessions ADD sek frozen<session_key>;
