# encoding: UTF-8

require "rack"
require "sinatra/base"

module Spontaneous
  module Rack
    NAMESPACE   = "/@spontaneous".freeze
    ACTIVE_USER = "SPONTANEOUS_USER".freeze
    ACTIVE_KEY  = "SPONTANEOUS_KEY".freeze
    AUTH_COOKIE = "spontaneous_api_key".freeze
    KEY_PARAM   = "__key".freeze
    RENDERER    = "spot.renderer".freeze

    EXPIRES_MAX = DateTime.parse("Thu, 31 Dec 2037 23:55:55 GMT").httpdate

    class << self
      def application
        case Spontaneous.mode
        when :back
          Back.application
        when :front
          Front.application
        end
      end

      def port
        Site.config.port
      end

      def make_front_controller(controller_class)
        controller_class.use(Spontaneous::Rack::AroundFront)
      end

      def make_back_controller(controller_class)
        controller_class.helpers Spontaneous::Rack::Helpers
        controller_class.helpers Spontaneous::Rack::UserHelpers
        controller_class.use Spontaneous::Rack::CookieAuthentication
        controller_class.use Spontaneous::Rack::AroundBack
        controller_class.register Spontaneous::Rack::Authentication
      end
    end

    class ServerBase < ::Sinatra::Base
      set :environment, Proc.new { Spontaneous.environment }
    end

    autoload :AroundBack,           'spontaneous/rack/around_back'
    autoload :AroundFront,          'spontaneous/rack/around_front'
    autoload :AroundPreview,        'spontaneous/rack/around_preview'
    autoload :Assets,               'spontaneous/rack/assets'
    autoload :Authentication,       'spontaneous/rack/authentication'
    autoload :Back,                 'spontaneous/rack/back'
    autoload :CSS,                  'spontaneous/rack/css'
    autoload :CacheableFile,        'spontaneous/rack/cacheable_file'
    autoload :CookieAuthentication, 'spontaneous/rack/cookie_authentication'
    autoload :EventSource,          'spontaneous/rack/event_source'
    autoload :Front,                'spontaneous/rack/front'
    autoload :HTTP,                 'spontaneous/rack/http'
    autoload :Helpers,              'spontaneous/rack/helpers'
    autoload :JS,                   'spontaneous/rack/js'
    autoload :PageController,       "spontaneous/rack/page_controller"
    autoload :Public,               'spontaneous/rack/public'
    autoload :QueryAuthentication,  'spontaneous/rack/query_authentication'
    autoload :Reloader,             'spontaneous/rack/reloader'
    autoload :SSE,                  'spontaneous/rack/sse'
    autoload :Static,               'spontaneous/rack/static'
    autoload :UserAdmin,            'spontaneous/rack/user_admin'
    autoload :UserHelpers,          'spontaneous/rack/user_helpers'
  end
end
