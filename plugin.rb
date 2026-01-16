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
        # --- ВОТ ЭТОТ БЛОК ВСТАВИТЬ (ПОЛНОСТЬЮ МЕТОД) ---
        app_email = params[:app_email]       # Почта из инпута
        forum_email = params[:forum_email]   # Почта из системы
        user_id = current_user.id

        return render json: { error: "Email required" }, status: 400 if app_email.blank?

        code = rand(100000..999999).to_s

        # Ключ связывает ID юзера форума и почту приложения
        redis_key = "yulib_auth_#{user_id}_#{app_email}"
        Discourse.redis.setex(redis_key, 300, code)

        # Обновленный лог: теперь ты увидишь обе почты в консоли
        Rails.logger.info "🚀 [YuLib] User ID: #{user_id} | Forum Email: #{forum_email} | Linking to App Email: #{app_email} | Code: #{code}"

        render json: { success: true }
        # --- КОНЕЦ БЛОКА ---
      end

      def unlink
        email = params[:email]
        return render json: { error: "Email required" }, status: 400 if email.blank?

        user = User.find_by_email(email)

        if user
          # Очищаем поля
          user.custom_fields['yulib_user_id'] = nil
          user.custom_fields['yulib_app_email'] = nil
          user.custom_fields['yulib_token'] = nil
          user.custom_fields['yulib_app_username'] = nil
          user.custom_fields['yulib_user_avatar'] = nil
          user.custom_fields['yulib_user_uuid'] = nil

          user.save_custom_fields

          render json: { success: true }
        else
          render json: { success: false, error: "User not found" }, status: 404
        end
      end

      def verify_code
        app_email = params[:app_email]
        input_code = params[:code]
        user_id = current_user.id
        user = current_user

        # 1. Проверяем связку в Redis
        redis_key = "yulib_auth_#{user_id}_#{app_email}"
        stored_code = Discourse.redis.get(redis_key)

        if stored_code.nil? || input_code != stored_code
          return render json: { success: false, error: "Invalid or expired code" }, status: 403
        end

        # 2. Генерируем МОК-ДАННЫЕ (ключи теперь сразу такие, как ждет фронт)
        mock_backend_data = {
          user_id: 888,
          email: app_email,
          token: "eyJhGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.fake-token",
          username: "AppMaster_#{rand(100)}",
          avatar: "https://avatars.githubusercontent.com/u/1?v=4",
          uuid: "550e8400-e29b-41d4-a716-44665544#{user_id}"
        }

        if user
          # 3. Сохраняем каждое поле в базу Discourse (Custom Fields)
          user.custom_fields['yulib_user_id'] = mock_backend_data[:user_id]
          user.custom_fields['yulib_app_email'] = mock_backend_data[:email]
          user.custom_fields['yulib_token'] = mock_backend_data[:token]
          user.custom_fields['yulib_app_username'] = mock_backend_data[:username]
          user.custom_fields['yulib_user_avatar'] = mock_backend_data[:avatar]
          user.custom_fields['yulib_user_uuid'] = mock_backend_data[:uuid]

          user.save_custom_fields

          # 4. Удаляем использованный код
          Discourse.redis.del(redis_key)

          # 5. Отдаем профиль фронту
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

    # Добавляем маршрут для отвязки
    post "/yulib/unlink"       => "yulib_integration/yulib#unlink"
    # Это говорит Rails: "Для этой ссылки используй контроллер настроек пользователя"
    get "/u/:username/preferences/yulib" => "users#preferences", constraints: { username: /[^\/]+/ }
  end
end
