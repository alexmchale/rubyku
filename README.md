rubyku
======

Rubyku is a set of scripts for managing Virtual Machines full of Ruby apps

# Notes

* Applications are identified by a name - maybe the project name could be
  optional? Convert the hostname to dashes like Semaphore to get the name,
  unless otherwise specified?
* What happens to the app's database when it is removed? Should the remove
  command have an option for deleting or keeping?

# Modules that can be installed on an app when initialized

* PostgreSQL (postgres)
* Redis (redis)
* MySQL (mysql)
