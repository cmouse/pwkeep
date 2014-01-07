require 'yaml'

module PWKeep

class Config < Hashr
  def load(file)
    self.merge YAML.load(file)
  end
end

end
