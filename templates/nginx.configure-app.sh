#!/bin/bash

# Enable the app's configuration
cd /etc/nginx
echo %%esc:nginx_conf%% > sites-available/%%app%%
ln -sf sites-available/%%app%% sites-enabled/%%app%%

# Kill HUP nginx to reload its configuration
if [ -f /run/nginx.pid ]; then
  kill -HUP $( cat /run/nginx.pid )
fi
