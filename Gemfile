source 'https://rubygems.org'

gemspec

group :test do
  gem 'simplecov'
  gem 'json'
  gem 'rack'
  gem 'rack-test'
  gem 'rake'
  gem 'rspec'
  gem 'term-ansicolor'
  # The latest version of `tins` adds a dependency on `bigdecimal`, which
  # causes JRuby to fetch and build it rather than using its built-in version.
  # This fails on JRuby 9.1, so we need to handle that version  specifically.
  #
  # TODO: Remove this when we drop JRuby 9.1 from the build matrix
  if defined?(JRUBY_VERSION) && Gem::Version.new(JRUBY_VERSION) <= Gem::Version.new("9.2.0")
    gem 'tins', '<= 1.32.1'
  else
    gem 'tins'
  end
end
