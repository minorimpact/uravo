USE uravo;

ALTER TABLE recurring_alert DROP INDEX recurring_alert_idx;
ALTER TABLE recurring_alert DROP AlertKey;
CREATE INDEX recurring_alert_idx ON recurring_alert (server_id, AlertGroup);

INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('ifconfig',0,NOW(), NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','ifconfig',NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'ifconfig_carrier',NULL,'',.5,1,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'ifconfig_dropped',NULL,'',.5,1,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'ifconfig_overruns',NULL,'',.5,1,0,NOW(),NOW());

INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('ntp',0,NOW(), NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','ntp',NOW());

INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('run',0,NOW(), NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','run',NOW());

INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('iostat',0,NOW(), NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','iostat',NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'iostat_iowait',NULL,'',35,50,0,NOW(),NOW());

INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('config',0,NOW(), NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','config',NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'config_promises',NULL,'Percent of promises not kept.',1,2,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'config_runtime',NULL,'Amount of time configuration should run, in minutes.',10,15,0,NOW(),NOW());

INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('disk', 0, NOW(), NOW());

INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('squid',0,NOW(), NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'squid_cpu',NULL,'Maximum CPU percentage for squid process.',80, 90, 0, NOW(), NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'squid_hitrate',NULL,'Minimum hit rate.', 50, 25, 0, NOW(), NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'squid_missrate',NULL,'Maximum miss rate.', 50, 75, 0, NOW(), NOW());

ALTER TABLE server ADD uravo_version VARCHAR(15) AFTER perl_arch;
CREATE TABLE type_log (id INT NOT NULL auto_increment PRIMARY KEY, type_id VARCHAR(50) NOT NULL, log_file VARCHAR(100), mod_date TIMESTAMP NOT NULL, create_date DATETIME, UNIQUE KEY `type_log_idx` (`type_id`, `log_file`));
CREATE TABLE type_log_detail (id INT NOT NULL auto_increment PRIMARY KEY, type_log_id INT NOT NULL, regex VARCHAR(50) NOT NULL, mod_date TIMESTAMP NOT NULL, create_date DATETIME NOT NULL, UNIQUE KEY `type_log_detail_idx` (`type_log_id`,`regex`));
INSERT INTO type_log (id, type_id, log_file, mod_date, create_date) VALUES (1, 'linux', '/var/log/messages', NOW(), NOW());
INSERT INTO type_log_detail (type_log_id, regex, mod_date, create_date) VALUES (1, 'error', NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('log',0,NOW(), NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','log',NOW());

