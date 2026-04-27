INSERT INTO `priority_state` (`group`, `status`, `started_by`, `started_job`, `cooldown`) 
VALUES 
('police', 'safe', NULL, NULL, 0),
('sheriff', 'safe', NULL, NULL, 0)
ON DUPLICATE KEY UPDATE 
    `status` = VALUES(`status`),
    `started_by` = VALUES(`started_by`),
    `started_job` = VALUES(`started_job`),
    `cooldown` = VALUES(`cooldown`);