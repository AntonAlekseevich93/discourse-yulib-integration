# name: yulib-integration
# about: External App Integration (Full Profile)
# version: 0.5.0
# authors: YuLib Team

require 'net/http'
require 'uri'

after_initialize do

  # 1. РЕГИСТРИРУЕМ ПОЛЯ В БАЗЕ (Типы данных)
  User.register_custom_field_type('yulib_external_user_id', :integer)
  User.register_custom_field_type('yulib_app_email', :string)
  User.register_custom_field_type('yulib_token', :string)
  User.register_custom_field_type('yulib_app_username', :string)
  User.register_custom_field_type('yulib_user_avatar', :string)
  User.register_custom_field_type('yulib_user_uuid', :string)

  # 2. БЕЛЫЙ СПИСОК ДЛЯ CURRENT USER (Чтобы данные жили после F5)
  # Мы будем отдавать их группой, но на всякий случай разрешим чтение
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_is_linked'
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_profile_data'

  # 3. НАСТРОЙКА СЕРИАЛАЙЗЕРА (Как отдавать данные на фронт)
  # Мы создадим виртуальное поле 'yulib_profile', которое соберет всё в один объект
  add_to_serializer(:current_user, :yulib_profile) do
    if object.custom_fields['yulib_token'].present?
      {
        user_id: object.custom_fields['yulib_external_user_id'],
        email: object.custom_fields['yulib_app_email'],
        token: object.custom_fields['yulib_token'],
        username: object.custom_fields['yulib_app_username'],
        avatar: object.custom_fields['yulib_user_avatar'],
        uuid: object.custom_fields['yulib_user_uuid']
      }
    else
      nil
    end
  end

  module ::YulibIntegration
    class YulibController < ::ApplicationController
      requires_plugin 'yulib-integration'

      skip_before_action :verify_authenticity_token
      skip_before_action :check_xhr


      def request_code
        app_email = params[:app_email]       # Почта приложения (ввел юзер в поле)
        forum_email = current_user.email     # Почта юзера на форуме
        user_id = current_user.id

        if app_email.blank?
          return render json: { error: "Email required" }, status: 400
        end

        # 1. Генерируем код
        code = rand(100000..999999).to_s

        # 2. Сохраняем в Redis Дискорса
        redis_key = "yulib_auth_#{user_id}_#{app_email}"
        Discourse.redis.setex(redis_key, 300, code)

        begin
          # 3. Отправляем всё на бэк
          base_url = SiteSetting.yulib_backend_url.chomp("/")
          uri = URI("#{base_url}/api/request-code")

          # Передаем ТРИ параметра: обе почты и сам код
          response = Net::HTTP.post_form(uri,
                                         'app_email'   => app_email,
                                         'forum_email' => forum_email,
                                         'code'        => code
          )

          if response.is_a?(Net::HTTPSuccess)
            Rails.logger.info "🚀 [YuLib] Code sent to Ktor. App: #{app_email}, Forum: #{forum_email}"
            render json: { success: true }
          else
            Discourse.redis.del(redis_key)
            Rails.logger.error "❌ [YuLib] Backend error: #{response.code} - #{response.body}"
            render json: { success: false, error: "Backend failed" }, status: 502
          end

        rescue => e
          Discourse.redis.del(redis_key)
          Rails.logger.error "❌ [YuLib] Connection error: #{e.message}"
          render json: { success: false, error: "Connection failed" }, status: 502
        end
      end


      def unlink
        # Нам не нужно искать юзера по email из параметров,
        # безопаснее работать с текущим авторизованным пользователем
        user = current_user
        app_email = user.custom_fields['yulib_app_email']
        forum_email = user.email

        if app_email.blank?
          return render json: { error: "No linked account found" }, status: 400
        end

        begin
          # 1. Запрос на Ktor
          base_url = SiteSetting.yulib_backend_url.chomp("/")
          uri = URI("#{base_url}/api/unlink")

          # Передаем обе почты, чтобы бэк знал, кого именно отвязывать
          response = Net::HTTP.post_form(uri,
                                         'app_email'   => app_email,
                                         'forum_email' => forum_email
          )

          if response.is_a?(Net::HTTPSuccess)
            # 2. Если бэк подтвердил (200 OK), чистим поля в Discourse
            user.custom_fields['yulib_external_user_id']      = nil
            user.custom_fields['yulib_app_email']    = nil
            user.custom_fields['yulib_token']        = nil
            user.custom_fields['yulib_app_username'] = nil
            user.custom_fields['yulib_user_avatar']   = nil
            user.custom_fields['yulib_user_uuid']     = nil
            user.save_custom_fields

            Rails.logger.info "🔗 [YuLib] Unlinked: Forum(#{forum_email}) <-> App(#{app_email})"
            render json: { success: true }
          else
            # Если бэк вернул ошибку (например, 403 или 500)
            Rails.logger.error "❌ [YuLib] Backend refused unlink: #{response.code} - #{response.body}"
            render json: {
              success: false,
              error: "Backend refused unlink: #{response.code}"
            }, status: 502
          end

        rescue => e
          Rails.logger.error "❌ [YuLib] Unlink connection failed: #{e.message}"
          render json: { success: false, error: "Connection to backend failed" }, status: 502
        end
      end

      def verify_code
        # --- НАСТРОЙКИ ---
        use_mock = false # Поставь false, чтобы шел запрос на твой бэк
        # -----------------

        app_email = params[:app_email]
        input_code = params[:code]
        user_id = current_user.id
        user = current_user

        # 1. Проверка кода в Redis
        redis_key = "yulib_auth_#{user_id}_#{app_email}"
        stored_code = Discourse.redis.get(redis_key)

        if stored_code.nil? || input_code != stored_code
          return render json: { success: false, error: "Invalid or expired code" }, status: 403
        end

        # 2. ПОЛУЧЕНИЕ ДАННЫХ (БЭК ИЛИ МОК)
        if use_mock
          # --- БЛОК МОКА (НАЧАЛО) ---
          external_data = {
            user_id: 888,
            email: app_email,
            token: "mock-token-#{user_id}",
            username: "MockUser_#{user_id}",
            avatar: "https://avatars.githubusercontent.com/u/3?v=4",
            uuid: "mock-uuid-#{Time.now.to_i}"
          }
        else
          begin
            base_url = SiteSetting.yulib_backend_url.chomp("/")
            uri = URI("#{base_url}/api/verify-user") # Поменяй адрес если надо
            response = Net::HTTP.post_form(uri, 'email' => app_email, 'code' => input_code)

            if response.is_a?(Net::HTTPSuccess)
              data = JSON.parse(response.body)
              external_data = {
                user_id:  data["id"],
                email:    data["email"],
                token:    data["token"],
                username: data["username"],
                avatar:   data["avatar_url"],
                uuid:     data["uuid"]
              }
            else
              return render json: { success: false, error: "Backend returned #{response.code}" }, status: 502
            end
          rescue => e
            Rails.logger.error "❌ [YuLib] API ERROR: #{e.class} - #{e.message}"
            return render json: { success: false, error: "Connection failed: #{e.message}" }, status: 502
          end
        end

        # 3. СОХРАНЕНИЕ В DISCOURSE
        if user && external_data
          user.custom_fields['yulib_external_user_id']      = external_data[:user_id]
          user.custom_fields['yulib_app_email']    = external_data[:email]
          user.custom_fields['yulib_token']        = external_data[:token]
          user.custom_fields['yulib_app_username'] = external_data[:username]
          user.custom_fields['yulib_user_avatar']   = external_data[:avatar]
          user.custom_fields['yulib_user_uuid']     = external_data[:uuid]
          user.save_custom_fields

          Discourse.redis.del(redis_key)

          render json: { success: true, yulib_profile: external_data }
        else
          render json: { success: false, error: "User not found" }, status: 404
        end
      end
    end
  end

  Discourse::Application.routes.prepend do
    post "/yulib/request-code" => "yulib_integration/yulib#request_code"
    post "/yulib/verify-code"  => "yulib_integration/yulib#verify_code"

    # Добавляем маршрут для отвязки
    post "/yulib/unlink"       => "yulib_integration/yulib#unlink"
    # Это говорит Rails: "Для этой ссылки используй контроллер настроек пользователя"
    get "/u/:username/preferences/yulib" => "users#preferences", constraints: { username: /[^\/]+/ }
  end
end
