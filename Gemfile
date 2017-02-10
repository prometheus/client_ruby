source 'https://rubygems.org'

gemspec

def ruby_version?(constraint)
  Gem::Dependency.new('', constraint).match?('', RUBY_VERSION)
end

gem 'mmap', git: 'https://github.com/lyda/mmap.git', :branch => 'modern-ruby'

group :test do
  gem 'json', '< 2.0' if ruby_version?('< 2.0')
  gem 'coveralls'
  gem 'rack', '< 2.0' if ruby_version?('< 2.2.2')
  gem 'rack-test'
  gem 'rake'
  gem 'rspec'
  gem 'rubocop', ruby_version?('< 2.0') ? '< 0.42' : nil
  gem 'tins', '< 1.7' if ruby_version?('< 2.0')
end
