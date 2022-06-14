# frozen_string_literal: true
require 'optparse'
require './config/application'

# Definindo ambiente
ENV['APP_RUBY_ENV'] = 'desenvolvimento'
ARGV.options do |opts|
  opts.on("-e", "--environment=val", String)   { |val| ENV['APP_RUBY_ENV'] = val }
  opts.parse!
end

# Setando Variaveis do Oracle Conforme o Ambiente
if ENV['APP_RUBY_ENV'] == 'producao'
    ORACLE_CONFIG = Hash.new
    ORACLE_CONFIG['host'] = APP_CONFIG[:oracle][:producao][:host]
    ORACLE_CONFIG['user'] = APP_CONFIG[:oracle][:producao][:user]
    ORACLE_CONFIG['password'] = APP_CONFIG[:oracle][:producao][:password]
else
    ORACLE_CONFIG = Hash.new
    ORACLE_CONFIG['host'] = APP_CONFIG[:oracle][:desenvolvimento][:host]
    ORACLE_CONFIG['user'] = APP_CONFIG[:oracle][:desenvolvimento][:user]
    ORACLE_CONFIG['password'] = APP_CONFIG[:oracle][:desenvolvimento][:password]
end
puts "---------------------------------------"
puts "[ SISTEMA #{APP_CONFIG[:programa][:versao]} - #{APP_CONFIG[:programa][:data]} ]"
puts "---------------------------------------"
puts "[#{ Date.time_now }] [INFO] Rodando no ambiente de (#{ENV['APP_RUBY_ENV']})"
