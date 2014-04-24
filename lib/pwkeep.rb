require 'bundler/setup'
require 'trollop'
require 'digest/sha2'
require 'logger'
require 'pathname'
require 'colorize'
require 'lockfile'
require 'openssl'

module PWKeep
  extend self

  def logger
    unless @logger
      @logger = Logger.new(STDOUT)
      @logger.formatter = proc do |severity, datetime, progname, msg| 
        "#{msg}\n"
      end
    end
    @logger
  end 

  class Exception < ::Exception
  end
end

require 'pwkeep/main'
require 'pwkeep/generator'
require 'pwkeep/storage'
require 'pwkeep/editor'
