DROP DATABASE IF EXISTS `uravo`;
CREATE DATABASE `uravo`;

USE uravo;

DROP TABLE IF EXISTS `action`;
CREATE TABLE `action` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `where_str` varchar(255) NOT NULL,
  `action` varchar(10) NOT NULL,
  `actionorder` int(11) NOT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  PRIMARY KEY (`id`)
);


DROP TABLE IF EXISTS `alert`;
CREATE TABLE `alert` (
  `Identifier` varchar(255) NOT NULL,
  `Serial` int(11) NOT NULL AUTO_INCREMENT,
  `Agent` varchar(64) DEFAULT NULL,
  `AlertGroup` varchar(255) DEFAULT NULL,
  `AlertKey` varchar(255) DEFAULT NULL,
  `Severity` int(11) DEFAULT NULL,
  `Summary` varchar(255) DEFAULT NULL,
  `StateChange` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `FirstOccurrence` datetime NOT NULL,
  `LastOccurrence` datetime DEFAULT NULL,
  `Type` int(11) DEFAULT NULL,
  `Tally` int(11) DEFAULT '1',
  `Class` int(11) DEFAULT NULL,
  `Acknowledged` int(11) NOT NULL,
  `SuppressEscl` int(11) NOT NULL DEFAULT '0',
  `AdditionalInfo` varchar(4096) DEFAULT NULL,
  `server_id` varchar(64) DEFAULT NULL,
  `RulePath` varchar(1024) DEFAULT NULL,
  `type_id` varchar(64) DEFAULT NULL,
  `cluster_id` varchar(64) DEFAULT NULL,
  `cage_id` int(11) DEFAULT '1',
  `rack_id` varchar(64) DEFAULT NULL,
  `EventLevel` int(11) DEFAULT NULL,
  `Ticket` varchar(20) DEFAULT NULL,
  `Note` text,
  `ParentIdentifier` varchar(255) DEFAULT NULL,
  `Action` int(11) DEFAULT NULL,
  `ActionData` varchar(255) DEFAULT NULL,
  `silo_id` varchar(20) DEFAULT NULL,
  `SiteList` varchar(4096) DEFAULT NULL,
  `Depth` int(11) DEFAULT NULL,
  `DeletedBy` varchar(64) DEFAULT NULL,
  `Recurring` int(11) DEFAULT '0',
  `AlertCount` int(11) DEFAULT '0',
  `Timeout` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Serial`),
  UNIQUE KEY `alert_Identifier_idx` (`Identifier`),
  KEY `alert_idx` (`AlertGroup`,`SuppressEscl`,`Severity`,`EventLevel`),
  KEY `alert_id_idx` (`server_id`, `AlertGroup`, `AlertKey`)
);

DELIMITER ;;
CREATE trigger insert_alert AFTER INSERT on alert
for each row
BEGIN
insert into historical_alert (Identifier,  Serial ,  Agent ,   AlertGroup,   AlertKey ,   Severity ,   Summary ,  StateChange, FirstOccurrence ,   LastOccurrence ,  Type ,  Tally ,   Class ,   Acknowledged ,   SuppressEscl ,   AdditionalInfo ,   server_id ,  RulePath ,  type_id ,  cluster_id ,   cage_id ,  rack_id ,  EventLevel ,  Ticket ,  Note ,  ParentIdentifier ,  Action ,  ActionData ,  silo_id ,  SiteList ,   Depth ,  DeletedBy ,   Recurring ,   AlertCount) VALUES (NEW.Identifier,NEW.Serial,NEW.Agent,NEW.AlertGroup,NEW.AlertKey,NEW.Severity,NEW.Summary,NEW.StateChange,NEW.FirstOccurrence,NEW.LastOccurrence,NEW.Type,NEW.Tally,NEW.Class,NEW.Acknowledged,NEW.SuppressEscl,NEW.AdditionalInfo,NEW.server_id,NEW.RulePath,NEW.type_id,NEW.cluster_id,NEW.cage_id,NEW.rack_id,NEW.EventLevel,NEW.Ticket,NEW.Note,NEW.ParentIdentifier,NEW.Action,NEW.ActionData,NEW.silo_id,NEW.SiteList,NEW.Depth,NEW.DeletedBy,NEW.Recurring,NEW.AlertCount);
insert into historical_Severity (Serial, Severity, state, create_date) values (NEW.Serial, NEW.Severity, 1, NOW());
insert into historical_Summary (Serial, Summary, state, create_date) values (NEW.Serial, NEW.Summary, 1, NOW());
insert into historical_ParentIdentifier (Serial, ParentIdentifier, state, create_date) values (NEW.Serial, NEW.ParentIdentifier, 1, NOW());
insert into historical_Acknowledged (Serial, Acknowledged, state, create_date) values (NEW.Serial, NEW.Acknowledged, 1, NOW());
insert into historical_Ticket (Serial, Ticket, state, create_date) values (NEW.Serial, NEW.Ticket, 1, NOW());
insert into historical_SuppressEscl (Serial, SuppressEscl, state, create_date) values (NEW.Serial, NEW.SuppressEscl, 1, NOW());
END ;;
DELIMITER ;

DELIMITER ;;
CREATE trigger update_alert AFTER UPDATE on alert
for each row
BEGIN
     update historical_alert set Identifier = NEW.Identifier,  Serial = NEW.Serial,  Agent = NEW.Agent,  AlertGroup = NEW.AlertGroup,  AlertKey = NEW.AlertKey,  Severity = NEW.Severity,  Summary = NEW.Summary,  StateChange = NEW.StateChange,  FirstOccurrence = NEW.FirstOccurrence,  LastOccurrence = NEW.LastOccurrence,  Type = NEW.Type,  Tally = NEW.Tally,  Class = NEW.Class,  Acknowledged = NEW.Acknowledged,  SuppressEscl = NEW.SuppressEscl,  AdditionalInfo = NEW.AdditionalInfo,  server_id = NEW.server_id,  RulePath = NEW.RulePath,  type_id = NEW.type_id,  cluster_id = NEW.cluster_id,  cage_id = NEW.cage_id,  rack_id = NEW.rack_id,  EventLevel = NEW.EventLevel,  Ticket = NEW.Ticket,  Note = NEW.Note,  ParentIdentifier = NEW.ParentIdentifier,  Action = NEW.Action,  ActionData = NEW.ActionData,  silo_id = NEW.silo_id,  SiteList = NEW.SiteList,  Depth = NEW.Depth,  DeletedBy = NEW.DeletedBy,  Recurring = NEW.Recurring,  AlertCount = NEW.AlertCount WHERE Serial=OLD.Serial;
IF NEW.Severity != OLD.Severity THEN
     update historical_Severity set state=0 where state=1 and Serial=OLD.Serial;
     insert into historical_Severity (Serial, Severity, state, create_date) values (OLD.Serial, NEW.Severity, 1, NOW());
     update historical_Summary set state=0 where state=1 and Serial=OLD.Serial;
     insert into historical_Summary (Serial, Summary, state, create_date) values (OLD.Serial, NEW.Summary, 1, NOW());
END IF;
IF NEW.ParentIdentifier != OLD.ParentIdentifier THEN
     update historical_ParentIdentifier set state=0 where state=1 and Serial=OLD.Serial;
     insert into historical_ParentIdentifier (Serial, ParentIdentifier, state, create_date) values (OLD.Serial, NEW.ParentIdentifier, 1, NOW());
END IF;
IF NEW.Acknowledged != OLD.Acknowledged THEN
     update historical_Acknowledged set state=0 where state=1 and Serial=OLD.Serial;
     insert into historical_Acknowledged (Serial, Acknowledged, state, create_date) values (OLD.Serial, NEW.Acknowledged, 1, NOW());
END IF;
IF NEW.Ticket != OLD.Ticket THEN
     update historical_Ticket set state=0 where state=1 and Serial=OLD.Serial;
     insert into historical_Ticket (Serial, Ticket, state, create_date) values (OLD.Serial, NEW.Ticket, 1, NOW());
END IF;
IF NEW.SuppressEscl != OLD.SuppressEscl THEN
     update historical_SuppressEscl set state=0 where state=1 and Serial=OLD.Serial;
     insert into historical_SuppressEscl (Serial, SuppressEscl, state, create_date) values (OLD.Serial, NEW.SuppressEscl, 1, NOW());
END IF;

END ;;
DELIMITER ;

DELIMITER ;;
CREATE  trigger delete_alert AFTER DELETE on alert
for each row 
BEGIN
update historical_alert set DeletedAt=NOW() WHERE Serial=OLD.Serial;
END ;;
DELIMITER ;


DROP TABLE IF EXISTS `alert_journal`;
CREATE TABLE `alert_journal` (
  `Serial` int(11) NOT NULL,
  `user_id` varchar(50) DEFAULT NULL,
  `entry` varchar(255) DEFAULT NULL,
  `create_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);


