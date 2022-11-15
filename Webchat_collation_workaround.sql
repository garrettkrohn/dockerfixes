-- set collation
SET collation_connection = utf8mb4_unicode_ci;
SET collation_database = utf8mb4_unicode_ci;
SET collation_server = utf8mb4_unicode_ci;

-- attempted work around for the collation error moving over to the new local

DELIMITER ;;
CREATE DEFINER=`root`@`%` PROCEDURE `createWebChat`(companyId INT, locationName VARCHAR(55), phoneNumberId INT, styleClass VARCHAR(128), 
s3StyleFile VARCHAR(255), createdByUserId INT, hideMobile TINYINT)
    COMMENT 'Create web chat for property\n\nParameters:\n- companyId - The unique id for the property for which the web chat is being created\n- locationName - The name of the property + "Web Chat", (e.g. Susona Bodrum Web Chat)\n- phoneNumberId - The unique id for the phone number that is to be attached with the web chat\n- styleClass - The name of the web chat in snake case + "webchat", (e.g. susona_bodrum_webchat)\n- s3StyleFile - The same naming convention as styleClass with ".css" added at the end, (e.g. susona_bodrum_webchat.css)\n- createdByUserId - The unique id associated with the user creating the web chat\n- hideMobile - A boolean (0 = false, 1 = true) determining whether or not the web chat will be continued to mobile'
