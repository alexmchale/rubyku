module Rubyku

  class RemoteProcedure

    include FileUtils
    include Term::ANSIColor

    attr_reader :hostname, :options

    def initialize(hostname, options = {})
      @hostname = hostname
      @options  = options
    end

    def esc(string)
      Shellwords.escape(string.to_s.strip)
    end

    def ssh(username, command)
      die "@hostname is not configured" if @hostname.to_s == ""

      puts magenta(command.gsub(/^\s+/, "").gsub(/ +/, " ").strip)
      puts

      Net::SSH.start(@hostname, username) do |ssh|
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

        [ stdout_data, stderr_data, exit_code, exit_signal ]
      end
    end

    def ssh_run_template(username, template, template_options = {})
      ssh(username, read_template_file(template, template_options))
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

    def log(message)
      puts
      puts "#{ yellow '---->' } #{ green message.to_s }"
      puts
    end

    def die(message)
      log red(message.to_s)
      exit 1
    end

    def read_template_file(filename, replacements = {})
      path   = File.expand_path("../../../templates/#{ filename }", __FILE__)
      string = File.read(path)

      replacements.merge({
        :app          => remote_project_name                                ,
        :app_username => app_username                                       ,
        :app_home     => "/home/#{ app_username }"                          ,
        :app_root     => "/home/#{ app_username }/#{ remote_project_name }" ,
        :hostname     => hostname                                           ,
      }).inject(string) do |string, (key, value)|
        string
          .gsub("%%esc:#{ key }%%", esc(value.to_s))
          .gsub("%%#{ key }%%", value.to_s)
      end
    end

    def read_project_config(key)
      check_and_chdir_git! local_git_path

      yaml_filename = File.join(local_git_path, "config", "rubyku.yml")
      yaml          = if File.file?(yaml_filename) then File.read(yaml_filename) end
      yaml_hash     = if yaml then YAML.load(yaml) end
      yaml_hash[key]  if yaml_hash
    end

    def yesno(prompt = 'Continue?', default = false)
      a = ''
      s = default ? '[Y/n]' : '[y/N]'
      d = default ? 'y' : 'n'
      until %w[y n].include? a
        a = ask("#{prompt} #{s} ") { |q| q.limit = 1; q.case = :downcase }
        a = d if a.length == 0
      end
      a == 'y'
    end

    def check_and_chdir_git!(local_git_path)
      # Check that the path exists
      if !File.directory?(File.join(local_git_path, ".git"))
        die "#{ local_git_path } is not a git repository"
      else
        chdir local_git_path
      end

      # Check that config/database.yml isn't checked in, is ignored
      if system("git ls-files config/database.yml --error-unmatch > /dev/null 2>&1")
        die "database.yml is checked into git and should not be"
      end

      # Check that config/database.yml isn't checked in, is ignored
      if !system("git check-ignore config/database.yml > /dev/null 2>&1")
        die "database.yml is not ignored by git and should be"
      end

      # Test that the proj has .ruby-version
      if !File.file?(".ruby-version")
        die "repository must have a .ruby-version file"
      end
    end

    def app_username
      "app"
    end

  end

end
