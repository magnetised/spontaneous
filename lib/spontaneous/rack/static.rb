
module Spontaneous
  module Rack
    class Static
      ALLOWED_METHODS = %w(GET HEAD).freeze

      def initialize(app, options)
        @app = app
        @try = ['', *options.delete(:try)].compact
        @static = ::Rack::Static.new(
          lambda { |env| [404, {}, []] },
          options)
      end

      def call(env)
        return @app.call(env) unless ALLOWED_METHODS.include?(env[S::REQUEST_METHOD])
        orig_path = env['PATH_INFO']
        found = nil
        @try.each do |path|
          resp = @static.call(env.merge!({'PATH_INFO' => orig_path + path}))
          break if 404 != resp[0] && found = resp
        end
        found or @app.call(env.merge!('PATH_INFO' => orig_path))
      end

    end
  end
end
