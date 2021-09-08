USE uravo;

UPDATE monitoring_default_values SET AlertKey="" WHERE AlertKey is Null;
ALTER TABLE monitoring_default_values CHANGE AlertKey AlertKey varchar(255) NOT NULL;

ALTER TABLE bu ADD `default` INT NOT NULL DEFAULT 0;
UPDATE bu SET `default`= 1 WHERE bu_id='unknown'; 

ALTER TABLE silo ADD `default` INT NOT NULL DEFAULT 0;
UPDATE silo SET `default`= 1 WHERE silo_id='unknown';

UPDATE monitoring_values SET AlertKey="" WHERE AlertKey is Null;
UPDATE monitoring_values SET cluster_id="" WHERE cluster_id is Null;
UPDATE monitoring_values SET type_id="" WHERE type_id is Null;
UPDATE monitoring_values SET server_id="" WHERE server_id is Null;
ALTER TABLE monitoring_values CHANGE AlertKey AlertKey varchar(255) NOT NULL;
ALTER TABLE monitoring_values CHANGE cluster_id cluster_id varchar(255) NOT NULL;
ALTER TABLE monitoring_values CHANGE type_id type_id varchar(255) NOT NULL;
ALTER TABLE monitoring_values CHANGE server_id server_id varchar(255) NOT NULL;