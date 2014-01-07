require 'highline/import'

module PWKeep

class Main
   attr :opts

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

   def run
     setup
     begin
       if opts[:initialize]
         @storage = PWKeep::Storage.new(:path => opts[:home])
#         @storage.create
#         # create a keypair
#         pw_a = ""
#         pw_b = ""
#         while(pw_a == "" or pw_a != pw_b)
#            pw_a = ask("Enter your password:   ") { |q| q.echo = false }
#            pw_b = ask("Confirm your password: ") { |q| q.echo = false }
#            say("<%= color('red') %>Passwords did not match") unless pw_a == pw_b
#         end
#         @storage.keypair_create(pw_b)
#         # this concludes initialization
#         say("<%= color('green') %>Password storage initialized")
          pw_b = 'test'
          @storage.keypair_load(pw_b)
          @storage.master_key_load
          data = @storage.load_system "test"

          Dispel::Screen.open do |screen|
            $ruco_screen = screen
            app = PWKeep::EditorApplication.new(data.to_s, 
              :lines => screen.lines, :columns => screen.columns
            )
          
            screen.draw *app.display_info
          
            Dispel::Keyboard.output do |key|
              if key == :resize
                app.resize(screen.lines, screen.columns)
              else
                result = app.key key
                if result == :quit
                  data = app.content
                  break
                end
              end
          
              screen.draw *app.display_info
            end
          end
 
          # FIXME: Check if there has been actual change.
          @storage.save_system "test", data
          say("<%= color('Contents updated', GREEN) %>")
       end
     rescue PWKeep::Exception => e
      PWKeep::logger.error e.message.colorize(:red)
     end
   end
end

end
