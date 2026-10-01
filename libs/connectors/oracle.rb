# frozen_string_literal: true

require_relative '../../config/application'

module Connector
  class Oracle
    def self.open(config = nil, **options)
      oracle = new(config, **options)
      return oracle unless block_given?

      begin
        yield oracle
      ensure
        original_error = $!
        begin
          oracle.close
        rescue StandardError => cleanup_error
          raise unless original_error

          warn "[WARN] Falha ao encerrar conexão: #{cleanup_error.class}: #{cleanup_error.message}"
        end
      end
    end

    def initialize(config = nil, connection: nil)
      if connection
        @con = connection
        return
      end

      config ||= defined?(ORACLE_CONFIG) ? ORACLE_CONFIG : Application.oracle_config
      raise ArgumentError, 'Configuração Oracle deve ser um Hash.' unless config.is_a?(Hash)

      missing = %w[host user password].select { |key| config[key].to_s.strip.empty? }
      unless missing.empty?
        raise ArgumentError, "Configuração Oracle ausente: #{missing.join(', ')}."
      end

      require 'oci8'
      @con = OCI8.new(config.fetch('user'), config.fetch('password'), config.fetch('host'))
    end

    # Sem bloco, o chamador deve fechar o cursor retornado.
    def consultar(sql, params = {})
      with_cursor(sql, params, close: block_given?) do |cursor|
        cursor.exec
        block_given? ? yield(cursor) : cursor
      end
    end

    def each_row(sql, params = {})
      return enum_for(__method__, sql, params) unless block_given?

      consultar(sql, params) { |cursor| cursor.fetch { |row| yield row } }
      self
    end

    def consulta_retorno(sql, params = {})
      each_row(sql, params).to_a
    end

    def executar(sql, params = {})
      with_cursor(sql, params) { |cursor| cursor.exec }
    end

    def commit
      connection.commit
    end

    def rollback
      connection.rollback
    end

    def close
      return if closed?

      con = @con
      @con = nil
      con.logoff
    end

    def closed?
      @con.nil?
    end

    private

    def connection
      raise IOError, 'Conexão Oracle encerrada.' if closed?

      @con
    end

    def with_cursor(sql, params, close: true)
      unless sql.is_a?(String) && !sql.strip.empty?
        raise ArgumentError, 'SQL deve ser uma string não vazia.'
      end
      raise ArgumentError, 'Parâmetros SQL devem ser um Hash.' unless params.is_a?(Hash)

      cursor = connection.parse(sql)
      transferred = false
      begin
        params.each { |name, value| cursor.bind_param(name, value) }
        result = yield cursor
        transferred = !close
        result
      ensure
        unless transferred
          original_error = $!
          begin
            cursor.close
          rescue StandardError => cleanup_error
            raise unless original_error

            warn "[WARN] Falha ao fechar cursor: #{cleanup_error.class}: #{cleanup_error.message}"
          end
        end
      end
    end
  end
end