DROP TABLE IF EXISTS `alert_summary`;
CREATE TABLE `alert_summary` (
  `server_id` varchar(50) NOT NULL,
  `AlertGroup` varchar(255) DEFAULT NULL,
  `Agent` varchar(64) DEFAULT NULL,
  `recurring` INT DEFAULT 0,
  `reported` INT DEFAULT 0,
  `mod_date` datetime NOT NULL,
  UNIQUE KEY `alert_summary_idx` (`server_id`,`AlertGroup`)
);


DROP TABLE IF EXISTS `bu`;
CREATE TABLE `bu` (
  `bu_id` varchar(20) NOT NULL,
  `name` varchar(50) NOT NULL,
  `contact` varchar(50) DEFAULT NULL,
  `comments` text,
  `default` int NOT NULL DEFAULT 0,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  PRIMARY KEY (`bu_id`)
);


DROP TABLE IF EXISTS `cage`;
CREATE TABLE `cage` (
  `cage_id` varchar(15) NOT NULL,
  `prefix` char(10) NOT NULL,
  `city` varchar(50) DEFAULT NULL,
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`cage_id`)
);


DROP TABLE IF EXISTS `changelog`;
CREATE TABLE `changelog` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `object_id` varchar(50) DEFAULT NULL,
  `object_type` varchar(15) NOT NULL,
  `user` varchar(50) NOT NULL,
  `ticket` varchar(15) DEFAULT NULL,
  `note` varchar(50) DEFAULT NULL,
  `create_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
);


DROP TABLE IF EXISTS `changelog_detail`;
CREATE TABLE `changelog_detail` (
  `changelog_id` int(11) NOT NULL,
  `field_name` varchar(50) NOT NULL,
  `old_value` varchar(255) DEFAULT NULL,
  `new_value` varchar(255) DEFAULT NULL,
  KEY `changelog_detail_id` (`changelog_id`)
);


DROP TABLE IF EXISTS `check_data`;
CREATE TABLE `check_data` (
  `server_id` varchar(50) NOT NULL DEFAULT '',
  `AlertGroup` varchar(50) NOT NULL DEFAULT '',
  `AlertKey` varchar(255) NOT NULL DEFAULT '',
  `value` text,
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`server_id`,`AlertGroup`,`AlertKey`)
);


DROP TABLE IF EXISTS `cluster`;
CREATE TABLE `cluster` (
  `cluster_id` varchar(20) NOT NULL DEFAULT '',
  `description` text,
  `comments` text,
  `silo_id` varchar(20) DEFAULT 'core',
  `silo_default` int(11) DEFAULT '0',
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `cluster_id` (`cluster_id`),
  UNIQUE KEY `cluster_idx` (`cluster_id`),
  KEY `silo_id_idx` (`silo_id`)
);


DROP TABLE IF EXISTS `cluster_netblock`;
CREATE TABLE `cluster_netblock` (
  `cluster_id` varchar(20) NOT NULL,
  `netblock_id` varchar(20) NOT NULL,
  `create_date` datetime NOT NULL,
  UNIQUE KEY `cluster_netblock_idx` (`cluster_id`,`netblock_id`)
);


DROP TABLE IF EXISTS `contacts`;
CREATE TABLE `contacts` (
  `contact_group` varchar(25) NOT NULL DEFAULT '',
  `default_group` tinyint(4) DEFAULT '0',
  `primary_email` varchar(50) NOT NULL DEFAULT '',
  `primary_pager` varchar(50) NOT NULL DEFAULT '',
  `secondary_email` varchar(50) NOT NULL DEFAULT '',
  `secondary_pager` varchar(50) NOT NULL DEFAULT '',
  `tertiary_email` varchar(50) NOT NULL DEFAULT '',
  `tertiary_pager` varchar(50) NOT NULL DEFAULT '',
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);


DROP TABLE IF EXISTS `cron_eta`;
CREATE TABLE `cron_eta` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `eta` int(11) DEFAULT '180',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name_idx` (`name`)
);


