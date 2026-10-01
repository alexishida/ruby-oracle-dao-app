# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require_relative '../config/initializer'

class ApplicationTest < Minitest::Test
  def test_default_environment
    assert_equal 'desenvolvimento', Application.parse_options([], env: {})[:environment]
  end

  def test_environment_variable_and_cli_precedence
    env = { 'APP_RUBY_ENV' => 'producao' }
    assert_equal 'producao', Application.parse_options([], env: env)[:environment]
    options = Application.parse_options(%w[-e desenvolvimento], env: env)
    assert_equal 'desenvolvimento', options[:environment]
  end

  def test_long_option_and_arguments_are_not_mutated
    argv = ['--environment=producao']
    assert_equal 'producao', Application.parse_options(argv, env: {})[:environment]
    assert_equal ['--environment=producao'], argv
  end

  def test_invalid_environment_does_not_fall_back_to_development
    assert_raises(ArgumentError) { Application.parse_options(%w[-e prod], env: {}) }
    assert_raises(ArgumentError) { Application.oracle_config('prod', env: {}) }
  end

  def test_invalid_cli_arguments
    assert_raises(OptionParser::InvalidOption) { Application.parse_options(['--unknown']) }
    assert_raises(OptionParser::MissingArgument) { Application.parse_options(['-e']) }
    assert_raises(OptionParser::InvalidArgument) { Application.parse_options(['unexpected']) }
  end

  def test_help_can_be_read_even_with_invalid_environment_variable
    options = Application.parse_options(['--help'], env: { 'APP_RUBY_ENV' => 'invalid' })
    assert options[:help]
    assert_includes options[:usage], '--environment'
  end

  def test_specific_credentials_override_common_credentials
    env = {
      'ORACLE_HOST' => 'common-host', 'ORACLE_USER' => 'common-user',
      'ORACLE_PASSWORD' => 'common-password', 'ORACLE_PRODUCAO_HOST' => 'prod-host'
    }
    assert_equal({ 'host' => 'prod-host', 'user' => 'common-user', 'password' => 'common-password' },
                 Application.oracle_config('producao', env: env))
    assert_equal 'common-host', Application.oracle_config('desenvolvimento', env: env)['host']
  end

  def test_file_configuration_is_used_when_environment_is_absent
    expected = APP_CONFIG[:oracle][:desenvolvimento].transform_keys(&:to_s)
    assert_equal expected, Application.oracle_config('desenvolvimento', env: {})
  end

  def test_configuration_uses_environment_variable_when_no_environment_is_passed
    env = { 'APP_RUBY_ENV' => 'producao', 'ORACLE_PRODUCAO_HOST' => 'prod-host' }
    assert_equal 'prod-host', Application.oracle_config(env: env)['host']
  end

  def test_cli_runs_from_another_directory
    Dir.mktmpdir do |directory|
      stdout, stderr, status = cli('-e', 'producao', chdir: directory)
      assert status.success?, stderr
      assert_includes stdout, '(producao)'
      assert_match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]/, stdout)
      assert_empty stderr
    end
  end

  def test_cli_help_and_error_exit_codes
    stdout, stderr, status = cli('--help')
    assert status.success?, stderr
    assert_includes stdout, 'Uso:'
    stdout, stderr, status = cli('-e', 'invalid')
    refute status.success?
    assert_empty stdout
    assert_includes stderr, 'Ambiente inválido'
  end

  def test_requiring_app_has_no_cli_side_effects
    ruby = ENV.fetch('TEST_RUBY', RbConfig.ruby)
    app = File.expand_path('../app.rb', __dir__)
    code = "ARGV.replace(['--unknown']); require #{app.dump}; " \
           "abort 'ARGV alterado' unless ARGV == ['--unknown']"
    stdout, stderr, status = Open3.capture3(ruby, '-e', code)
    assert status.success?, stderr
    assert_empty stdout
    assert_empty stderr
  end

  def test_requiring_connector_does_not_load_cli_or_oracle_driver
    ruby = ENV.fetch('TEST_RUBY', RbConfig.ruby)
    connector = File.expand_path('../libs/connectors/oracle.rb', __dir__)
    code = "before = $LOADED_FEATURES.dup; require #{connector.dump}; " \
           "added = $LOADED_FEATURES - before; " \
           "abort 'Dependência carregada prematuramente' if " \
           "added.any? { |path| path.match?(/optparse|oci8|config\\/initializer/) }"
    stdout, stderr, status = Open3.capture3(ruby, '-e', code)
    assert status.success?, stderr
    assert_empty stdout
    assert_empty stderr
  end

  private

  def cli(*args, **options)
    ruby = ENV.fetch('TEST_RUBY', RbConfig.ruby)
    Open3.capture3({ 'APP_RUBY_ENV' => nil }, ruby,
                  File.expand_path('../app.rb', __dir__), *args, **options)
  end
end
