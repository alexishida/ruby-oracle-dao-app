# frozen_string_literal: true

require_relative 'config/initializer'

if __FILE__ == $PROGRAM_NAME
  begin
    options = Application.parse_options(ARGV)
    if options[:help]
      puts options[:usage]
    else
      environment = options.fetch(:environment)
      ENV['APP_RUBY_ENV'] = environment
      ORACLE_CONFIG = Application.oracle_config(environment).freeze

      puts '---------------------------------------'
      puts "[ SISTEMA #{APP_CONFIG[:programa][:versao]} - #{APP_CONFIG[:programa][:data]} ]"
      puts '---------------------------------------'
      puts "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] [INFO] Rodando no ambiente de (#{environment})"
    end
  rescue OptionParser::ParseError, ArgumentError => e
    warn "[ERRO] #{e.message}"
    exit 1
  end
end
