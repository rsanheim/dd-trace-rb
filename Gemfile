source 'https://rubygems.org'

gemspec

if RUBY_VERSION >= '3.0.0'
  gem 'webrick', '>= 1.7.0' # No longer bundled by default since Ruby 3.0
end

if RUBY_VERSION < '2.1.0'
  gem 'json', '< 2.5.0' # > 2.5 have a bug with Ruby 2.0: https://github.com/flori/json/issues/464
  gem 'safe_yaml' # Allow use of YAML.safe_load on all supported rubies
end

# This file was generated by Appraisal

unless ENV['CI'] == 'true'
  gem 'hiredis'
  gem 'lograge'
  gem 'makara'
  # gem 'rails', '~> 5.2.1'
  # gem 'activerecord', '6.1.1'
  gem 'redis'
  gem 'redis-rails'
  gem 'sprockets', '< 4'
  gem 'sidekiq', '< 5'

  # gem 'activerecord-jdbcmysql-adapter', platform: :jruby
  # gem 'activerecord-jdbcpostgresql-adapter', platform: :jruby
  # gem 'jdbc-sqlite3', '>= 3.28', platform: :jruby
  # gem 'mysql2', '< 1', platform: :ruby
  # gem 'pg', '< 1.0', platform: :ruby
  # gem 'sqlite3', '~> 1.4.1', platform: :ruby
end
