@echo off

set SQL_DIR=..\src\main\db\changelog
set UPDATER_FILE=db-updater.pl
set CONFIG_FILE=..\src\main\conf\dev\dbcp.properties
set SEARCH_STRING=cayenne.dbcp.url=jdbc:postgresql://localhost/
set databaseName=

for /f "tokens=2* delims=/" %%A  in (
	'findstr /bc:"%SEARCH_STRING%" %CONFIG_FILE%'
) do set databaseName=%%B


perl %UPDATER_FILE% %SQL_DIR% %databaseName% --dbhost localhost --username carmen --password carmen
