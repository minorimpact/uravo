USE uravo;

UPDATE monitoring_default_values SET AlertKey="" WHERE AlertKey is Null;
ALTER TABLE monitoring_default_values CHANGE AlertKey AlertKey varchar(255) NOT NULL;
