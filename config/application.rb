# frozen_string_literal: true

# Definindo variaveis
ENV["NLS_LANG"] = "BRAZILIAN PORTUGUESE_BRAZIL.AL32UTF8"

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
}
