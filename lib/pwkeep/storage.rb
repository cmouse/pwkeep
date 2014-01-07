require 'securerandom'
require 'base64'
require 'json'
require 'hashr'

module PWKeep

class Storage
   def path
     @options[:path]
   end

   def initialize(options)
     @options = options
 
     @options[:cipher] ||= 'AES-256-CTR'
     @options[:keycipher] ||= 'AES-256-CBC'
     @options[:keysize] ||= 2048
     @options[:hash_rounds] ||= 2000

     unless @options[:path].class == Pathname
       @options[:path] = Pathname.new(@options[:path].to_s).expand_path
     end
  
     if path.exist? 
       @lockfile = Lockfile.new path.join(".lock").to_s
       ObjectSpace.define_finalizer(self, proc { @lockfile.unlock })
     end
   end

   def create
     return if path.exist?
     path.mkdir
     @lockfile = Lockfile.new path.join(".lock").to_s
     ObjectSpace.define_finalizer(self, proc { @lockfile.unlock })
   end

   def keypair_create(password)
     # ensure it does not exist
     @key = OpenSSL::PKey::RSA.new @options[:keysize]
     cipher = OpenSSL::Cipher::Cipher.new @options[:keycipher]

     path.join('private.pem').open 'w' do |io| io.write key.export(cipher, password) end
   end

   def keypair_load(password)
     key_pem = path.join('private.pem').read
     @key = OpenSSL::PKey::RSA.new key_pem, password
   end

   def master_key_create
     # generates master key and encrypt it with private key
     unless @key
       raise PWKeep::Exception, "RSA private key required"
     end

     # figure out key size
     cipher = OpenSSL::Cipher::Cipher.new @options[:cipher]
     @master_key = SecureRandom.random_bytes(cipher.key_len)
     
     # encrypt & store
     path.join('master.key').open 'w' do |io| io.write Base64.encode64(@key.public_encrypt(master_key, 4)) end
   end

   def master_key_load
     unless @key
       raise PWKeep::Exception, "RSA private key required"
     end

     # load the key
     @master_key = @key.private_decrypt(Base64.strict_decode64(path.join('master.key').read.gsub! "\n",""),4)
   end

   def system_to_hash(system)
     d = Digest::SHA512.new
     system_h = system
     (0..@options[:hash_rounds]).each do
         system_h = d.update(system_h).digest
         d.reset
     end
     Base64.urlsafe_encode64(system_h)
   end

   def load_system(system)
     unless @master_key
       raise PWKeep::Exception, "Master key required"
     end

     system_h = system_to_hash(system)
     raise "Cannot find #{system}" unless path.join(system_h).exist?

     # found it, decrypt and load json
 
     state = 0 # 0 = init, 1 = header, 2 = body, 3 = end
     opts = {}
     blob = ""
     path.join(system_h).each_line do |line|
       if state == 0 and line != "----- BEGIN ENCRYPTED DATA -----\n"
         raise "Cannot parse data"
       elsif state == 0
         state = 1
         next
       end

       if state == 1 and line =~ /^\s*([^:]+)\s*:\s*(\S+)\s*/
         if $1.downcase == 'dek-info'
           (opts[:cipher], opts[:iv]) = $2.split /,/
         end
         next
       elsif state == 1 and line.chomp == ""
         state = 2
         next
       end

       if state == 2 and line.chomp == "----- END ENCRYPTED DATA -----"
         state = 3
         break
       elsif state == 2
         blob = blob + line.chomp
         next
       end

       break
     end

     raise "Cannot parse data" unless state == 3

     blob = Base64.strict_decode64(blob)

     # decrypt the file with iv
     cipher = OpenSSL::Cipher::Cipher.new opts[:cipher]
     cipher.decrypt

     cipher.key = @master_key
     cipher.iv = [opts[:iv]].pack('H*')

     # perform decrypt
     JSON.load(cipher.update(blob) + cipher.final).deep_symbolize_keys[:data]
   end

   def save_system(system, data)
     unless @master_key
       raise PWKeep::Exception, "Master key required"
     end

     # write system
     system_h = system_to_hash(system)
     # encrypt data
     cipher = OpenSSL::Cipher::Cipher.new @options[:cipher]
     cipher.encrypt
     iv = cipher.random_iv
     cipher.key = @master_key 

     data = { :system => :system, :data => data, :stored_at => Time.now }
     blob = Base64.encode64(cipher.update(data.to_json) + cipher.final)

     # store system name to make search work 
     path.join(system_h).open('w') do |io|
        io.write "----- BEGIN ENCRYPTED DATA -----\n"
        io.write "DEK-Info: #{cipher.name},#{iv.unpack('H*').join('').upcase}\n"
        io.write "\n"
        io.write blob
        io.write "----- END ENCRYPTED DATA -----\n" 
     end
   end
end

end
