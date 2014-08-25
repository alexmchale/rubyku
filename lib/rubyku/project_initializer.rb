module Rubyku

  class ProjectInitializer < RemoteProcedure

    attr_reader :app_hostname, :app_name, :local_path, :remote_name

    def run
      # Set up ivars
      @app_hostname = options[:app_hostname]
      @app_name     = options[:app_name]
      @local_path   = options[:local_path]
      @remote_name  = options[:remote_name]

      # Verify the values
      log "Verifying configuration details"
      check_and_chdir_local_app! local_path
      resolve_host! server_hostname
      verify_candidate_hostname! app_hostname
      check_symbol_name! app_name
      check_symbol_name! remote_name

      # Test if the remote project path already exists
      # TODO: change this to instead verify that it's the same repository -- check the root sha-1 maybe?
      log "Checking if the specified app already exists"
      if ssh_path_exists(app_username, app_name)
        die "app #{ app_name } already exists on #{ server_hostname }"
      end

      # Install the Ruby the app uses
      log "Installing the Ruby used by this project"
      ssh_run_template(app_username, "install-ruby.sh", {
        :version => File.read(File.join local_path, ".ruby-version"),
      })

      # Add the remote to the git project
      log "Adding the local Git remote"
      run_template("add_git_remote.sh")

      # Create the PostgreSQL database
      log("Creating a PostgreSQL database")
      ssh_run_template("root", "create_postgres_database.sh", {
        :dbname => app_name         ,
        :dbuser => app_name         ,
        :dbpass => SecureRandom.hex ,
      })

      # Initialize the new app
      log "Initializing the new app on the remote host"
      ssh_run_template(app_username, "initialize_new_app.sh")

      # Set ENV file
      log "Writing dotenv file in project"
      ssh_write_file(app_username, "#{ app_name }/.env", nil) do
        (options[:env] || {}).merge({
          "RAILS_ENV"       => "production"                                                           ,
          "PATH"            => "/home/#{ app_username }/.rvm/wrappers/#{ app_name }:$PATH" ,
          "SECRET_KEY_BASE" => SecureRandom.hex(64)                                                   ,
        }).map do |key, value|
          "#{ key }=#{ value }\n"
        end.join
      end

      # Set the nginx configuration
      ssh_run_template("root", "nginx.configure-app.sh")

      # Push the project to the remote host
      log "Pushing the local repository to the remote"
      system "git push --all #{ esc remote_name }"
    end

  end

end
