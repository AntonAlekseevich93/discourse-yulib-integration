# name: yulib-integration
# about: External App Integration (Full Profile)
# version: 0.5.0
# authors: YuLib Team

require 'net/http'
require 'uri'

after_initialize do

  # 1. РЕГИСТРИРУЕМ ПОЛЯ В БАЗЕ (Типы данных)
  User.register_custom_field_type('yulib_user_id', :integer)
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
        user_id: object.custom_fields['yulib_user_id'],
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
        email = params[:email]
        return render json: { error: "Email required" }, status: 400 if email.blank?

        code = rand(100000..999999).to_s
        Discourse.redis.setex("yulib_auth_#{email}", 300, code)
        Rails.logger.info "🚀 [YuLib] Code: #{code} for #{email}"

        render json: { success: true }
      end

      def verify_code
        email = params[:email]
        input_code = params[:code]
        stored_code = Discourse.redis.get("yulib_auth_#{email}")

        if stored_code.nil? || input_code != stored_code
          return render json: { success: false, error: "Invalid or expired code" }, status: 403
        end

        user = User.find_by_email(email)

        if user
          # --- ТУТ ПРИХОДЯТ ДАННЫЕ С ТВОЕГО БЭКА (МОК) ---
          # В реальности ты распарсишь ответ от API
          mock_backend_data = {
            user_id: 777,
            app_email: email,
            token: "eyJhGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.fake-token",
            app_username: "AppMaster_#{rand(100)}",
            user_avatar: "https://avatars.githubusercontent.com/u/1?v=4", # Тестовая картинка
            user_uuid: "550e8400-e29b-41d4-a716-446655440000"
          }

          # Сохраняем каждое поле отдельно в Custom Fields
          user.custom_fields['yulib_user_id'] = mock_backend_data[:user_id]
          user.custom_fields['yulib_app_email'] = mock_backend_data[:app_email]
          user.custom_fields['yulib_token'] = mock_backend_data[:token]
          user.custom_fields['yulib_app_username'] = mock_backend_data[:app_username]
          user.custom_fields['yulib_user_avatar'] = mock_backend_data[:user_avatar]
          user.custom_fields['yulib_user_uuid'] = mock_backend_data[:user_uuid]

          user.save_custom_fields
          Discourse.redis.del("yulib_auth_#{email}")

          # Отдаем сохраненный профиль обратно фронту
          render json: {
            success: true,
            yulib_profile: mock_backend_data
          }
        else
          render json: { success: false, error: "User not found" }, status: 404
        end
      end
    end
  end

  Discourse::Application.routes.prepend do
    post "/yulib/request-code" => "yulib_integration/yulib#request_code"
    post "/yulib/verify-code"  => "yulib_integration/yulib#verify_code"

    # --- ДОБАВЛЯЕМ ВОТ ЭТУ СТРОКУ ---
    # Это говорит Rails: "Для этой ссылки используй контроллер настроек пользователя"
    get "/u/:username/preferences/yulib" => "users#preferences", constraints: { username: /[^\/]+/ }
  end
end