proc:BEGIN

    -- Define variables for logging the procedure
    SET @procedureName := 'createWebChat' COLLATE utf8mb4_unicode_ci;
    SET @tablesAffected := 'location, stored_message_categories, stored_message' COLLATE utf8mb4_unicode_ci;
    SET @variablesProvided := CONCAT('company_id: ', companyId, 'location_name: ', locationName, 'phone_number_id: ', phoneNumberId,
    'style_class: ', styleClass, 's3_style_file: ', s3StyleFile, 'created_by_user_id: ', createdByUserId, 'hide_mobile: ', hideMobile) COLLATE utf8mb4_unicode_ci;
    SET @results := '' COLLATE utf8mb4_unicode_ci;
    SET @rowsAffected := 0 COLLATE utf8mb4_unicode_ci;

    -- Define variables for procedure
    SET @widgetName = 'Online Chat' COLLATE utf8mb4_unicode_ci;
    SET @locationType = 'std' COLLATE utf8mb4_unicode_ci;
    SET @categoryName = locationName COLLATE utf8mb4_unicode_ci;
    SET @webWelcomeLabel = 'Web Welcome' COLLATE utf8mb4_unicode_ci;
    SET @webWelcomeText = 'Hello! How may we assist you?' COLLATE utf8mb4_unicode_ci;
    SET @mobileTransferLabel = 'Mobile Transfer' COLLATE utf8mb4_unicode_ci;
    SET @mobileTransferText = 'Thanks for chatting with us today. To continue your conversation via text, just reply to this message on your phone.'COLLATE utf8mb4_unicode_ci;
    SET @afterHoursWelcomeLabel = 'After Hours Welcome'COLLATE utf8mb4_unicode_ci;
    SET @afterHoursWelcomeText = 'Thanks for chatting with us today. We are currently closed. Please leave us your mobile number and a message and we will get back to you as soon as we can.'COLLATE utf8mb4_unicode_ci;
    SET @afterHoursMobileLabel = 'After Hours Mobile Transfer'COLLATE utf8mb4_unicode_ci;
    SET @afterHoursMobileText = 'Thanks for chatting with us today. We will send you a text as soon as our team is available.'COLLATE utf8mb4_unicode_ci;
    SET @widgetDeviceId = 'main-chat-page'COLLATE utf8mb4_unicode_ci;
    SET @widgetSession = 'session'COLLATE utf8mb4_unicode_ci;
    SET @realWidgetDeviceId = ( SELECT CONCAT(@widgetDeviceId, COUNT(*) + 1) FROM `widget` WHERE `company_id` = companyId AND `device_id` LIKE CONCAT(@widgetDeviceId, '%'))COLLATE utf8mb4_unicode_ci;
    SET @storedMessageType = 'live_web_chat'COLLATE utf8mb4_unicode_ci;
    SET @storedMessageCategoryType = 'live_web_chat'COLLATE utf8mb4_unicode_ci;

    -- Validate parameters given

    -- Check companyId to ensure it isn't empty
    IF (companyId = '') THEN 
        SELECT ('Please provide a valid company_id') COLLATE utf8mb4_unicode_ci; 
        LEAVE proc; 
    END IF; 
    
     -- Check locationName to ensure it isn't empty
    IF (locationName = '') THEN 
        SELECT ('Please provide a valid location_name')COLLATE utf8mb4_unicode_ci; 
        LEAVE proc; 
    END IF; 

     -- Check styleClass to ensure it isn't empty
    IF (styleClass = '') THEN 
        SELECT ('Please provide a valid style_class')COLLATE utf8mb4_unicode_ci; 
        LEAVE proc; 
    END IF; 

     -- Check s3StyleFile to ensure it isn't empty
    IF (s3StyleFile = '') THEN 
        SELECT ('Please provide a valid s3_style_file')COLLATE utf8mb4_unicode_ci; 
        LEAVE proc; 
    END IF; 
    
     -- Check createdByUserId to ensure it isn't empty
    IF (createdByUserId = '') THEN 
        SELECT ('Please provide a valid user_id')COLLATE utf8mb4_unicode_ci; 
        LEAVE proc; 
    END IF; 

    -- Validate the provided companyId exists, exit procedure if needed
    IF NOT EXISTS(SELECT 1 FROM `company` WHERE `company_id` = companyId) THEN
        SELECT CONCAT('company_id "', companyId, '" not found! Please provide a valid company_id')COLLATE utf8mb4_unicode_ci;
        LEAVE proc; 
    END IF;
    
    -- If provided, validate phoneNumberId exists, exit procedure if needed
    IF (phoneNumberId IS NOT NULL) THEN
        IF NOT EXISTS(SELECT 1 FROM `number` WHERE `phone_number_id` = phoneNumberId) THEN
            SELECT CONCAT('phone_number_id "', phoneNumberId, '" not found! Please provide a valid phone_number_id')COLLATE utf8mb4_unicode_ci;
            LEAVE proc;
        END IF;
    END IF; 

    -- If phonenNumberId does NOT exist, mobile button cannot be included
    IF ((phoneNumberId IS NULL) AND (hideMobile = 0)) THEN
        SELECT CONCAT('phone_number_id "', phoneNumberId, '" is NULL and continue to mobile has been selected.
        Please choose valid phone_number_id if you want mobile button avaiable.')COLLATE utf8mb4_unicode_ci;
        LEAVE PROC;
    END IF;

    -- Validate the provided createdByUserId exists, exit procedure if needed
    IF NOT EXISTS(SELECT 1 FROM `user` WHERE `id` = createdByUserId) THEN
        SELECT CONCAT('user_id "', createdByUserId, '" not found! Please provide a valid user_id')COLLATE utf8mb4_unicode_ci;
        LEAVE proc; 
    END IF; 

    
    -- Update database

    -- Insert new api key if needed
    IF (SELECT `value` FROM `company_settings` WHERE `key` = 'api_key_v1' AND `company_id` = companyId) IS NULL THEN
        -- Generate a new random API key.  Ensure the key is unique or loop until a unique key is obtained.
        SET @new_api_key = (SELECT (SHA1(CONCAT(now(), FLOOR(100000000 + RAND() * (1000000000 - 100000000)))))) COLLATE utf8mb4_unicode_ci;
        WHILE (SELECT COUNT(*) FROM api_keys WHERE `key` = @new_api_key) > 0 DO
        SET @new_api_key = (SELECT (SHA1(CONCAT(now(), FLOOR(100000000 + RAND() * (1000000000 - 100000000)))))) COLLATE utf8mb4_unicode_ci;
        END WHILE;

        -- Add the new key to api_keys
        INSERT INTO `api_keys` (`key`, `level`, `ignore_limits`, `date_created`)
            VALUES (@new_api_key, 1, 1, NOW());

        -- Add the new key to the company_settings
        INSERT INTO `company_settings` (`company_id`, `key`, `value`)
            VALUES (companyId, 'api_key_v1', @new_api_key);
    END IF;


    -- Create the new location
    INSERT INTO `location` (`company_id`, `name`, `type`, `created_by`, `created_timestamp`, `phone_number_id`)
        VALUES( companyId, locationName, 'std', createdByUserId, UNIX_TIMESTAMP(), phoneNumberId );
    SET @locationId = (SELECT `loc_id` FROM `location` WHERE `company_id` = companyId AND `name` = locationName) COLLATE utf8mb4_unicode_ci;

    -- Make sure that the stored messages have been created
    SET @realCategoryName = ( SELECT CONCAT(@categoryName, COUNT(*) + 1) FROM `stored_message_categories`  WHERE `company_id` = companyId AND `name` LIKE CONCAT(@categoryName, '%') COLLATE utf8mb4_unicode_ci);

    INSERT INTO `stored_message_categories` (`company_id`, `parent`, `type`, `name`)
        VALUES( companyId, 0, @storedMessageCategoryType, @realCategoryName );
    SET @categoryId = (SELECT `id` FROM `stored_message_categories` WHERE `company_id` = companyId AND `parent` = 0 AND `type` = @storedMessageCategoryType AND `name` = @realCategoryName) COLLATE utf8mb4_unicode_ci;
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    INSERT INTO `stored_message` (`company_id`, `type`, `text`, `label`, `category`, `order`)
        VALUES( companyId, @storedMessageType, @webWelcomeText, @webWelcomeLabel, @categoryId, 1);
    SET @welcomeStoredId = (SELECT `stored_id` FROM `stored_message` WHERE `company_id` = companyId AND `type` = @storedMessageType AND `text` = @webWelcomeText AND `label` = @webWelcomeLabel AND `category` = @categoryId AND `order` = 1) COLLATE utf8mb4_unicode_ci;
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    INSERT INTO `stored_message` (`company_id`, `type`, `text`, `label`, `category`, `order`)
        VALUES( companyId, @storedMessageType, @mobileTransferText, @mobileTransferLabel, @categoryId, 2);
    SET @mobileStoredId = (SELECT `stored_id` FROM `stored_message` WHERE `company_id` = companyId AND `type` = @storedMessageType AND `text` = @mobileTransferText AND `label` = @mobileTransferLabel AND `category` = @categoryId AND `order` = 2) COLLATE utf8mb4_unicode_ci;
    SET @rowsAffected := @rowsAffected + ROW_COUNT()COLLATE utf8mb4_unicode_ci;

    INSERT INTO `stored_message` (`company_id`, `type`, `text`, `label`, `category`, `order`)
        VALUES( companyId, @storedMessageType, @afterHoursWelcomeText, @afterHoursWelcomeLabel, @categoryId, 3);
    SET @afterHoursWelcomeStoredId = (SELECT `stored_id` FROM `stored_message` WHERE `company_id` = companyId AND `type` = @storedMessageType AND `text` = @afterHoursWelcomeText AND `label` = @afterHoursWelcomeLabel AND `category` = @categoryId AND `order` = 3)COLLATE utf8mb4_unicode_ci;
    SET @rowsAffected := @rowsAffected + ROW_COUNT()COLLATE utf8mb4_unicode_ci;

    INSERT INTO `stored_message` (`company_id`, `type`, `text`, `label`, `category`, `order`)
        VALUES( companyId, @storedMessageType, @afterHoursMobileText, @afterHoursMobileLabel, @categoryId, 4);
    SET @afterHoursMobileStoredId = (SELECT `stored_id` FROM `stored_message` WHERE `company_id` = companyId AND `type` = @storedMessageType AND `text` = @afterHoursMobileText AND `label` = @afterHoursMobileLabel AND `category` = @categoryId AND `order` = 4)COLLATE utf8mb4_unicode_ci;
    SET @rowsAffected := @rowsAffected + ROW_COUNT()COLLATE utf8mb4_unicode_ci;

    INSERT INTO `widget` (`company_id`, `type`, `device_id`, `name`, `api_key_id`, `style`, `session`)
    SELECT c.`company_id`, 'guest', @realWidgetDeviceId, @widgetName, ak.`id`, styleClass, @widgetSession
    FROM `company` AS c
             INNER JOIN `company_settings` AS cs ON `cs`.`company_id` = `c`.`company_id` AND `cs`.`key` = 'api_key_v1'
             INNER JOIN `api_keys` AS ak ON `ak`.`key` = `cs`.`value`
    WHERE `c`.`company_id` = companyId
    LIMIT 1;
    SET @widgetId = LAST_INSERT_ID() COLLATE utf8mb4_unicode_ci;
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Link to location
    INSERT INTO `widget_location` (`widget_id`, `loc_id`, `display_name`)
        VALUES (@widgetId, @locationId, 'General Inquiries');
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Link to welcome message
    INSERT INTO `widget_stored_message` (`widget_id`, `stored_id`, `type`)
        VALUES (@widgetId, @welcomeStoredId, 'welcome');
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Link to mobile transfer message
    INSERT INTO `widget_stored_message` (`widget_id`, `stored_id`, `type`)
        VALUES (@widgetId, @mobileStoredId, 'mobile-transfer');
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Link to after hours message
    INSERT INTO `widget_stored_message` (`widget_id`, `stored_id`, `type`)
        VALUES (@widgetId, @afterHoursWelcomeStoredId, 'after-hours-welcome');
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Link to after hours mobile transfer message
    INSERT INTO `widget_stored_message` (`widget_id`, `stored_id`, `type`)
        VALUES (@widgetId, @afterHoursMobileStoredId, 'after-hours-mobile-transfer');
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Hide mobile button if specified
    IF (hideMobile = 1) THEN
        INSERT INTO `widget_setting` ( `widget_id`, `key`, `value` )
            VALUES ( @widgetId, 'hide_continue_on_mobile_button', 1 );
    END IF;

    -- Display an orange label in Kipsu UI for chat conversations
    INSERT INTO `widget_setting` (`widget_id`, `key`, `value`) 
        VALUES (@widgetId, 'label_class', 'widget-label-orange');
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Hide the initial welcome message.
    INSERT INTO `widget_setting` (`widget_id`, `key`, `value`) 
        VALUES (@widgetId, 'hide_widget_convo_on_welcome', 1);
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Use an S3 stylesheet
    INSERT INTO `widget_setting` (`widget_id`, `key`, `value`) 
        VALUES (@widgetId, 's3_stylesheet', s3StyleFile);
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Retrieve the URL for this widget to provide to property
    SELECT
        `co`.`company_name`,
        CONCAT('localhost/acct/widget/', CONCAT(`w`.`widget_id`, CONCAT('/', SUBSTRING(MD5(CONCAT(`co`.`company_id`, `w`.`device_id`)), 1, 4) ))) AS url
    FROM `widget` AS w
             INNER JOIN `company` AS co ON `co`.`company_id` = `w`.`company_id`
    WHERE `w`.widget_id = @widgetId;
    SET @rowsAffected := @rowsAffected + ROW_COUNT() COLLATE utf8mb4_unicode_ci;

    -- Log all the details related to this procedure being ran
    CALL `logSupportProcedureWithResults`(@procedureName, @tablesAffected, @variablesProvided, @rowsAffected, @results);

END;;
DELIMITER ;