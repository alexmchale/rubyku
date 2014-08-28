#!/bin/bash

# Get the app's port number
cd %%app_root%%
port=$( sudo -u %%app_username%% -H %%app_home%%/.port_numbers/get_port )

# Enable the app's configuration
echo %%inject:nginx.template.conf%% > /etc/nginx/sites-available/%%app_name%%
perl -p -i -e "s/%%port%%/$port/g" /etc/nginx/sites-available/%%app_name%%
ln -sf /etc/nginx/sites-available/%%app_name%% /etc/nginx/sites-enabled/%%app_name%%

# Kill HUP nginx to reload its configuration
if [ -f /run/nginx.pid ]; then
  kill -HUP $( cat /run/nginx.pid )
fi
