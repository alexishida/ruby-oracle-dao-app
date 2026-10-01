# frozen_string_literal: true

require 'optparse'
require_relative 'application'

module Application
  def self.parse_options(argv, env: ENV)
    options = { environment: env.fetch('APP_RUBY_ENV', 'desenvolvimento'), help: false }
    parser = OptionParser.new do |opts|
      opts.banner = 'Uso: ruby app.rb [opções]'
      opts.on('-e AMBIENTE', '--environment AMBIENTE', ENVIRONMENTS.join(' ou ')) do |value|
        options[:environment] = value
      end
      opts.on('-h', '--help', 'Exibe esta ajuda') { options[:help] = true }
    end

    remaining = parser.parse(argv)
    raise OptionParser::InvalidArgument, remaining.join(' ') unless remaining.empty?

    validate_environment!(options[:environment]) unless options[:help]
    options[:usage] = parser.to_s
    options
  end

end
