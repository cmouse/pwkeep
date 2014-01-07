require 'yaml'
require 'singleton'

module PWKeep
  class Config < Hashr 
    def load(file)
      self.merge YAML.load_file(file)
    end
  end
end
