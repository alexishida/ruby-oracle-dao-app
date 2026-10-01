# Ruby Oracle DAO App

Aplicação Ruby para executar consultas e comandos em um banco Oracle por meio da
classe `Connector::Oracle`. O projeto inclui configuração para os ambientes de
desenvolvimento e produção e scripts Linux para execução manual ou agendada.

## Requisitos

- Ruby com Bundler;
- Oracle Instant Client compatível com a arquitetura do sistema;
- bibliotecas do Instant Client disponíveis para o `ruby-oci8` (e ferramentas de
  compilação/SDK caso a instalação da gem precise compilar sua extensão nativa);
- acesso à instância Oracle.

O `Gemfile.lock` atual foi gerado em Linux (`x86_64-linux`), e os scripts
incluídos pressupõem que o Instant Client esteja em `/opt/oracle/instantclient`.

## Configuração

1. Instale as dependências Ruby:

   ```bash
   bundle install
   ```

2. Configure a conexão por variáveis de ambiente:

   ```bash
   export ORACLE_HOST="servidor:1521/nome_do_servico"
   export ORACLE_USER="usuario"
   export ORACLE_PASSWORD="sua_senha"
   ```

   Para credenciais distintas por ambiente, use os prefixos
   `ORACLE_DESENVOLVIMENTO_` e `ORACLE_PRODUCAO_`, seguidos de `HOST`, `USER` ou
   `PASSWORD`. Por exemplo, `ORACLE_PRODUCAO_HOST` substitui `ORACLE_HOST` apenas
   em produção.

   A precedência é: variável específica do ambiente, variável comum e valor de
   `config/application.rb`. O projeto não carrega arquivos `.env` automaticamente.
   Se necessário, os valores também podem ser definidos nesse arquivo:

   ```ruby
   desenvolvimento: {
     host: "servidor:1521/nome_do_servico",
     user: "usuario",
     password: "senha"
   }
   ```

   O valor de `host` é passado diretamente ao `OCI8.new`; use o formato de
   conexão adotado pela sua instalação Oracle.

   Não envie credenciais reais ao repositório. A configuração é validada ao abrir
   uma conexão, antes de carregar o driver Oracle.

3. Exponha as bibliotecas do Instant Client antes de executar a aplicação:

   ```bash
   export LD_LIBRARY_PATH=/opt/oracle/instantclient
   export PATH=/opt/oracle/instantclient:$PATH
   ```

## Execução

Execute usando o ambiente de desenvolvimento (padrão quando `APP_RUBY_ENV` não
está definido):

```bash
bundle exec ruby app.rb
```

Para produção:

```bash
bundle exec ruby app.rb --environment producao
```

Também é aceito o formato curto:

```bash
bundle exec ruby app.rb -e producao
```

Também é possível definir `APP_RUBY_ENV=producao`; a opção `-e` tem precedência
sobre a variável de ambiente. Valores diferentes de `desenvolvimento` e
`producao` são rejeitados. Use `ruby app.rb --help` para exibir a ajuda.

O ponto de entrada atual seleciona a configuração e imprime o cabeçalho; ainda
não há uma rotina de negócio ou consulta executada automaticamente.

O script [`run.sh`](run.sh) verifica as dependências já instaladas e inicia a
aplicação com `bundle exec`, usando produção por padrão ou `APP_RUBY_ENV` quando
definido. Instale Bundler e as gems antes de executá-lo. O caminho do Instant
Client pode ser alterado por `ORACLE_CLIENT_DIR`:

```bash
ORACLE_CLIENT_DIR=/opt/oracle/instantclient bash run.sh
```

## Uso do conector Oracle

A classe está em `libs/connectors/oracle.rb`. A forma com bloco encerra a conexão
automaticamente, inclusive em caso de erro. Ela não confirma transações
automaticamente:

```ruby
require_relative "libs/connectors/oracle"

config = Application.oracle_config("desenvolvimento")
Connector::Oracle.open(config) do |oracle|
  # Retorna um array e fecha o cursor automaticamente.
  linhas = oracle.consulta_retorno(
    "SELECT id, nome FROM minha_tabela WHERE ativo = :ativo", ativo: 1
  )

  # Processa linha a linha, sem acumular o resultado inteiro em memória.
  oracle.each_row("SELECT id, nome FROM minha_tabela") do |id, nome|
    puts "#{id}: #{nome}"
  end

  oracle.executar("UPDATE minha_tabela SET ativo = :ativo WHERE id = :id",
                  ativo: 1, id: 42)
  oracle.commit
end
```

