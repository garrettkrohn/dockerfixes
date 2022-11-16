-- right now with docker we can get collation issues.  The collation needs to match between the tables and procedure

-- just change the name of the table

ALTER TABLE company CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

