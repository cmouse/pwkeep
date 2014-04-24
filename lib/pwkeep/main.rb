require 'highline/import'
require 'keepass/password'

module PWKeep
  class Main
     attr :opts
  
     def initialize
       @opts = { :home => ENV['PWKEEP_HOME'] || '~/.pwkeep' } # required value
     end

     def keypair_load
       counter = 0
       while true 
         begin
           pw = ask("Enter your password:") { |q| q.echo = false }
           @storage.keypair_load pw
         rescue OpenSSL::PKey::RSAError => e
           say "<%= color('Invalid password', RED) %>"
           counter = counter + 1
           if (counter>2) 
             raise e
           end
           next
         end
         break
       end
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
         opt :list, "List all known systems", :short => '-l'
         opt :help, "Show usage", :short => '-h'
         opt :home, "Home directory", :short => '-H', :type => :string, :default => ( ENV['PWKEEP_HOME'] || '~/.pwkeep' )
         opt :version, "Show version", :short => '-V'
       end
  
       # validate options
       Trollop::die :system, "must be given for create/show/edit/delete" if opts[:system].nil? and (opts[:edit] or opts[:view] or opts[:delete] or opts[:create])
       Trollop::die :create, "can only have one mode of operation" if opts[:create] and (opts[:edit] or opts[:view] or opts[:delete] or opts[:search] or opts[:initialize] or opts[:list])
       Trollop::die :edit, "can only have one mode of operation" if opts[:edit] and (opts[:create] or opts[:view] or opts[:delete] or opts[:search] or opts[:initialize] or opts[:list])
       Trollop::die :view, "can only have one mode of operation" if opts[:view] and (opts[:edit] or opts[:create] or opts[:delete] or opts[:search] or opts[:initialize] or opts[:list])
       Trollop::die :delete, "can only have one mode of operation" if opts[:delete] and (opts[:edit] or opts[:view] or opts[:create] or opts[:search] or opts[:initialize] or opts[:list])
       Trollop::die :search, "can only have one mode of operation" if opts[:search] and (opts[:edit] or opts[:view] or opts[:delete] or opts[:create] or opts[:initialize] or opts[:list])
       Trollop::die :initialize, "can only have one mode of operation" if opts[:initialize] and (opts[:edit] or opts[:view] or opts[:delete] or opts[:create] or opts[:search] or opts[:list])
       Trollop::die :list, "can only have one mode of operation" if opts[:list] and (opts[:edit] or opts[:view] or opts[:delete] or opts[:create] or opts[:search] or opts[:initialize])
  
       Trollop::die "You must choose one mode of operation" unless opts[:create] or opts[:edit] or opts[:view] or opts[:delete] or opts[:search] or opts[:initialize] or opts[:list]
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
           keypair_load
   
           data = @storage.load_system opts[:system]
  
           say("Last edited: #{data[:stored_at]}\nSystem: #{data[:system]}\n\n")
           say(data[:data])
           return 
         end
  
         if opts[:create]
           data = "Username: \nPassword: #{KeePass::Password.generate('uullA{6}')}"
           
           result = PWKeep.run_editor(data, {})
  
           unless result[0]
             raise PWKeep::Exception, "Not modified"
           end
  
           keypair_load
           @storage.save_system opts[:system], result[1]
           say("<%= color('Changes stored', GREEN)%>")
           return
         end
  
         if opts[:edit]
           keypair_load
           data = @storage.load_system opts[:system]
           result = PWKeep.run_editor(data[:data], {})
           unless result[0]
             raise PWKeep::Exception, "Not modified"
           end
           @storage.save_system opts[:system], result[1]
           say("<%= color('Changes stored', GREEN)%>")
           return
         end
  
         if opts[:delete]
           keypair_load
           data = @storage.load_system opts[:system]
           # just to be sure
           unless agree("Are you <%=color('SURE',BOLD)%> you want to delete #{data[:system]}?")
             @storage.delete data[:system]
           end
           say("<%= color('System deleted', YELLOW)%>")
           return
         end
  
         if opts[:search]
           keypair_load
           say("All matching systems\n")
           @storage.list_all_systems.sort.each do |system|
             if system.match opts[:search]
               say("  - #{system}")
             end
           end
           return
         end
  
         if opts[:list]
           keypair_load
           say("All known systems\n")
           @storage.list_all_systems.sort.each do |system| 
             say("  - #{system}")
           end
           return
         end
       rescue PWKeep::Exception => e1
        PWKeep::logger.error e1.message.colorize(:red)
       rescue OpenSSL::PKey::RSAError => e2
        PWKeep::logger.error "Cannot load private key".colorize(:red)
       rescue SystemExit,Interrupt
        # ignore
       end
     end
  end
end
