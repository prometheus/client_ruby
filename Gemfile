source 'https://rubygems.org'

gemspec

def ruby_version?(constraint)
  Gem::Dependency.new('', constraint).match?('', RUBY_VERSION)
end

group :test do
  gem 'coveralls'
  gem 'json', '< 2.0' if ruby_version?('< 2.0')
  gem 'rack', '< 2.0' if ruby_version?('< 2.2.2')
  gem 'rack-test'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop', ruby_version?('< 2.0') ? '< 0.42' : nil
  gem 'term-ansicolor', '< 1.4' if ruby_version?('< 2.0')
  gem 'tins', '< 1.7' if ruby_version?('< 2.0')
end
