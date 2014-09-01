module Rubyku

  class RemoteProcedure

    include FileUtils
    include Term::ANSIColor

    attr_reader :server_hostname, :options

    def initialize(server_hostname, options = {})
      @server_hostname = server_hostname.to_s.strip
      @options         = options

      raise RubykuError, "server_hostname is not configured" if @server_hostname == ""
      resolve_host! @server_hostname
    end

    def esc(string)
      Shellwords.escape(string.to_s.strip)
    end

    def ssh(username, command, &block)
      puts magenta(command.gsub(/^\s+/, "").gsub(/ +/, " ").strip)
      puts

      Net::SSH.start(server_hostname, username) do |ssh|
        stdout_data = ""
        stderr_data = ""
        exit_code   = nil
        exit_signal = nil

        ssh.open_channel do |channel|
          channel.exec(command) do |ch, success|
            unless success
              abort "FAILED: couldn't execute command (ssh.channel.exec)"
            end

            channel.on_data do |ch, data|
              STDOUT.print(data); STDOUT.flush

              stdout_data << data
            end

            channel.on_extended_data do |ch, type, data|
              STDERR.print(data); STDERR.flush

              stderr_data << data
            end

            channel.on_request("exit-status") do |ch, data|
              exit_code = data.read_long
            end

            channel.on_request("exit-signal") do |ch, data|
              exit_signal = data.read_long
            end
          end
        end

        ssh.loop

        if block
          yield(stdout_data, stderr_data, exit_code, exit_signal)
        else
          [ stdout_data, stderr_data, exit_code, exit_signal ]
        end
      end
    end

    def ssh_run_template(username, template, template_options = {})
      ssh(username, read_template_file(template, template_options))
    end

    def ssh_read_file(username, remote_path)
      ssh(username, "cat #{ esc remote_path }") do |out, err, code, signal|
        if code == 0
          return out
        else
          return nil
        end
      end
    end

    def ssh_write_file(username, remote_path, content, &block)
      raise "cannot specify both content and block" if content && block
      content ||= block.call

      ssh(username, <<-SCRIPT)
        mkdir -p $( dirname #{ esc remote_path } )
        echo #{ esc content } > #{ esc remote_path }
      SCRIPT
    end

    def ssh_write_template(username, remote_path, template, template_options = {})
      ssh_write_file(username, remote_path, read_template_file(template, template_options))
    end

    def ssh_path_exists(username, remote_path)
      ssh(username, "test -e #{ esc remote_path }") do |out, err, code, signal|
        return code == 0
      end
    end

    def log(message)
      puts
      puts "#{ yellow '---->' } #{ green message.to_s }"
      puts
    end

    def die(message)
      raise RubykuError, message.to_s
    end

    def all_templates
      @@templates_path ||=
        File.expand_path("../../../templates", __FILE__)

      @@all_templates ||=
        Dir["#{ @@templates_path }/**/*"].inject({}) do |templates, filename|
          if File.file? filename
            templates[File.basename filename] = File.read(filename)
          end

          templates
        end
    end

    def read_template_file(filename, replacements = {})
      # Build the replacements that every procedure has.
      all_replacements =
        replacements.merge(all_templates).merge({
          :app_username    => app_username              ,
          :app_home        => "/home/#{ app_username }" ,
          :server_hostname => server_hostname           ,
        })

      # Append ones that exist for some procedures.
      %i( app_name app_root app_hostname remote_name ).each do |key|
        if respond_to? key
          all_replacements[key] = send(key)
        end
      end

      # A lambda to do the replacements as the "inject" keyword is recursive.
      inject = -> string do
        all_replacements.inject(string) do |str, (key, value)|
          [
            [ "%%inject:#{ key }%%" , Proc.new { esc(inject[value]) } ],
            [ "%%esc:#{ key }%%"    , Proc.new { esc(value.to_s)    } ],
            [ "%%#{ key }%%"        , Proc.new { value.to_s         } ],
          ].inject(str) do |str, (anchor, replacement)|
            str.gsub(anchor, &replacement)
          end
        end
      end

      # Find the template and inject it.
      if string = all_templates[filename]
        inject[string]
      else
        raise RubykuError, "cannot find template #{ filename.inspect }"
      end
    end

    def run_template(filename, replacements = {})
      system(read_template_file(filename, replacements))
    end

    def read_project_config key
      check_and_chdir_git! local_git_path

      yaml_filename = File.join(local_git_path, "config", "rubyku.yml")
      yaml          = if File.file?(yaml_filename) then File.read(yaml_filename) end
      yaml_hash     = if yaml then YAML.load(yaml) end
      yaml_hash[key]  if yaml_hash
    end

    def check_and_chdir_local_app! local_git_path
      # Check that the path exists
      if !File.directory?(File.join(local_git_path, ".git"))
        raise RubykuError, "#{ local_git_path } is not a git repository"
      else
        chdir local_git_path
      end

      # Check that config/database.yml isn't checked in, is ignored
      if system("git ls-files config/database.yml --error-unmatch > /dev/null 2>&1")
        raise RubykuError, "database.yml is checked into git and should not be"
      end

      # Check that config/database.yml isn't checked in, is ignored
      if !system("git check-ignore config/database.yml > /dev/null 2>&1")
        raise RubykuError, "database.yml is not ignored by git and should be"
      end

      # Check that Gemfile is committed
      if !system("git ls-files Gemfile --error-unmatch > /dev/null 2>&1")
        raise RubykuError, "repository must have a Gemfile committed"
      end

      # Check that config.ru is committed
      if !system("git ls-files config.ru --error-unmatch > /dev/null 2>&1")
        raise RubykuError, "repository must have a rack.ru file committed"
      end

      # Test that the proj has .ruby-version
      if !File.file?(".ruby-version")
        raise RubykuError, "repository must have a .ruby-version file"
      end
    end

    def resolve_host! hostname
      Resolv.getaddress(hostname)
    rescue Resolv::ResolvError
      raise RubykuError, "invalid hostname #{ hostname.inspect }"
    end

    def verify_candidate_hostname! hostname
      # Test the specified hostname against this regex.
      regex = /(?=^.{4,255}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)/
      return true if hostname =~ regex

      # Valid hostnames are always acceptable.
      resolve_host! hostname
    end

    def check_symbol_name! name
      if name !~ /\A[a-z0-9][a-z0-9_\-\.]*\z/
        raise RubykuError, "#{ name.inspect } is not a valid name"
      end
    end

    def app_username
      "app"
    end

  end

end
