Gem::Specification.new do |s|
  s.name = 'pwkeep'
  s.version = '0.0.1'
  s.platform = Gem::Platform::RUBY
  s.authors = [ 'Aki Tuomi']
  s.email = %w( aki.tuomi@g-works.fi )
  s.summary = 'Simple password storage gem'
  s.description = 'A simple password storage utility'
  s.rubyforge_project = s.name
  s.files = `git ls-files`.split("\n")
  s.executables = %w( pwkeep )
  s.require_path = 'lib'
  s.add_dependency 'bundler'
  s.add_dependency 'ruby-gpgme'
  s.add_dependency 'colored'
  s.add_dependency 'highline'
end
