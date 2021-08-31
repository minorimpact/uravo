USE uravo;

INSERT INTO `module` (`module_id`, `remote`, `mod_date`, `create_date`) VALUES ('bandwidth', 0, NOW(), NOW());

INSERT INTO `monitoring_default_values` (`id`, `AlertGroup`, `AlertKey`, `description`, `yellow`, `red`, `disabled`, `mod_date`, `create_date`) VALUES (NULL,'bandwidth_rate',NULL,NULL,50000000,75000000,0,NOW(),NOW());

INSERT INTO `type_module` (`type_id`, `module_id`, `create_date`) VALUES ('linux','bandwidth',NOW());
