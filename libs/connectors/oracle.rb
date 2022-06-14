# frozen_string_literal: true
require 'oci8'

module Connector
  class Oracle
    def initialize
     @con = OCI8.new(ORACLE_CONFIG['user'], ORACLE_CONFIG['password'], ORACLE_CONFIG['host'])
    end

    def consultar(sql)
      cursor = @con.parse(sql)
      cursor.exec
      return cursor
    end

    def consulta_retorno(sql)
      dados = []
      cursor = @con.parse(sql)
      cursor.exec
      cursor.fetch do |row|
        dados << row
      end
      return dados
    end

    def executar(sql)
      cursor = @con.parse(sql)
      cursor.exec
    end

    def commit
      @con.commit
    end

  end
end