DROP TABLE IF EXISTS `cron_log`;
CREATE TABLE `cron_log` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `server_id` varchar(50) DEFAULT NULL,
  `name` varchar(255) NOT NULL,
  `pid` int(11) DEFAULT NULL,
  `start_date` datetime NOT NULL,
  `sleep` int(11) DEFAULT '0',
  `eta_date` datetime DEFAULT NULL,
  `end_date` datetime DEFAULT NULL,
  `exit_status` int(11) DEFAULT NULL,
  `error_output` text,
  PRIMARY KEY (`id`),
  UNIQUE KEY `server_name_pid_start_idx` (`server_id`,`name`,`pid`,`start_date`)
);


DROP TABLE IF EXISTS `deleted_server`;
CREATE TABLE `deleted_server` (
  `server_id` varchar(50) NOT NULL DEFAULT '',
  `create_date` datetime DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY `deleted_server_idx` (`server_id`)
);


DROP TABLE IF EXISTS `diskinfo`;
CREATE TABLE `diskinfo` (
  `server_id` varchar(50) NOT NULL,
  `name` varchar(25) NOT NULL,
  `size` int(11) DEFAULT NULL,
  `mounted_on` varchar(100) DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `idx_diskinfo` (`server_id`,`name`)
);


DROP TABLE IF EXISTS `escalations`;
CREATE TABLE `escalations` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `cluster_id` varchar(20) NOT NULL DEFAULT '',
  `type_id` varchar(20) NOT NULL DEFAULT '',
  `AlertGroup` varchar(50) DEFAULT '',
  `contact_group` varchar(25) NOT NULL DEFAULT '',
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `escalations_idx` (`cluster_id`,`type_id`,`AlertGroup`)
);


