#!/bin/bash

# where we put the port numbers
root="$HOME/.port_numbers"
this_port_file="$root/PORT-$( basename `pwd` )"
next_port_file="$root/NEXT_PORT"

# make sure those files exist
touch "$this_port_file" "$next_port_file"

# grab what the next port number will be
next_port=$( cat "$next_port_file" )
if [ -z "$next_port" ]; then
  next_port="25000"
fi

# does this app have a port number yet?
this_port=$( cat "$this_port_file" )
if [ -z "$this_port" ]; then
  this_port="$next_port"
  next_port=$(( $next_port + 1 ))

  echo "$this_port" > "$this_port_file"
  echo "$next_port" > "$next_port_file"
fi

# echo the port number
echo $this_port
