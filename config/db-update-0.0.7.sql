USE uravo;

CREATE INDEX alert_id_idx ON alert (server_id, AlertGroup, AlertKey);