DROP TABLE IF EXISTS `filter`;
CREATE TABLE `filter` (
  `id` varchar(25) NOT NULL,
  `where_str` varchar(255) NOT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  PRIMARY KEY (`id`)
);


DROP TABLE IF EXISTS `hardware_detail`;
CREATE TABLE `hardware_detail` (
  `id` varchar(50) NOT NULL DEFAULT '',
  `vendor` varchar(50) DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`id`)
);


DROP TABLE IF EXISTS `historical_Acknowledged`;
CREATE TABLE `historical_Acknowledged` (
  `Serial` int(11) NOT NULL,
  `Acknowledged` int(11) NOT NULL,
  `state` int(11) DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  KEY `historical_Acknowledged_idx` (`Serial`)
);


DROP TABLE IF EXISTS `historical_ParentIdentifier`;
CREATE TABLE `historical_ParentIdentifier` (
  `Serial` int(11) NOT NULL,
  `ParentIdentifier` varchar(255) DEFAULT NULL,
  `state` int(11) DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  KEY `historical_ParentIdentifier_idx` (`Serial`)
);


DROP TABLE IF EXISTS `historical_Severity`;
CREATE TABLE `historical_Severity` (
  `Serial` int(11) NOT NULL,
  `Severity` int(11) NOT NULL,
  `state` int(11) NOT NULL DEFAULT '0',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  KEY `historical_Severity_idx` (`Serial`)
);


DROP TABLE IF EXISTS `historical_Summary`;
CREATE TABLE `historical_Summary` (
  `Serial` int(11) NOT NULL,
  `Summary` varchar(255) NOT NULL,
  `state` int(11) NOT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  KEY `historical_Summary_idx` (`Serial`)
);


