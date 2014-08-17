module Rubyku

  # This class is responsible for initializing a new server to be ready for
  # Rubyku deployment.

  class SystemInitializer < RemoteProcedure

    attr_reader :local_git_path, :remote_name, :hostname, :remote_project_name

    REGEX_SYMBOL = /\A[a-zA-Z_\.\-]+\z/
    RUBYKU_DIR   = File.expand_path("../..", __FILE__)

    def run
      # Update / upgrade / install system packages
      log "Installing system packages #{ blue default_system_packages.join(' ') }"
      ssh "root", <<-SCRIPT
        # Ensure package files are up to date
        apt-get -y update
        apt-get -y upgrade

        # Install packages that we use
        apt-get -y install #{ default_system_packages.join(' ') }

        # Install Foreman in the system ruby
        /usr/local/bin/gem install --no-rdoc --no-ri foreman

        # Configure Postgres for authentication
        echo #{ esc read_template_file 'pg_hba.conf' } > /etc/postgresql/9.3/main/pg_hba.conf
        service postgresql restart
      SCRIPT

      # Setup the deployment user
      log "Creating deployment user #{ blue app_username }"
      ssh "root", <<-SCRIPT
        # Setup the app user
        if [ ! -d /home/#{ app_username } ]; then
          # Create the user account
          useradd \
            --home /home/#{ app_username } \
            --create-home \
            --shell /bin/bash \
            --password "`makepasswd --chars=20`" \
            #{ app_username }

          # Grant access to the same keys
          mkdir -p /home/#{ app_username }/.ssh
          cp /root/.ssh/authorized_keys /home/#{ app_username }/.ssh/authorized_keys
          chown -R #{ app_username } /home/#{ app_username }/.ssh
          chmod -R go-rwx /home/#{ app_username }/.ssh
        fi
      SCRIPT

      # Configure RVM for the deployment user
      log "Configuring RVM for #{ blue app_username }"
      ssh app_username, <<-SCRIPT
        # Set up RVM on the app user
        curl -sSL https://get.rvm.io | bash -s stable

        # Configure global gems
        cp ~/.rvm/gemsets/global.gems /tmp/global.gems
        echo bundler >> /tmp/global.gems
        echo puma >> /tmp/global.gems
        sort -u /tmp/global.gems > ~/.rvm/gemsets/global.gems
        rm /tmp/global.gems

        # Set up the get_port script
        mkdir -p $HOME/.port_numbers
        echo #{ esc read_template_file 'get_port.sh' } > $HOME/.port_numbers/get_port
        chmod u+x $HOME/.port_numbers/get_port
      SCRIPT

      # Install RVM's build requirements
      log "Installing RVM's build requirements"
      ssh "root", <<-SCRIPT
        # Install RVM's build requirements
        /home/#{ app_username }/.rvm/bin/rvm requirements
      SCRIPT
    end

    def default_system_packages
      %w(
        make gcc libssl-dev
        nginx
        postgresql-9.3 postgresql-client-9.3 postgresql-server-dev-9.3
        redis-server redis-tools
        git makepasswd silversearcher-ag
        nodejs
        ruby2.0
      )
    end

  end

end
