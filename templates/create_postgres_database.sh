# Create the PostgreSQL user and database
cd /tmp # so that the 'postgres' user doesn't issue a warning
echo "CREATE ROLE %%dbuser%% PASSWORD '%%dbpass%%' LOGIN" | sudo -u postgres psql
sudo -u postgres createdb %%dbname%% --owner=%%dbuser%%

# Add the database password to pgpass
if [ "$?" = "0" ]; then
  echo "localhost:*:%%dbname%%:%%dbuser%%:%%dbpass%%" >> %%app_home%%/.pgpass
  chown %%app_username%% %%app_home%%/.pgpass
  chmod 0600 %%app_home%%/.pgpass
fi
