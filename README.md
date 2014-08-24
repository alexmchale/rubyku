rubyku
======

Rubyku is a set of scripts for managing Virtual Machines full of Ruby apps

# Notes

* Applications are identified by a name - maybe the project name could be
  optional? Convert the hostname to dashes like Semaphore to get the name,
  unless otherwise specified?
* What happens to the app's database when it is removed? Should the remove
  command have an option for deleting or keeping?
* You specify both a connection hostname and an app hostname, to allow you to
  set the app up before the DNS is configured for the app's proper hostname.

# Modules that can be installed on an app when initialized

* PostgreSQL (postgres)
* Redis (redis)
* MySQL (mysql)
