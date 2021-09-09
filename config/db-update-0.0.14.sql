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

ALTER TABLE process DROP process_id;
ALTER TABLE process CHANGE name process_id varchar(20) NOT NULL PRIMARY KEY;
ALTER TABLE type_process CHANGE process_id process_id varchar(20) NOT NULL;
UPDATE type_process SET process_id='sshd' WHERE process_id=1;
UPDATE type_process SET process_id='ntpd' WHERE process_id=2;
UPDATE type_process SET process_id='pylon' WHERE process_id=4;
UPDATE type_process SET process_id='outpost.pl' WHERE process_id=6;
UPDATE type_process SET process_id='control.pl' WHERE process_id=7;
UPDATE type_process SET process_id='mysqld' WHERE process_id=8;
UPDATE type_process SET process_id='httpd' WHERE process_id=9;
UPDATE type_process SET process_id='crond' WHERE process_id=10;

