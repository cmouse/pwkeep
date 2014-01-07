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
     @options[:keysize] ||= 2048
     @options[:iterations] ||= 2000
     @options[:digest] ||= 'sha512'

     unless @options[:path].class == Pathname
       @options[:path] = Pathname.new(@options[:path].to_s).expand_path
     end
  
     if path.exist? 
       @lockfile = Lockfile.new path.join(".lock").to_s, :retries => 0
       @lockfile.lock
       ObjectSpace.define_finalizer(self, proc { @lockfile.unlock })
     end
   end

   def create
     return if path.exist?
     path.mkdir
     @lockfile = Lockfile.new path.join(".lock").to_s, :retries => 0
     @lockfile.lock
     ObjectSpace.define_finalizer(self, proc { @lockfile.unlock })
   end

   def keypair_create(password)
     # ensure it does not exist
     @key = OpenSSL::PKey::RSA.new @options[:keysize]
     cipher = OpenSSL::Cipher.new @options[:keycipher]

     path.join('private.pem').open 'w' do |io| io.write @key.export(cipher, password) end
   end

   def keypair_load(password)
     key_pem = path.join('private.pem').read
     @key = OpenSSL::PKey::RSA.new key_pem, password
   end

   def master_key_load
     unless @key
       raise PWKeep::Exception, "RSA private key required"
     end

     # load the key
     @master_key = @key.private_decrypt(path.join('master.key').open('rb') { |io| io.read },4)
   end

   def system_to_hash(system)
     d = Digest.const_get(@options[:digest].upcase).new

     system_h = system
     (0..@options[:iterations]).each do
         system_h = d.update(system_h).digest
         d.reset
     end
     "system-#{Base64.urlsafe_encode64(system_h)}"
   end

   def load_system(system)
     unless @key
       raise PWKeep::Exception, "Private key required"
     end

     system_h = system_to_hash(system)
     raise "Cannot find #{system}" unless path.join(system_h).exist?

     # found it, decrypt and load json
     # the file contains crypto name, iv len, iv, data
     header = nil
     data = nil
     path.join(system_h).open('rb') { |io| 
       header = io.read @options[:keysize]/8
       data = io.read 
     }

     # header
     cipher = @key.private_decrypt(header,4).unpack('Z*')[0]
     cipher = OpenSSL::Cipher.new cipher
     # re-unpack now that we know the size of the rest of the fields...
     header = @key.private_decrypt(header,4).unpack("Z*a#{cipher.iv_len}a#{cipher.key_len}")

     cipher.decrypt
     cipher.iv = header[1]
     cipher.key = header[2]

     # perform decrypt
     data = cipher.update(data) + cipher.final

     unless data[0] == "{" and data[-1] == "}" 
       raise PWKeep::Exception, "Corrupted data file"
     end

     JSON.load(data).deep_symbolize_keys
   end

   def save_system(system, data)
     unless @key
       raise PWKeep::Exception, "Private key required"
     end

     # write system
     system_h = system_to_hash(system)
     # encrypt data
     cipher = OpenSSL::Cipher::Cipher.new @options[:cipher]
     cipher.encrypt

     # use one time key and iv
     iv = cipher.random_iv
     key = cipher.random_key

     data = { :system => system, :data => data, :stored_at => Time.now }
     header = [cipher.name, iv, key].pack("Z*a#{cipher.iv_len}a#{cipher.key_len}")
     blob = cipher.update(data.to_json) + cipher.final

     # store system name to make search work 
     path.join(system_h).open('wb') do |io|
         io.write @key.public_encrypt header, 4
         io.write blob
     end
   end

   def valid?
     path.join('private.pem').exist? 
   end
end

end
