# encoding: UTF-8

require 'simplecov'
require 'coveralls'

RSpec.configure do |c|
  c.warnings = true
end

SimpleCov.formatter =
  if ENV['CI']
    Coveralls::SimpleCov::Formatter
  else
    SimpleCov::Formatter::HTMLFormatter
  end

SimpleCov.start
