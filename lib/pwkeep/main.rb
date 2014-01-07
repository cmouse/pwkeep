require 'highline/import'
require 'keepass/password'

module PWKeep

class Main
   attr :opts

   def initialize
     @opts = { :home => ENV['PWKEEP_HOME'] || '~/.pwkeep' } # required value
   end

   def setup
     @opts = Trollop::options do
       version "0.0.1 (c) 2014 Aki Tuomi"
       banner <<-EOS
This program is a simple password storage utility. Distributed under MIT license. NO WARRANTY.

Usage:
       #{$0} [options]

Where [options] are
 
EOS
       opt :system, "System name", :type => :string, :short => '-n'
       opt :initialize, "Initialize storage at ~/.pwkeep (you can change this with PWKEEP_HOME or --home)", :short => '-i'
       opt :create, "Create new entry", :short => '-c'
       opt :view, "View entry", :short => '-v'
       opt :edit, "Edit entry", :short => '-e'
       opt :delete, "Delete entry", :short => '-d'
       opt :search, "Search for system or username", :type => :string, :short => '-s'
       opt :help, "Show usage", :short => '-h'
       opt :home, "Home directory", :short => '-H', :type => :string, :default => ( ENV['PWKEEP_HOME'] || '~/.pwkeep' )
       opt :version, "Show version", :short => '-V'
     end

     # validate options
     Trollop::die :system, "must be given for create/show/edit/delete" if opts[:system].nil? and (opts[:edit] or opts[:view] or opts[:delete] or opts[:create])
     Trollop::die :create, "can only have one mode of operation" if opts[:create] and (opts[:edit] or opts[:view] or opts[:delete] or opts[:search] or opts[:initialize])
     Trollop::die :edit, "can only have one mode of operation" if opts[:edit] and (opts[:create] or opts[:view] or opts[:delete] or opts[:search] or opts[:initialize])
     Trollop::die :view, "can only have one mode of operation" if opts[:view] and (opts[:edit] or opts[:create] or opts[:delete] or opts[:search] or opts[:initialize])
     Trollop::die :delete, "can only have one mode of operation" if opts[:delete] and (opts[:edit] or opts[:view] or opts[:create] or opts[:search] or opts[:initialize])
     Trollop::die :search, "can only have one mode of operation" if opts[:search] and (opts[:edit] or opts[:view] or opts[:delete] or opts[:create] or opts[:initialize])
     Trollop::die :initialize, "can only have one mode of operation" if opts[:initialize] and (opts[:edit] or opts[:view] or opts[:delete] or opts[:create] or opts[:search])
     Trollop::die "You must choose one mode of operation" unless opts[:create] or opts[:edit] or opts[:view] or opts[:delete] or opts[:search] or opts[:initialize]
   end

   def self.run
     Main.new.run
   end

   def load_config
     config_file = Pathname.new(@opts[:home]).expand_path.join('config.yml')
     if config_file.exist? 
        PWKeep::Config.instance.load(config_file)
     end 
   end

   def run
     setup
     load_config
     @storage = PWKeep::Storage.new(:path => opts[:home])

     begin
       if opts[:initialize]
         @storage.create

         if @storage.valid? 
           say("<%= color('WARNING!', BOLD) %> a valid pwkeep storage was found!")
           say("If you continue, the existing storage becomes <%= color('UNUSABLE', BOLD) %>")
           unless agree("Continue (y/n)? ") 
             raise PWKeep::Exception, "Storage initialization aborted" 
           end
         end

         # create a keypair
         pw_a = ""
         pw_b = ""
         while(pw_a == "" or pw_a != pw_b)
            pw_a = ask("Enter your password:   ") { |q| q.echo = false }
            pw_b = ask("Confirm your password: ") { |q| q.echo = false }
            say("<%= color('Passwords did not match', RED %>") unless pw_a == pw_b
         end
         @storage.keypair_create(pw_b)
         # this concludes initialization
         say("<%= color('Password storage initialized', GREEN %>")
         return
       end
 
       raise "Storage not initialized (run with --initialize)" unless @storage.valid? 

       if opts[:view]
         pw = ask("Enter your password:") { |q| q.echo = false }
         @storage.keypair_load pw
 
         data = @storage.load_system opts[:system]

         say("Last edited: #{data[:stored_at]}\nSystem: #{data[:system]}\n\n")
         say(data[:data])
         return 
       end

       if opts[:create]
         data = "Username: \nPassword: #{KeePass::Password.generate('uullA{6}')}"
         
         result = PWKeep.run_editor(data, {})

         unless result[0]
           raise "Not modified"
         end

         pw = ask("Enter your password:") { |q| q.echo = false }
         @storage.keypair_load pw
         @storage.save_system opts[:system], result[1]
         say("<%= color('Changes stored', GREEN)%>")
         return
       end

       if opts[:edit]
         pw = ask("Enter your password:") { |q| q.echo = false }
         @storage.keypair_load pw
         data = @storage.load_system opts[:system]
         result = PWKeep.run_editor(data[:data], {})
         unless result[0]
           raise "Not modified"
         end
         @storage.save_system opts[:system], result[1]
         say("<%= color('Changes stored', GREEN)%>")
         return
       end
     rescue PWKeep::Exception => e
      PWKeep::logger.error e.message.colorize(:red)
      return
     end
   end
end

end
