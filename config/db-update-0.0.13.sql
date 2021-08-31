USE uravo;

CREATE INDEX new_alert_processed_idx ON new_alert(Processed);

ALTER TABLE alert_summary ADD Agent varchar(64) after AlertGroup;
ALTER TABLE alert_summary ADD recurring INT DEFAULT 0 AFTER Agent;
ALTER TABLE alert_summary ADD reported INT DEFAULT 0 AFTER recurring;

DROP TABLE recurring_alert;

CREATE TABLE `processed_alert` (
      `Identifier` varchar(255) NOT NULL,
      `Serial` int(11) NOT NULL AUTO_INCREMENT,
      `Agent` varchar(64) DEFAULT NULL,
      `AlertGroup` varchar(255) DEFAULT NULL,
      `AlertKey` varchar(255) DEFAULT NULL,
      `Severity` int(11) DEFAULT NULL,
      `Summary` varchar(255) DEFAULT NULL,
      `Type` int(11) DEFAULT NULL,
      `Tally` int(11) DEFAULT '1',
      `Class` int(11) DEFAULT NULL,
      `AdditionalInfo` varchar(4096) DEFAULT NULL,
      `server_id` varchar(64) DEFAULT NULL,
      `RulePath` varchar(1024) DEFAULT NULL,
      `type_id` varchar(64) DEFAULT NULL,
      `cluster_id` varchar(64) DEFAULT NULL,
      `cage_id` int(11) DEFAULT NULL,
      `rack_id` varchar(64) DEFAULT NULL,
      `Ticket` varchar(20) DEFAULT NULL,
      `Action` int(11) DEFAULT NULL,
      `ActionData` varchar(255) DEFAULT NULL,
      `silo_id` varchar(20) DEFAULT NULL,
      `SiteList` varchar(4096) DEFAULT NULL,
      `Depth` int(11) DEFAULT NULL,
      `DeletedBy` varchar(64) DEFAULT NULL,
      `Recurring` int(11) DEFAULT NULL,
      `SuppressEscl` int(11) NOT NULL DEFAULT '0',
      `Timeout` int(11) DEFAULT NULL,
      PRIMARY KEY (`Serial`)
);

ALTER TABLE new_alert DROP Processed;

