Gem::Specification.new do |s|
  s.name = 'pwkeep'
  s.version = '0.0.3'
  s.platform = Gem::Platform::RUBY
  s.authors = [ 'Aki Tuomi']
  s.email = %w( aki.tuomi@g-works.fi )
  s.summary = 'Simple password storage gem'
  s.description = 'A simple password storage utility'
  s.rubyforge_project = s.name
  s.files = `git ls-files`.split("\n")
  s.executables = %w( pwkeep )
  s.require_path = 'lib'
  s.license = 'MIT'
  s.add_dependency 'bundler'
  s.add_dependency 'colorize'
  s.add_dependency 'highline'
  s.add_dependency 'trollop'
  s.add_dependency 'lockfile'
  s.add_dependency 'hashr'
  s.add_dependency 'ruco'
  s.add_dependency 'keepass-password-generator'
end
