#!/bin/bash

# Enable the app's configuration
cd /etc/nginx
echo %%inject:nginx.template.conf%% > sites-available/%%app_name%%
ln -sf sites-available/%%app_name%% sites-enabled/%%app_name%%

# Kill HUP nginx to reload its configuration
if [ -f /run/nginx.pid ]; then
  kill -HUP $( cat /run/nginx.pid )
fi
