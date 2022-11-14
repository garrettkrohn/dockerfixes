-- web chat call
CALL createWebChat( 4, 'White Oaks Web Chat', 7, 'white_oaks_webchat', 'white_oaks_webchat.css', 1, 1 );

-- create a test number, if you don't have one already
INSERT INTO `number` (phone_number_id, company_id, phone_number)
VALUES (1, 4, 777);

-- delete styles for testing
DELETE FROM widget_setting WHERE `key` = 's3_stylesheet' ORDER BY widget_setting_id DESC LIMIT 1;

-- Delete out to create another if needed
DELETE FROM convo ORDER BY convo_id DESC LIMIT 1;

DELETE FROM location WHERE company_id = 4 AND phone_number_id = 7;

CALL createWebChat( 4, 'White Oaks Web Chat', 7, 'white_oaks_webchat', 'white_oaks_webchat.css', 1, 1 );

-- get the url of the last widget you created
SET @mostRecentWidget = (SELECT widget_id FROM widget ORDER BY widget_id DESC LIMIT 1);

SELECT
  `co`.`company_name`,
  CONCAT('localhost/acct/widget/', CONCAT(`w`.`widget_id`, CONCAT('/', SUBSTRING(MD5(CONCAT(`co`.`company_id`, `w`.`device_id`)), 1, 4) ))) AS url
FROM `widget` AS w
INNER JOIN `company` AS co ON `co`.`company_id` = `w`.`company_id`
WHERE `w`.widget_id = @mostRecentWidget;

-- create a test number, if you don't have one already
INSERT INTO `number` (phone_number_id, company_id, phone_number)
VALUES (1, 4, 777);