DROP TABLE IF EXISTS `historical_SuppressEscl`;
CREATE TABLE `historical_SuppressEscl` (
  `Serial` int(11) NOT NULL,
  `SuppressEscl` int(11) NOT NULL,
  `state` int(11) DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  KEY `historical_SuppressEscl_idx` (`Serial`)
);


DROP TABLE IF EXISTS `historical_Ticket`;
CREATE TABLE `historical_Ticket` (
  `Serial` int(11) NOT NULL,
  `Ticket` varchar(20) DEFAULT NULL,
  `state` int(11) DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  KEY `historical_Ticket_idx` (`Serial`)
);


DROP TABLE IF EXISTS `historical_alert`;
CREATE TABLE `historical_alert` (
  `Identifier` varchar(255) NOT NULL,
  `Serial` int(11) NOT NULL,
  `Agent` varchar(64) DEFAULT NULL,
  `AlertGroup` varchar(255) DEFAULT NULL,
  `AlertKey` varchar(255) DEFAULT NULL,
  `Severity` int(11) DEFAULT NULL,
  `Summary` varchar(255) DEFAULT NULL,
  `StateChange` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `FirstOccurrence` datetime NOT NULL,
  `LastOccurrence` datetime DEFAULT NULL,
  `Type` int(11) DEFAULT NULL,
  `Tally` int(11) DEFAULT '1',
  `Class` int(11) DEFAULT NULL,
  `Acknowledged` int(11) DEFAULT NULL,
  `SuppressEscl` int(11) NOT NULL DEFAULT '1',
  `AdditionalInfo` varchar(4096) DEFAULT NULL,
  `server_id` varchar(64) DEFAULT NULL,
  `RulePath` varchar(1024) DEFAULT NULL,
  `type_id` varchar(64) DEFAULT NULL,
  `cluster_id` varchar(64) DEFAULT NULL,
  `cage_id` int(11) DEFAULT '1',
  `rack_id` varchar(64) DEFAULT NULL,
  `EventLevel` int(11) DEFAULT NULL,
  `Ticket` varchar(20) DEFAULT NULL,
  `Note` text,
  `ParentIdentifier` varchar(255) DEFAULT NULL,
  `Action` int(11) DEFAULT NULL,
  `ActionData` varchar(255) DEFAULT NULL,
  `silo_id` varchar(20) DEFAULT NULL,
  `SiteList` varchar(4096) DEFAULT NULL,
  `Depth` int(11) DEFAULT NULL,
  `DeletedBy` varchar(64) DEFAULT NULL,
  `Recurring` int(11) DEFAULT '0',
  `AlertCount` int(11) DEFAULT '0',
  `DeletedAt` datetime DEFAULT NULL,
  PRIMARY KEY (`Serial`)
);


DROP TABLE IF EXISTS `interface`;
CREATE TABLE `interface` (
  `interface_id` int(11) NOT NULL AUTO_INCREMENT,
  `server_id` varchar(50) NOT NULL DEFAULT '',
  `name` varchar(50) DEFAULT NULL,
  `ip` varchar(18) DEFAULT NULL,
  `netblock_id` varchar(20) DEFAULT NULL,
  `network` varchar(18) DEFAULT NULL,
  `mac` varchar(17) DEFAULT NULL,
  `main` BOOLEAN DEFAULT NULL,
  `icmp` BOOLEAN DEFAULT TRUE,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`interface_id`),
  KEY `interface_server_idx` (`server_id`),
  KEY `interface_network_idx` (`network`)
);


DROP TABLE IF EXISTS `interface_alias`;
CREATE TABLE `interface_alias` (
  `interface_id` int(11) NOT NULL,
  `alias` varchar(50) NOT NULL,
  `create_date` datetime NOT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `interface_alias_interface_alias_idx` (`interface_id`,`alias`)
);


DROP TABLE IF EXISTS `module`;
CREATE TABLE `module` (
  `module_id` varchar(20) NOT NULL,
  `remote` int(11) NOT NULL DEFAULT '0',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  PRIMARY KEY (`module_id`)
);


