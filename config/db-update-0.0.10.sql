USE uravo;

INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'inode_size',NULL,'Maximum percentage of inodes in use.',75,90,0,NOW(),NOW());

ALTER TABLE recurring_alert DROP INDEX recurring_alert_idx;
DELETE FROM recurring_alert;
CREATE UNIQUE INDEX recurring_alert_idx ON recurring_alert (server_id, AlertGroup);

ALTER TABLE new_alert ADD Timeout INT AFTER SuppressEscl;
ALTER TABLE alert ADD Timeout INT AFTER AlertCount;
