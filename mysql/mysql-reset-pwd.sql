-- http://dev.mysql.com/doc/refman/5.5/en/resetting-permissions.html#resetting-permissions-unix
SET @my_password = '<PASSWORD>';

UPDATE mysql.user SET Password=PASSWORD(@my_password) WHERE User='root';
FLUSH PRIVILEGES;

-- $ service mysql stop && mysqld_safe --init-file=/path/to/this/file.sql &
