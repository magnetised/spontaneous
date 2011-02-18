# encoding: UTF-8

require 'less'

module Spontaneous
  module Rack
    module Back
      NAMESPACE = "/@spontaneous".freeze
      AUTH_COOKIE = "spontaneous_api_key".freeze

      module Authentication
        module Helpers
          def authorised?
            if cookie = request.cookies[AUTH_COOKIE]
              true
            else
              false
            end
          end

          def api_key
            request.cookies[AUTH_COOKIE]
          end

          def user
            api_key = request.cookies[AUTH_COOKIE]
            if api_key && key = Spontaneous::Permissions::AccessKey.authenticate(api_key)
              key.user
            else
              nil
            end
          end
        end

        def self.registered(app)
          app.helpers Authentication::Helpers
          app.post "/login" do
            login = params[:user][:login]
            password = params[:user][:password]
            if key = Spontaneous::Permissions::User.authenticate(login, password)
              response.set_cookie(AUTH_COOKIE, {
                :value => key.key_id,
                :path => '/'
              })
              redirect NAMESPACE, 302
            else
              halt(401, erubis(:login))
            end
          end
        end

        def requires_authentication!(options = {})
          exceptions = (options[:except] || []).push("#{NAMESPACE}/login" )
          before do
            # puts "AUTH: path:#{request.path} user:#{user.inspect}"
            # p exceptions.detect { |e| e === request.path }
            unless exceptions.detect { |e| e === request.path }
              unless user
                halt(401, erubis(:login)) unless user
              end
            end
          end
        end

      end


      def self.application
        app = ::Rack::Builder.new {
          # use ::Rack::CommonLogger, STDERR  if Spontaneous.development?
          use ::Rack::Lint
          use ::Rack::ShowExceptions if Spontaneous.development?

          map NAMESPACE do
            run EditingInterface
          end

          map "/" do
            run Preview
          end
        }
      end

      class EditingInterface < ServerBase

        use AroundBack
        register Authentication

        requires_authentication! :except => %w(static css js).map{ |p| %r(^#{NAMESPACE}/#{p}) }

        set :views, Proc.new { Spontaneous.application_dir + '/views' }

        def json(response)
          content_type 'application/json', :charset => 'utf-8'
          response.to_json
        end

        def update_fields(model, field_data)
          field_data.each do | name, values |
            model.fields[name].update(values)
          end
          if model.save
            json(model)
          end
        end

        helpers do
          def scripts(*scripts)
            if Spontaneous.development?
              scripts.map do |script|
                src = "/js/#{script}.js"
                path = Spontaneous.application_dir(src)
                size = File.size(path)
                ["#{NAMESPACE}#{src}", size]
                # %(<script src="#{NAMESPACE}/js/#{script}.js" type="text/javascript"></script>)
              end.to_json
            else
              # script bundling + compression
            end
          end
        end

        get '/?' do
          p @user
          erubis :index
        end

        get '/root' do
          json Site.root
        end

        get '/page/:id' do
          json Content[params[:id]]
        end

        get '/types' do
          json Schema
        end

        # get '/type/:type' do
        #   klass = params[:type].gsub(/\\./, "::").constantize
        #   json klass
        # end

        get '/map' do
          json Site.map
        end

        get '/map/:id' do
          json Site.map(params[:id])
        end

        get '/location*' do
          path = params[:splat].first
          page = Site[path]
          json Site.map(page.id)
        end

        post '/save/:id' do
          content = Content[params[:id]]
          update_fields(content, params[:field])
        end

        post '/savebox/:id/:box_id' do
          content = Content[params[:id]]
          box = content.boxes[params[:box_id]]
          update_fields(box, params[:field])
        end


        post '/content/:id/position/:position' do
          content = Content[params[:id]]
          content.update_position(params[:position].to_i)
          json( {:message => 'OK'} )
        end


        post '/file/upload/:id' do
          file = params['file']
          media_file = Spontaneous::Media.upload_path(file[:filename])
          FileUtils.mkdir_p(File.dirname(media_file))
          FileUtils.mv(file[:tempfile].path, media_file)
          json({ :id => params[:id], :src => Spontaneous::Media.to_urlpath(media_file), :path => media_file})
        end

        post '/file/replace/:id' do
          content = Content[params[:id]]
          file = params['file']
          field = content.fields[params['field']]
          field.unprocessed_value = file
          content.save
          json({ :id => content.id, :src => field.src})
        end


        post '/file/wrap/:id/:box_id' do
          content = Content[params[:id]]
          box = content.boxes[params[:box_id]]
          file = params['file']
          type = box.type_for_mime_type(file[:type])
          if type
            position = 0
            instance = type.new
            box.insert(position, instance)
            field = instance.field_for_mime_type(file[:type])
            media_file = Spontaneous::Media.upload_path(file[:filename])
            FileUtils.mkdir_p(File.dirname(media_file))
            FileUtils.mv(file[:tempfile].path, media_file)
            field.unprocessed_value = media_file
            content.save
            json({
              :position => position,
              :entry => instance.entry.to_hash
            })
          end
        end

        post '/add/:id/:box_id/:type_name' do
          position = 0
          content = Content[params[:id]]
          box = content.boxes[params[:box_id]]
          type = params[:type_name].constantize

          instance = type.new
          box.insert(position, instance)
          content.save
          json({
            :position => position,
            :entry => instance.entry.to_hash
          })
        end

        post '/destroy/:id' do
          content = Content[params[:id]]
          content.destroy
          json({})
        end

        post '/slug/:id' do
          content = Content[params[:id]]
          if params[:slug].nil? or params[:slug].empty?
            406 # Not Acceptable
          else
            content.slug = params[:slug]
            if content.siblings.detect { |s| s.slug == content.slug }
              409 # Conflict
            else
              content.save
              json({:path => content.path })
            end
          end
        end

        get '/slug/:id/unavailable' do
          content = Content[params[:id]]
          json(content.siblings.map { |c| c.slug })
        end

        get '/static/*' do
          send_file(Spontaneous.static_dir / params[:splat].first)
        end


        get '/js/*' do
          content_type :js
          File.read(Spontaneous.js_dir / params[:splat].first)
        end

        get '/css/*' do
          # need to check for file existing and just send that
          # though production server would handle that I suppose
          file = params[:splat].first
          if file =~ /\.css$/
            less_template = Spontaneous.css_dir / File.basename(file, ".css") + ".less"
            if File.exists?(less_template)
              content_type :css
              Less::Engine.new(File.new(less_template)).to_css
            else
              raise Sinatra::NotFound
            end
          else
            send_file(Spontaneous.css_dir / file)
          end
        end

      end # EditingInterface

      class Preview < Spontaneous::Rack::Public
        HTTP_EXPIRES = "Expires".freeze
        HTTP_CACHE_CONTROL = "Cache-Control".freeze
        HTTP_LAST_MODIFIED = "Last-Modified".freeze
        HTTP_NO_CACHE = "max-age=0, must-revalidate, no-cache, no-store".freeze

        use AroundPreview
        register Authentication

        set :views, Proc.new { Spontaneous.application_dir + '/views' }

        # I don't want this because I'm redirecting everything to /@spontaneous unless
        # we're logged in
        # requires_authentication! :except => ['/', '/favicon.ico']

        # redirect to /@spontaneous unless we're logged in
        before do
          unless user or %r{^/media} === request.path
            redirect NAMESPACE, 302
          end
        end

        get "/favicon.ico" do
          send_file(Spontaneous.static_dir / "favicon.ico")
        end

        def render_page(page, format = :html, local_params = {})
          now = Time.now.to_formatted_s(:rfc822)
          response.headers[HTTP_EXPIRES] = now
          response.headers[HTTP_LAST_MODIFIED] = now
          response.headers[HTTP_CACHE_CONTROL] = HTTP_NO_CACHE
          super
        end
      end # Preview

    end
  end
end

