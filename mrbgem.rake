MRuby::Gem::Specification.new('picoruby-mackerel') do |spec|
  spec.license = 'MIT'
  spec.author = 'PicoRuby Mackerel contributors'
  spec.summary = 'Small Mackerel metrics client for PicoRuby'
  spec.require_name = 'mackerel'

  spec.add_dependency 'picoruby-net-http'
  spec.add_dependency 'picoruby-json'
  spec.add_dependency 'picoruby-time'
end

