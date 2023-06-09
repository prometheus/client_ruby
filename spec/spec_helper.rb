# encoding: UTF-8

require 'simplecov'
require 'timecop'

RSpec.configure do |c|
  c.warnings = true
end

SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter

SimpleCov.start

Timecop.safe_mode = true
