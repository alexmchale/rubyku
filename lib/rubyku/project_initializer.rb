module Rubyku

  class ProjectInitializer < RemoteProcedure

    attr_reader :local_git_path, :remote_name, :remote_project_name

    def run
      # Set up ivars
      @local_git_path      = options[:local_path] || Dir.pwd
      @remote_name         = options[:git_remote_name] || hostname
      @remote_project_name = options[:remote_project_name] || hostname.gsub(".", "-")

      # Confirm the input
      log "Confirm the following details:"
      puts "Hostname:            #{ hostname            }"
      puts "Local Git Path:      #{ local_git_path      }"
      puts "Git Remote Name:     #{ remote_name         }"
      puts "Remote Project Name: #{ remote_project_name }"
      puts
      exit unless options[:yes] || yesno("Do you want to proceed with these values?", false)

      # Validate the input
      #unless [ remote_name, hostname, remote_project_name ].all? { |s| s =~ REGEX_SYMBOL }
      #  die "invalid input"
      #end

      # Verify that the specified path looks correct and chdir
      log "Verifying the specified Git repository"
      check_and_chdir_git! local_git_path

      # Test if the remote project path already exists
      log "Checking if the specified project already exists"
      (stdout, stderr, code, signal) = ssh(app_username, "ls #{ esc remote_project_name } > /dev/null 2>&1")
      if code == 0
        die "project #{ remote_project_name } already exists on #{ hostname }"
      end

      # Install the ruby
      log "Installing the Ruby used by this project"
      ssh app_username, ".rvm/bin/rvm install #{ esc File.read '.ruby-version' }"

      # Add the remote to the git project
      log "Adding the local Git remote"
      system "git remote rm #{ esc hostname }"
      system "git remote add #{ esc hostname } #{ esc app_username }@#{ esc hostname }:#{ esc remote_project_name }"

      # Create the PostgreSQL database
      log "Creating a PostgreSQL database"
      postgresql_dbname   = remote_project_name
      postgresql_username = remote_project_name
      postgresql_password = SecureRandom.hex
      (stdout, stderr, code, signal) = ssh "root", <<-SCRIPT
        # Create the PostgreSQL user and database
        cd /tmp
        echo "CREATE ROLE #{ postgresql_username } PASSWORD '#{ postgresql_password }' LOGIN" | sudo -u postgres psql
        sudo -u postgres createdb #{ esc postgresql_dbname } --owner=#{ esc postgresql_username }

        # Add the database password to pgpass
        if [ "$?" = "0" ]; then
          echo #{
            [
              'localhost'         ,
              '*'                 ,
              postgresql_dbname   ,
              postgresql_username ,
              postgresql_password ,
            ].join(':')
          } >> /home/#{ esc app_username }/.pgpass
        fi

        chown #{ esc app_username } /home/#{ esc app_username }/.pgpass
        chmod 0600 /home/#{ esc app_username }/.pgpass
      SCRIPT

      # Initialize the git repository on the remote host
      log "Initializing the new repository on the remote host"
      ssh app_username, <<-SCRIPT
        git init #{ esc remote_project_name }
        cd #{ esc remote_project_name }
        git config receive.denyCurrentBranch ignore
        echo #{ esc read_template_file 'post-receive.sh' } > .git/hooks/post-receive
        chmod u+x .git/hooks/post-receive
      SCRIPT

      # Set database.yml settings
      log "Setting database.yml with PostgreSQL configuration"
      ssh app_username, <<-SCRIPT
        cd #{ esc remote_project_name }
        mkdir -p config
        echo #{
          esc read_template_file('postgresql-database.yml', {
            :database => postgresql_dbname   ,
            :username => postgresql_username ,
          })
        } > config/database.yml
      SCRIPT

      # Set ENV file
      options[:env] ||= Hash.new
      options[:env]["RAILS_ENV"] ||= "production"
      options[:env]["PATH"] = "/home/#{ app_username }/.rvm/wrappers/#{ remote_project_name }:$PATH"
      options[:env]["SECRET_KEY_BASE"] = SecureRandom.hex(64)
      env = options[:env].map { |k, v| "#{ k }=#{ v }\n" }.join
      log "Writing dotenv file in project"
      ssh app_username, <<-SCRIPT
        cd #{ esc remote_project_name }
        echo #{ esc env } > .env
      SCRIPT

      # Set the nginx configuration
      ssh "root", <<-SCRIPT
        # Write the configuration file
        cd /etc/nginx
        echo #{
          esc read_template_file('nginx.template.conf',
                app: remote_project_name,
                app_root: "/home/#{ app_username }/#{ remote_project_name }",
                hostname: hostname,
              )
        } > sites-available/#{ remote_project_name }
        ln -sf /etc/nginx/sites-available/#{ remote_project_name } sites-enabled/#{ remote_project_name }

        # Kill HUP nginx to reload its configuration
        if [ -f /run/nginx.pid ]; then
          kill -HUP $( cat /run/nginx.pid )
        fi
      SCRIPT

      # Push the project to the remote host
      log "Pushing the local repository to the remote"
      system "git push --all #{ esc hostname }"
    end

  end

end
