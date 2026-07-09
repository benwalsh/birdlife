require_relative 'boot'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
# require "active_storage/engine"
require 'action_controller/railtie'
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require 'action_view/railtie'
require 'action_cable/engine'
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Collage
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # The frame hangs in Connemara; keep everything on Irish local time.
    config.time_zone = 'Europe/Dublin'

    # The jobs dashboard (Mission Control, cloud/dev only — see the Gemfile group).
    # Configure here, before the engine's own initializer captures the defaults: gate it
    # through JobsBaseController (admin-only) and drop its built-in HTTP basic auth in
    # favour of that. Guarded so the Pi (no gem loaded) is unaffected.
    if defined?(MissionControl::Jobs)
      config.mission_control.jobs.base_controller_class = 'JobsBaseController'
      config.mission_control.jobs.http_basic_auth_enabled = false
    end

    config.generators do |g|
      g.template_engine :haml
      g.test_framework :rspec, fixtures: false, view_specs: false,
                               helper_specs: false, routing_specs: false
      g.system_tests = nil
    end
  end
end
