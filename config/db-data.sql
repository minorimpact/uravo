USE uravo;

GRANT ALL ON uravo.* to 'uravo'@'%' IDENTIFIED BY 'uravo';
GRANT ALL ON uravo.* to 'uravo'@'localhost' IDENTIFIED BY 'uravo';

INSERT INTO `bu` (bu_id, name, contact, comments, create_date, mod_date) VALUES ('unknown','unknown','unknown','', NOW(), NOW());

INSERT INTO `cage` (`cage_id`, `prefix`, `city`, `create_date`, `mod_date`) VALUES ('unknown', '', '', NOW(), NOW());

INSERT INTO `cluster` (`cluster_id`, `description`, `comments`, `silo_id`, `silo_default`, `create_date`, `mod_date`) VALUES ('unknown',NULL,'','unknown',1,NOW(), NOW());

INSERT INTO `filter` (`id`, `where_str`, `mod_date`, `create_date`) VALUES ('hidden','SuppressEscl = 5 and EventLevel >= 10 and Severity > 3',NOW(),NOW());

INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('bandwidth', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('config', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('conn', 1, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('cpu', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('cron', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('disk', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('http', 1, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('ifconfig', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('iostat', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('log',0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('memory', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('ntp', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('procs', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('run', 0, NOW(), NOW());
INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('squid', 0, NOW(), NOW());

INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'bandwidth_rate',NULL,NULL,50000000,75000000,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'config_promises',NULL,'Percent of promises not kept.',1,2,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'config_runtime',NULL,'Amount of time configuration should run, in minutes.',10,15,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'conn',NULL,NULL,1,2,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'cpu_load_average',NULL,'5 Minute cpu load average.',10,15,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'cpu_yellow_time',NULL,'How long a CPU is allowed to be yellow before generating an alert, in minutes.',30,60,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'disk_fill',NULL,'',120,60,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'disk_size',NULL,'',75,85,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'http_load_time',NULL,'',3,5,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'ifconfig_carrier',NULL,'',.5,1,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'ifconfig_dropped',NULL,'',.5,1,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'ifconfig_overruns',NULL,'',.5,1,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'memory','swap','',75,85,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'procs_total',NULL,'',150,200,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'squid_cpu',NULL,'Maximum CPU percentage for squid process.',80,90,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'squid_hitrate',NULL,'Minimum hit rate.',50,25,0,NOW(),NOW());
INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'squid_missrate',NULL,'Maximum miss rate.',50,75,0,NOW(),NOW());

INSERT INTO `network` (`network`, `network_order`, `default_interface_name`, `mod_date`, `create_date`) VALUES ('backnet',0, 'eth1', NOW(),NOW());
INSERT INTO `network` (`network`, `network_order`, `default_interface_name`, `mod_date`, `create_date`) VALUES ('frontnet',1, 'eth0', NOW(),NOW());

INSERT INTO `process` (`process_id`, `name`, `create_date`, `mod_date`) VALUES (1,'sshd',NOW(),NOW());
INSERT INTO `process` (`process_id`, `name`, `create_date`, `mod_date`) VALUES (2,'pylon',NOW(),NOW());
INSERT INTO `process` (`process_id`, `name`, `create_date`, `mod_date`) VALUES (3,'outpost.pl',NOW(),NOW());
INSERT INTO `process` (`process_id`, `name`, `create_date`, `mod_date`) VALUES (4,'control.pl',NOW(),NOW());
INSERT INTO `process` (`process_id`, `name`, `create_date`, `mod_date`) VALUES (5,'mysqld',NOW(),NOW());
INSERT INTO `process` (`process_id`, `name`, `create_date`, `mod_date`) VALUES (6,'httpd',NOW(),NOW());
INSERT INTO `process` (`process_id`, `name`, `create_date`, `mod_date`) VALUES (7,'crond',NOW(),NOW());

INSERT INTO `rack` (`rack_id`, `cage_id`, `x_pos`, `y_pos`, `create_date`, `mod_date`) VALUES ('unknown','unknown',1,1,NOW(),NOW());

INSERT INTO `rootcause` ( `id`, `where_str`, `causeorder`, `mod_date`, `create_date`) VALUES (1,'AlertGroup=\'conn\'',1,NOW(),NOW());
INSERT INTO `rootcause` ( `id`, `where_str`, `causeorder`, `mod_date`, `create_date`) VALUES (3,'AlertGroup=\'proc_count\' and AlertKey=\'httpd\'',3,NOW(),NOW());
INSERT INTO `rootcause` ( `id`, `where_str`, `causeorder`, `mod_date`, `create_date`) VALUES (4,'AlertGroup=\'purple_tsunami\'',4,NOW(),NOW());

INSERT INTO `rootcause_symptom` (`rootcause_id`, `id` , `where_str`, `mod_date`, `create_date`) VALUES (1,NULL,'server_id=\'SERVER_ID\' and AlertGroup != \'conn\'',NOW(),NOW());
INSERT INTO `rootcause_symptom` (`rootcause_id`, `id` , `where_str`, `mod_date`, `create_date`) VALUES (3,NULL,'AlertGroup=\'servicegroup\' and server_id=\'SERVER_ID\'',NOW(),NOW());
INSERT INTO `rootcause_symptom` (`rootcause_id`, `id` , `where_str`, `mod_date`, `create_date`) VALUES (3,NULL,'server_id=\'SERVER_ID\' and AlertGroup=\'http_connect\'',NOW(),NOW());
INSERT INTO `rootcause_symptom` (`rootcause_id`, `id` , `where_str`, `mod_date`, `create_date`) VALUES (4,NULL,'AlertGroup=\'timeout\'',NOW(),NOW());


INSERT INTO `settings` (`name`, `value`, `mod_date`) VALUES ('alert_timeout','10',NOW());
INSERT INTO `settings` (`name`, `value`, `mod_date`) VALUES ('record_clears','0',NOW());
INSERT INTO `settings` (`name`, `value`, `mod_date`) VALUES ('minimum_severity','3',NOW());
INSERT INTO `settings` (`name`, `value`, `mod_date`) VALUES ('from_address','uravo@localhost',NOW());
INSERT INTO `settings` (`name`, `value`, `mod_date`) VALUES ('email_interval','30',NOW());
INSERT INTO `settings` (`name`, `value`, `mod_date`) VALUES ('tsunami_level','100',NOW());
INSERT INTO `settings` (`name`, `value`, `mod_date`) VALUES ('history_to_keep','14',NOW());

INSERT INTO `silo` (`silo_id`, `comments`, `bu_id`, `mod_date`, `create_date`) VALUES ('unknown','','unknown',NOW(),NOW());

INSERT INTO `type` (`type_id`, `comments`, `auto_id_type`, `auto_id_source`, `auto_id_text`, `community`, `create_date`, `mod_date`) VALUES ('pylon','',NULL,NULL,NULL,NULL,NOW(),NOW());
INSERT INTO `type` (`type_id`, `comments`, `auto_id_type`, `auto_id_source`, `auto_id_text`, `community`, `create_date`, `mod_date`) VALUES ('linux','','file','/etc/redhat-release','CentOS',NULL,NOW(),NOW());
INSERT INTO `type` (`type_id`, `comments`, `auto_id_type`, `auto_id_source`, `auto_id_text`, `community`, `create_date`, `mod_date`) VALUES ('website','',NULL,NULL,NULL,NULL,NOW(),NOW());
INSERT INTO `type` (`type_id`, `comments`, `auto_id_type`, `auto_id_source`, `auto_id_text`, `community`, `create_date`, `mod_date`) VALUES ('unknown','',NULL,NULL,NULL,NULL,NOW(),NOW());
INSERT INTO `type` (`type_id`, `comments`, `auto_id_type`, `auto_id_source`, `auto_id_text`, `community`, `create_date`, `mod_date`) VALUES ('control','',NULL,NULL,NULL,NULL,NOW(),NOW());
INSERT INTO `type` (`type_id`, `comments`, `auto_id_type`, `auto_id_source`, `auto_id_text`, `community`, `create_date`, `mod_date`) VALUES ('outpost','',NULL,NULL,NULL,NULL,NOW(),NOW());
INSERT INTO `type` (`type_id`, `comments`, `auto_id_type`, `auto_id_source`, `auto_id_text`, `community`, `create_date`, `mod_date`) VALUES ('db','',NULL,NULL,NULL,NULL,NOW(),NOW());
INSERT INTO `type` (`type_id`, `comments`, `auto_id_type`, `auto_id_source`, `auto_id_text`, `community`, `create_date`, `mod_date`) VALUES ('webserver','',NULL,NULL,NULL,NULL,NOW(),NOW());

INSERT INTO type_log (id, type_id, log_file, mod_date, create_date) VALUES (1, 'linux', '/var/log/messages', NOW(), NOW());

INSERT INTO type_log_detail (type_log_id, regex, mod_date, create_date) VALUES (1, 'error', NOW(), NOW());

INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('db','procs',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('control','procs',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','bandwidth',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','cpu',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','config',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','conn',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','cron',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','disk',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','ifconfig',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','iostat',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','log',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','memory',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','ntp',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','procs',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','run',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('outpost','procs',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('webserver','http',NOW());
INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('website','http',NOW());

INSERT INTO `type_process` (`type_id`, `process_id`, `yellow`, `red`) VALUES ('db',5,'','>0');
INSERT INTO `type_process` (`type_id`, `process_id`, `yellow`, `red`) VALUES ('control',4,'','=1');
INSERT INTO `type_process` (`type_id`, `process_id`, `yellow`, `red`) VALUES ('linux',1,'>1','>0');
INSERT INTO `type_process` (`type_id`, `process_id`, `yellow`, `red`) VALUES ('linux',7,'','>0');
INSERT INTO `type_process` (`type_id`, `process_id`, `yellow`, `red`) VALUES ('outpost',3,'','=1');
INSERT INTO `type_process` (`type_id`, `process_id`, `yellow`, `red`) VALUES ('pylon',2,'','>0');
INSERT INTO `type_process` (`type_id`, `process_id`, `yellow`, `red`) VALUES ('webserver',6,'','>=5');