DROP TABLE IF EXISTS `monitoring_default_values`;
CREATE TABLE `monitoring_default_values` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `AlertGroup` varchar(50) NOT NULL,
  `AlertKey` varchar(255) NOT NULL,
  `description` text,
  `yellow` float DEFAULT NULL,
  `red` float DEFAULT NULL,
  `disabled` tinyint(1) DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`id`),
  UNIQUE KEY `monitoring_default_values_idx` (`AlertGroup`,`AlertKey`)
);


DROP TABLE IF EXISTS `monitoring_values`;
CREATE TABLE `monitoring_values` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `AlertGroup` varchar(50) NOT NULL,
  `AlertKey` varchar(255) NOT NULL,
  `cluster_id` varchar(20) NOT NULL,
  `type_id` varchar(20) NOT NULL,
  `server_id` varchar(50) NOT NULL,
  `yellow` float DEFAULT NULL,
  `red` float DEFAULT NULL,
  `disabled` tinyint(1) DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`id`),
  UNIQUE KEY `monitoring_values_idx` (`AlertGroup`,`AlertKey`,`cluster_id`,`type_id`,`server_id`)
);


DROP TABLE IF EXISTS `netblock`;
CREATE TABLE `netblock` (
  `netblock_id` varchar(20) NOT NULL DEFAULT '',
  `silo_id` varchar(20) DEFAULT NULL,
  `address` varchar(18) NOT NULL DEFAULT '',
  `network` varchar(18) NOT NULL DEFAULT '',
  `discovery` tinyint(1) NOT NULL DEFAULT '1',
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`netblock_id`)
);


DROP TABLE IF EXISTS `network`;
CREATE TABLE `network` (
  `network` varchar(20) NOT NULL,
  `network_order` int(11) NOT NULL,
  `default_interface_name` varchar(10),
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  PRIMARY KEY (`network`)
);


DROP TABLE IF EXISTS `new_alert`;
CREATE TABLE `new_alert` (
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
  `Timeout` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`Serial`)
);


DROP TABLE IF EXISTS `process`;
CREATE TABLE `process` (
  `process_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(32) NOT NULL DEFAULT '',
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`process_id`)
);


DROP TABLE IF EXISTS `processed_alert`;
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


DROP TABLE IF EXISTS `rack`;
CREATE TABLE `rack` (
  `rack_id` varchar(20) NOT NULL,
  `cage_id` varchar(20) NOT NULL,
  `x_pos` int(11) DEFAULT NULL,
  `y_pos` int(11) DEFAULT NULL,
  `create_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`rack_id`),
  UNIQUE KEY `rack_cage_idx` (`rack_id`,`cage_id`)
);


DROP TABLE IF EXISTS `rootcause`;
CREATE TABLE `rootcause` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `where_str` varchar(255) NOT NULL,
  `causeorder` int(11) NOT NULL DEFAULT '0',
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  PRIMARY KEY (`id`)
);


DROP TABLE IF EXISTS `rootcause_symptom`;
CREATE TABLE `rootcause_symptom` (
  `rootcause_id` int(11) NOT NULL,
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `where_str` varchar(255) NOT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `rootcause_symptom_idx` (`rootcause_id`)
);


