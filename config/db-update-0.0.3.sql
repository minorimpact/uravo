USE uravo;

ALTER TABLE network ADD default_interface_name VARCHAR(10) AFTER network_order;

UPDATE network SET default_interface_name='eth0' WHERE network='backnet';
UPDATE network SET default_interface_name='eth1' WHERE network='frontnet';