Métodos disponíveis:

| Método | Finalidade |
| --- | --- |
| `consultar(sql, params = {})` | Devolve o cursor; com bloco, fecha-o automaticamente após o uso. |
| `consulta_retorno(sql, params = {})` | Devolve todas as linhas em um array e fecha o cursor. |
| `each_row(sql, params = {})` | Processa linhas com bloco ou devolve um enumerador. |
| `executar(sql, params = {})` | Executa SQL, devolve o resultado de `cursor.exec` e fecha o cursor. |
| `commit` | Confirma a transação atual. |
| `rollback` | Desfaz a transação atual. |
| `close` / `closed?` | Encerra a conexão / verifica se foi encerrada. |

`params` é um Hash de parâmetros vinculados, por nome ou posição. Para um valor
nulo com tipo explícito, use, por exemplo, `idade: { value: nil, type: Integer }`.
Os parâmetros são enviados a `OCI8::Cursor#bind_param`; não interpole valores de
usuários em SQL. Referência: [API do ruby-oci8 2.2.11](https://github.com/kubo/ruby-oci8/blob/ruby-oci8-2.2.11/lib/oci8/cursor.rb).

Ao usar `consultar` sem bloco, feche o cursor retornado com `cursor.close`.
Ao usar `Connector::Oracle.new` sem a forma `open` com bloco, encerre a conexão
com `oracle.close` em um `ensure`. `close` pode ser chamado mais de uma vez;
operações em uma conexão encerrada são rejeitadas.

Se a operação e o fechamento falharem, o erro da operação é preservado e a falha
de fechamento é registrada em `stderr`. Se apenas o fechamento falhar, sua
exceção é propagada. Após uma tentativa de `close`, a conexão não pode ser
reutilizada.

## Agendamento

O [`start.sh`](start.sh) configura uma entrada de `cron` para chamar `run.sh` no
início de cada hora, executa a aplicação uma vez e inicia `cron -f` em primeiro
plano. Ele é destinado a um contêiner dedicado com `cron` e `crontab` instalados,
com permissões para configurar o agendamento e iniciar o serviço.

```bash
bash start.sh
```

As demais entradas do usuário são preservadas. Executar o script novamente
substitui somente a tarefa marcada com `# ruby-oracle-dao-app`, evitando
duplicação. Os caminhos são calculados a partir da localização do projeto, e a
saída padrão e os erros são acrescentados a `log.txt`.

O script captura as variáveis exportadas de conexão, ambiente, Instant Client,
Ruby e Bundler em `tmp/cron.env`, com permissão `600` e fora do versionamento.
A execução inicial e a tarefa agendada carregam esse arquivo, preservando a
configuração mesmo quando o cron inicia com um ambiente mínimo. As credenciais
ficam no arquivo privado, sem aparecer no comando do crontab. Reinicie o serviço
por `start.sh` após alterar essas variáveis para atualizar o arquivo.

## Testes

Os testes Ruby usam Minitest, declarado no grupo `test` do Gemfile. Após instalar
as dependências desse grupo:

```bash
bundle exec ruby test/all_test.rb
bash test/scripts_test.sh
```

A suíte cobre argumentos da CLI, configuração, parâmetros SQL, fechamento de
cursores/conexões e falhas de execução. Os testes de shell simulam Bundler e cron,
incluindo preservação das tarefas existentes e interrupção quando faltam gems.
Nenhum desses testes precisa de um banco Oracle ou altera o cron real.

## Estrutura

```text
.
├── app.rb                     # Ponto de entrada
├── config/
│   ├── application.rb         # Metadados e resolução da configuração Oracle
│   └── initializer.rb         # Parser da CLI
├── libs/connectors/oracle.rb  # Adaptador para ruby-oci8
├── run.sh                     # Execução em produção
├── start.sh                   # Configuração de cron e inicialização
└── test/                      # Testes Ruby e shell sem banco
```

## Licença

Distribuído sob a [licença MIT](LICENSE).
