USE uravo;

CREATE INDEX server_type_idx ON server_type (server_id, type_id);
ALTER TABLE interface ADD icmp BOOLEAN DEFAULT TRUE AFTER main;