DROP TABLE IF EXISTS `server`;
CREATE TABLE `server` (
  `server_id` varchar(50) NOT NULL DEFAULT '',
  `serial_number` varchar(32) DEFAULT NULL,
  `hostname` varchar(50) DEFAULT NULL,
  `cluster_id` varchar(20) NOT NULL,
  `description` varchar(250) DEFAULT NULL,
  `mem` int(11) DEFAULT NULL,
  `rack_id` varchar(20) NOT NULL,
  `position` int(11) DEFAULT NULL,
  `check_conn` int(11) DEFAULT '1',
  `check_snmp` int(11) DEFAULT '1',
  `comments` text,
  `os_vendor` varchar(48) DEFAULT NULL,
  `os_version` varchar(16) DEFAULT NULL,
  `os_bit` tinyint(4) DEFAULT '32',
  `os_kernel` varchar(32) DEFAULT NULL,
  `os_arch` varchar(6) DEFAULT NULL,
  `cpu_count` smallint(6) DEFAULT NULL,
  `cpu_physical_count` int(11) DEFAULT NULL,
  `cpu_cores` tinyint(4) NOT NULL DEFAULT '0',
  `cpu_cache_kb` smallint(6) NOT NULL DEFAULT '0',
  `cpu_name` varchar(50) DEFAULT NULL,
  `cpu_mhz` float DEFAULT NULL,
  `cpu_bogomips` float DEFAULT NULL,
  `bus_speed` mediumint(9) NOT NULL DEFAULT '0',
  `server_model` varchar(50) DEFAULT NULL,
  `service_tag` varchar(10) DEFAULT NULL,
  `asset_tag` varchar(10) DEFAULT NULL,
  `perl_version` varchar(7) DEFAULT NULL,
  `perl_arch` varchar(30) DEFAULT NULL,
  `uravo_version VARCHAR(15) DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`server_id`),
  UNIQUE KEY `hostname` (`hostname`),
  KEY `server_rack_id_idx` (`rack_id`)
);


DROP TABLE IF EXISTS `server_type`;
CREATE TABLE `server_type` (
  `server_id` varchar(50) NOT NULL,
  `type_id` varchar(20) NOT NULL,
  `create_date` datetime NOT NULL,
  KEY `server_type_idx` (`server_id`,`type_id`)
);


DROP TABLE IF EXISTS `settings`;
CREATE TABLE `settings` (
  `name` varchar(50) NOT NULL,
  `value` varchar(50) NOT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS `silo`;
CREATE TABLE `silo` (
  `silo_id` varchar(20) NOT NULL,
  `comments` text,
  `bu_id` varchar(20) NOT NULL,
  `default` int NOT NULL DEFAULT 0,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `create_date` datetime NOT NULL,
  PRIMARY KEY (`silo_id`)
);


DROP TABLE IF EXISTS `type`;
CREATE TABLE `type` (
  `type_id` varchar(20) NOT NULL DEFAULT '',
  `comments` text,
  `auto_id_type` varchar(25) DEFAULT NULL,
  `auto_id_source` varchar(255) DEFAULT NULL,
  `auto_id_text` varchar(255) DEFAULT NULL,
  `community` varchar(50) DEFAULT NULL,
  `create_date` datetime DEFAULT NULL,
  `mod_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `type_id` (`type_id`),
  UNIQUE KEY `type_id_idx` (`type_id`)
);


DROP TABLE IF EXISTS `type_log`;
CREATE TABLE type_log (
  id INT NOT NULL auto_increment PRIMARY KEY,
  type_id VARCHAR(50) NOT NULL,
  log_file VARCHAR(100), 
  mod_date TIMESTAMP NOT NULL, 
  create_date DATETIME,
  UNIQUE KEY `type_log_idx` (`type_id`, `log_file`)
);


DROP TABLE IF EXISTS `type_log_detail`;
CREATE TABLE type_log_detail (
    id INT NOT NULL auto_increment PRIMARY KEY,
    type_log_id int not null, 
    regex varchar(50) not null, 
    mod_date timestamp not null,
    create_date datetime not null,
    UNIQUE KEY `type_log_detail_idx` (`type_log_id`,`regex`)
);


DROP TABLE IF EXISTS `type_module`;
CREATE TABLE `type_module` (
  `type_id` varchar(20) NOT NULL,
  `module_id` varchar(20) NOT NULL,
  `enabled` BOOLEAN DEFAULT TRUE NOT NULL,
  `create_date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `type_module_idx` (`type_id`,`module_id`)
);


DROP TABLE IF EXISTS `type_process`;
CREATE TABLE `type_process` (
  `type_id` varchar(20) NOT NULL DEFAULT '',
  `process_id` int(11) NOT NULL DEFAULT '0',
  `yellow` varchar(5) DEFAULT '',
  `red` varchar(5) DEFAULT '',
  UNIQUE KEY `type_id` (`type_id`,`process_id`)
);

