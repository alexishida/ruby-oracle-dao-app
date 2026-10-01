# frozen_string_literal: true

# Deve ser definido antes de carregar o driver Oracle.
ENV['NLS_LANG'] ||= 'BRAZILIAN PORTUGUESE_BRAZIL.AL32UTF8'

# Configurações da aplicação
APP_CONFIG = {
  oracle: {
    desenvolvimento: {
      host: "",
      user: "",
      password: "",
    },

    producao: {
      host: "",
      user: "",
      password: "",
    }
  },
  programa: {
    versao: "1.0.0",
    data: '14/06/2022'
  }
}.freeze

module Application
  ENVIRONMENTS = %w[desenvolvimento producao].freeze

  def self.oracle_config(environment = nil, env: ENV)
    environment ||= env.fetch('APP_RUBY_ENV', 'desenvolvimento')
    validate_environment!(environment)
    APP_CONFIG.fetch(:oracle).fetch(environment.to_sym).each_with_object({}) do |(key, value), config|
      config[key.to_s] = env.fetch("ORACLE_#{environment.upcase}_#{key.upcase}") do
        env.fetch("ORACLE_#{key.upcase}", value)
      end
    end
  end

  def self.validate_environment!(environment)
    return if ENVIRONMENTS.include?(environment)

    raise ArgumentError, "Ambiente inválido: #{environment.inspect}. Use #{ENVIRONMENTS.join(' ou ')}."
  end
  private_class_method :validate_environment!
end
