# name: discourse-yulib-integration
# about: External App Integration (Full Profile)
# version: 0.5.1
# authors: YuLib Team
# url: https://github.com/AntonAlekseevich93/discourse-yulib-integration

enabled_site_setting :yulib_integration_enabled

require 'net/http'
require 'uri'

# --- 1. ЗАВИСИМОСТИ ДЛЯ ПУШЕЙ ---
gem 'signet', '0.17.0'
gem 'os', '1.1.4'
gem 'memoist', '0.16.2'
gem 'googleauth', '1.7.0'
gem 'fcm', '1.0.8'

register_asset 'stylesheets/common/yulib.scss'
register_svg_icon "check"
register_svg_icon "unlink"
register_svg_icon "angle-down"
register_svg_icon "angle-up"
after_initialize do
  Rails.logger.error "❌ ВНИМАНИЕ-1"

  class ::YulibBook < ActiveRecord::Base
    self.table_name = "yulib_books"
    belongs_to :user

    def full_cover_url
      return nil if image_name.blank?

      # 1. Определяем, используем ли маленькие обложки
      use_small = SiteSetting.yulib_use_small_covers

      if use_small
        # Берем хост для маленьких обложек
        host = SiteSetting.yulib_small_cover_books_s3_host

        # Логика замены расширения на .webp (аналог kotlin substringBeforeLast)
        # Если в имени есть точка, берем всё до последней точки, иначе берем всё имя
        base_name = image_name.include?('.') ? image_name.rpartition('.').first : image_name
        final_image_name = "#{base_name}.webp"
      else
        # Берем обычный хост и оставляем оригинальное имя
        host = SiteSetting.yulib_cover_books_s3_host
        final_image_name = image_name
      end

      return final_image_name if host.blank? # Если хост не задан, отдаем только имя

      # 2. Гарантируем, что хост заканчивается на /
      base_url = host.end_with?("/") ? host : "#{host}/"

      # 3. Формируем финальный путь с учетом папки
      if image_folder_id.present?
        "#{base_url}#{image_folder_id}/#{final_image_name}"
      else
        "#{base_url}images/#{final_image_name}"
      end
    end
  end

  add_to_class(:user, :yulib_book_stats) do
    # Ключ кэша уникален для юзера
    cache_key = "yulib_stats_#{self.id}"

    # Пытаемся взять из кэша (живет 12 часов, но мы сбросим его при обновлении)
    Rails.cache.fetch(cache_key, expires_in: 12.hours) do
      ::YulibBook
        .where(user_id: self.id)
        .group(:reading_status)
        .count
    end
  end

  # 2. Добавляем это поле в сериалайзер, чтобы фронтенд его видел
  # Добавляем и в User (профиль) и в Post (для отображения в постах)
  add_to_serializer(:user, :yulib_stats) do
    object.yulib_book_stats
  end

  add_to_serializer(:user_card, :yulib_stats) do
    object.yulib_book_stats
  end
  allow_public_user_custom_field :yulib_stats

  add_to_serializer(:post, :yulib_stats) do
    object.user&.yulib_book_stats
  end

  # 1. РЕГИСТРИРУЕМ ПОЛЯ В БАЗЕ (Типы данных)
  User.register_custom_field_type('yulib_external_user_id', :integer)
  User.register_custom_field_type('yulib_app_email', :string)
  User.register_custom_field_type('yulib_token', :string)
  User.register_custom_field_type('yulib_app_username', :string)
  User.register_custom_field_type('yulib_user_avatar', :string)
  User.register_custom_field_type('yulib_user_uuid', :string)
  User.register_custom_field_type('yulib_last_sync_at', :integer)

  # НОВОЕ ПОЛЕ: Для хранения токена пушей
  User.register_custom_field_type('yulib_push_token', :string)
  # Разрешаем менять его админам (на всякий случай)
  allow_staff_user_custom_field 'yulib_push_token'
  # НОВОЕ ПОЛЕ: Статус подписки (включено/выключено)
  User.register_custom_field_type('yulib_push_enabled', :boolean)
  allow_staff_user_custom_field 'yulib_push_enabled'

  # ==СВЕРНУТОСТЬ БАННЕРА НА ГЛАВНОЙ==
  User.register_custom_field_type('yulib_banner_collapsed', :boolean)
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_banner_collapsed'
  add_to_serializer(:current_user, :yulib_banner_collapsed) do
    # Проверяем и строку 'true', и булево true
    val = object.custom_fields['yulib_banner_collapsed']
    val == 'true' || val == true
  end
  # == END СВЕРНУТОСТЬ БАННЕРА НА ГЛАВНОЙ==

  # 2. БЕЛЫЙ СПИСОК ДЛЯ CURRENT USER (Чтобы данные жили после F5)
  # Мы будем отдавать их группой, но на всякий случай разрешим чтение
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_is_linked'
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_profile_data'
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_external_user_id'
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_app_email'
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_token'
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_app_username'
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_user_avatar'
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_user_uuid'
  DiscoursePluginRegistry.serialized_current_user_fields << 'yulib_push_enabled'
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

  add_to_serializer(:user, :yulib_verified) do
    # Пользователь считается верифицированным, если у него есть токен
    object.custom_fields['yulib_token'].present?
  end

  # Разрешаем передачу этого поля на клиент
  add_to_serializer(:post, :yulib_verified) do
    object.user&.custom_fields&.[]('yulib_token').present?
  end

  add_to_serializer(:user_card, :yulib_verified) do
    object.custom_fields['yulib_token'].present?
  end

  # Чтобы фронтенд знал, включены ли пуши
  add_to_serializer(:user, :yulib_push_enabled) do
    val = object.custom_fields['yulib_push_enabled']
    val == 'true' || val == true
  end

  add_to_serializer(:current_user, :yulib_push_enabled) do
    val = object.custom_fields['yulib_push_enabled']
    val == 'true' || val == true
  end
  # END Чтобы фронтенд знал, включены ли пуши

  # Добавляем коннектор для велком-баннера
  allow_public_user_custom_field :yulib_profile

  # --- 4. ПОДКЛЮЧАЕМ ЛОГИКУ ОТПРАВКИ (Pusher) ---
  # Мы создадим этот файл на следующем шаге
  require_relative 'lib/yulib_pusher'

  DiscourseEvent.on(:push_notification) do |user, payload|
    # Проверяем, есть ли у юзера токен и включены ли пуши в настройках
    if SiteSetting.yulib_fcm_enabled? && user.custom_fields['yulib_push_tokens'].present?
      Rails.logger.info(
        "📣 [YuLib] push_notification user_id=#{user.id} " \
        "username=#{user.username} " \
        "payload_username=#{payload[:username]} " \
        "notification_type=#{payload[:notification_type]} " \
        "topic_id=#{payload[:topic_id]} post_number=#{payload[:post_number]}"
      )
      Jobs.enqueue(:send_yulib_push, user_id: user.id, payload: payload)
    end
  end

  require_dependency 'jobs/base'
  module ::Jobs
    class SendYulibPush < ::Jobs::Base
      def execute(args)
        return unless SiteSetting.yulib_fcm_enabled?
        user = ::User.find_by(id: args[:user_id])
        return unless user

        # Вызываем наш класс отправки
        ::YulibIntegration::Pusher.push(user, args[:payload])
      end
    end
  end

  module ::YulibIntegration
    class YulibController < ::ApplicationController
      requires_plugin 'yulib-integration'

      skip_before_action :verify_authenticity_token
      skip_before_action :check_xhr

      def list_books
        user = current_user
        last_sync = user.custom_fields['yulib_last_sync_at'].to_i

        # Берем интервал из настроек
        sync_interval = get_sync_interval_seconds

        # Проверяем: пора ли обновлять?
        if (Time.now.to_i - last_sync) > sync_interval
          sync_books_from_ktor(user, last_sync)
        end

        books = YulibBook.where(user_id: user.id)

        # Мы проходим по каждой книге и добавляем URL обложки вручную
        books_with_covers = books.map do |book|
          # 1. Берем стандартные поля
          book_hash = book.as_json(only: [
            :book_id, :author_id, :author_name, :book_name, :user_cover_url,
            :page_count, :isbn, :reading_status, :age_restriction, :book_genre_id,
            :image_name, :start_date, :end_date, :timestamp_of_creating,
            :timestamp_of_updating, :external_user_id, :is_visible_for_all_users,
            :description, :image_folder_id, :main_book_id, :publication_year,
            :timestamp_of_reading_done
          ])

          # 2. Добавляем вычисляемую ссылку
          book_hash['full_cover_url'] = book.full_cover_url

          book_hash
        end

        render json: {
          success: true,
          books: books_with_covers
        }
      end

      def toggle_banner
        return render_json_error("Not logged in") unless current_user
        # 1. Приводим к булевому значению (строка 'true' -> true, остальное -> false)
        state = params[:state].to_s == 'true'
        # 2. Пишем в custom_fields
        current_user.custom_fields['yulib_banner_collapsed'] = state
        # 3. Сохраняем. save_custom_fields(true) форсирует запись.
        if current_user.save_custom_fields(true)
          render json: success_json
        else
          render_json_error("Could not save")
        end
      end

      def sync_books_from_ktor(user, last_sync)
        token = user.custom_fields['yulib_token']
        return if token.blank?
        forum_user_email = user.email

        begin
          base_url = SiteSetting.yulib_backend_url.chomp("/")
          uri = URI("#{base_url}/api/books/delta?since=#{last_sync}&forum_email=#{URI.encode_www_form_component(forum_user_email)}")

          req = Net::HTTP::Get.new(uri)
          req['Authorization'] = "Bearer #{token}"

          res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }

          if res.is_a?(Net::HTTPSuccess)
            payload = JSON.parse(res.body)

            # 1. Удаление
            if payload["deleted"].present?
              YulibBook.where(user_id: user.id, book_id: payload["deleted"]).delete_all
            end

            # 2. Обновление (все поля)
            if payload["updated"].present?
              process_book_updates(user.id, payload["updated"])
            end

            # !!! ВАЖНО: Сбрасываем кэш статистики книг пользователя под каждым постом на форуме которая показывается-!!!
            Rails.cache.delete("yulib_stats_#{user.id}")

            user.custom_fields['yulib_last_sync_at'] = Time.now.to_i
            user.save_custom_fields
          end
        rescue => e
          Rails.logger.error "🚀 [YuLib] Sync Error: #{e.message}"
        end
      end

      def process_book_updates(user_id, books_array)
        records = books_array.map do |b|
          {
            user_id: user_id,
            book_id: b["bookId"],
            author_id: b["authorId"],
            author_name: b["authorName"],
            book_name: b["bookName"],
            user_cover_url: b["userCoverUrl"],
            page_count: b["pageCount"],
            isbn: b["Isbn"],
            reading_status: b["readingStatus"],
            age_restriction: b["ageRestriction"],
            book_genre_id: b["bookGenreId"],
            image_name: b["imageName"],
            start_date: b["startDate"],
            end_date: b["endDate"],
            timestamp_of_creating: b["timestampOfCreating"],
            timestamp_of_updating: b["timestampOfUpdating"],
            external_user_id: b["userId"],
            is_visible_for_all_users: b["isVisibleForAllUsers"] || true,
            description: b["description"],
            image_folder_id: b["imageFolderId"],
            main_book_id: b["mainBookId"],
            publication_year: b["publicationYear"],
            timestamp_of_reading_done: b["timestampOfReadingDone"],
            created_at: Time.now,
            updated_at: Time.now
          }
        end

        # Выполняем массовый вставку/обновление по паре (user_id + book_id)
        YulibBook.upsert_all(records, unique_by: [:user_id, :book_id])
      end

      def get_sync_interval_seconds
        setting = SiteSetting.yulib_sync_interval.to_s.downcase
        total_seconds = 0

        # Регулярка ищет числа с h или m (например, 10h, 30m)
        hours = setting.scan(/(\d+)h/).flatten.first.to_i
        minutes = setting.scan(/(\d+)m/).flatten.first.to_i

        total_seconds = (hours * 3600) + (minutes * 60)

        # Если ввели ерунду или 0, сбрасываем на дефолт (24 часа)
        total_seconds > 0 ? total_seconds : 86400
      rescue
        86400 # Дефолт при любой ошибке
      end

      def enable_push
        user = current_user
        auth_token = user.custom_fields['yulib_token']
        forum_email = user.email

        if auth_token.blank?
          return render json: { success: false, error: "Нет токена авторизации." }, status: 400
        end

        # ПОПЫТКА 1: Пробуем отправить на то, что уже есть в базе
        # (Pusher сам возьмет список из yulib_push_tokens)
        if ::YulibIntegration::Pusher.confirm_subscription(user)
          user.custom_fields['yulib_push_enabled'] = true
          user.save_custom_fields
          return render json: { success: true }
        end

        Rails.logger.warn "⚠️ [YuLib] Cached tokens failed. Refreshing from Backend..."

        # ПОПЫТКА 2: Запрашиваем актуальный список у Ktor
        begin
          base_url = SiteSetting.yulib_backend_url.chomp("/")
          uri = URI("#{base_url}/api/get-all-push-tokens")

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{auth_token}" # Авторизация по токену
          request.set_form_data({
                                  "forum_email" => forum_email
                                })

          response = http.request(request)

          if response.is_a?(Net::HTTPSuccess)
            data = JSON.parse(response.body)

            # Ждем массив push_tokens
            new_tokens = data["push_tokens"]

            # Обратная совместимость на всякий случай
            new_tokens = [new_tokens] if new_tokens.is_a?(String)

            if new_tokens.present? && new_tokens.any?
              # Обновляем список в базе
              ::YulibIntegration::Pusher.subscribe(user, new_tokens)

              # Пробуем снова
              if ::YulibIntegration::Pusher.confirm_subscription(user)
                user.custom_fields['yulib_push_enabled'] = true
                user.save_custom_fields
                return render json: { success: true }
              else
                error_msg = "Google не принял ни один из новых токенов."
              end
            else
              error_msg = "Бэкенд вернул пустой список токенов."
            end
          else
            error_msg = response.code == "401" ? "Сессия истекла. Перепривяжитесь." : "Ошибка бэкенда: #{response.code}"
          end
        rescue => e
          error_msg = "Ошибка сети: #{e.message}"
        end

        user.custom_fields['yulib_push_enabled'] = false
        user.save_custom_fields
        render json: { success: false, error: error_msg }, status: 502
      end

      def request_code
        app_email = params[:app_email] # Почта приложения (ввел юзер в поле)
        forum_email = current_user.email # Почта юзера на форуме

        if app_email.blank?
          return render json: { error: "Email required" }, status: 400
        end

        begin
          # 3. Отправляем всё на бэк
          base_url = SiteSetting.yulib_backend_url.chomp("/")
          uri = URI("#{base_url}/api/request-code")

          # Передаем ТРИ параметра: обе почты и сам код
          response = Net::HTTP.post_form(uri,
                                         'app_email' => app_email,
                                         'forum_email' => forum_email
          )

          if response.is_a?(Net::HTTPSuccess)
            Rails.logger.info "🚀 [YuLib] Code sent to Ktor. App: #{app_email}, Forum: #{forum_email}"
            render json: { success: true }
          else
            Rails.logger.error "❌ [YuLib] Backend error: #{response.code} - #{response.body}"
            render json: { success: false, error: "Backend failed" }, status: 502
          end

        rescue => e
          Rails.logger.error "❌ [YuLib] Connection error: #{e.message}"
          render json: { success: false, error: "Connection failed" }, status: 502
        end
      end

      def unlink
        # Нам не нужно искать юзера по email из параметров,
        # безопаснее работать с текущим авторизованным пользователем
        user = current_user
        token = user.custom_fields['yulib_token']
        app_email = user.custom_fields['yulib_app_email']
        forum_email = user.email

        if app_email.blank?
          return render json: { error: "No linked account found" }, status: 400
        end

        begin
          # 1. Запрос на Ktor
          base_url = SiteSetting.yulib_backend_url.chomp("/")
          uri = URI("#{base_url}/api/unlink")

          # --- СЛОЖНЫЙ ЗАПРОС (чтобы передать Header) ---
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = (uri.scheme == "https")

          # Создаем POST запрос
          request = Net::HTTP::Post.new(uri)

          # Добавляем заголовки
          request['Authorization'] = "Bearer #{token}" if token.present?

          # Добавляем данные формы
          request.set_form_data(
            'app_email' => app_email,
            'forum_email' => forum_email
          )

          response = http.request(request)

          if response.is_a?(Net::HTTPSuccess)
            # 2. Если бэк подтвердил (200 OK), чистим поля в Discourse
            # --- УДАЛЕНИЕ КНИГ ---
            # Удаляем все книги, связанные с этим пользователем
            deleted_count = YulibBook.where(user_id: user.id).delete_all
            # !!! ВАЖНО: Сбрасываем кэш статистики книг пользователя под каждым постом на форуме которая показывается-!!!
            Rails.cache.delete("yulib_stats_#{user.id}")
            Rails.logger.info "🗑️ [YuLib] Deleted #{deleted_count} books for user #{user.id}"

            # Удаляем токен пушей
            ::YulibIntegration::Pusher.unsubscribe(user)
            user.custom_fields['yulib_push_enabled'] = false # <--- Выключаем статус
            # --- ОЧИСТКА ПОЛЕЙ ЮЗЕРА ---
            user.custom_fields['yulib_external_user_id'] = nil
            user.custom_fields['yulib_app_email'] = nil
            user.custom_fields['yulib_token'] = nil
            user.custom_fields['yulib_app_username'] = nil
            user.custom_fields['yulib_user_avatar'] = nil
            user.custom_fields['yulib_user_uuid'] = nil

            # Важно: сбрасываем время последней синхронизации,
            # чтобы при новой привязке скачались все данные (since=0)
            user.custom_fields['yulib_last_sync_at'] = nil

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
        forum_email = current_user.email
        forum_user_id = current_user.id
        forum_user_name = current_user.username
        input_code = params[:code]
        user = current_user

        if app_email.blank? || input_code.blank?
          return render json: { success: false, error: "Invalid or expired code" }, status: 403
        end

        # Объявляем переменную заранее, чтобы она была видна в блоке сохранения внизу
        external_data = nil

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
            uri = URI("#{base_url}/api/verify-user")
            # Отправляем только email и код
            response = Net::HTTP.post_form(
              uri,
              'app_email' => app_email,
              'forum_user_id' => forum_user_id,
              'forum_email' => forum_email,
              'forum_user_name' => forum_user_name,
              'code' => input_code
            )

            if response.is_a?(Net::HTTPSuccess)
              data = JSON.parse(response.body)

              # --- ЛОГИКА ПУШЕЙ ---
              # Берем токен СТРОГО из ответа бэкенда
              backend_tokens = data["push_tokens"] # <--- Plural (множественное число)

              # Если бэк прислал по-старому (строку), оборачиваем в массив
              if backend_tokens.is_a?(String)
                backend_tokens = [backend_tokens]
              end

              # 1. Сохраняем список
              if backend_tokens.present? && backend_tokens.any?
                ::YulibIntegration::Pusher.subscribe(user, backend_tokens)

                # Мы просто пробуем отправить,
                # но это НЕ должно влиять на успех авторизации профиля
                send_success = ::YulibIntegration::Pusher.confirm_subscription(user)
                user.custom_fields['yulib_push_enabled'] = send_success

                if send_success
                  Rails.logger.info "✅ [YuLib] Welcome push SENT."
                else
                  Rails.logger.warn "⚠️ [YuLib] Welcome push FAILED, but continuing login..."
                end
              else
                user.custom_fields['yulib_push_enabled'] = false
              end
              # ---END ЛОГИКА ПУШЕЙ ---

              avatar_host = SiteSetting.yulib_avatar_host.chomp("/")
              # avatar_url
              external_data = {
                user_id: data["id"],
                email: data["email"],
                token: data["token"],
                username: data["username"],
                avatar: "#{avatar_host}/#{data["uuid"]}.jpg",
                uuid: data["uuid"]
              }

            else
              # === ВЕТКА ОШИБКИ ===

              # 1. Лечим кодировку для логов (чтобы не было краша ASCII-8BIT)
              error_body = response.body.to_s.force_encoding("UTF-8")
              if !error_body.valid_encoding?
                error_body = error_body.encode("UTF-16be", :invalid => :replace, :replace => "?").encode('UTF-8')
              end

              Rails.logger.error "❌ [YuLib] Backend error: #{response.code} - #{error_body}"

              # 2. Инициализируем NULL.
              # Если останется nil, твой JS сработает по логике статуса (403 -> "Неверный код")
              user_error_msg = nil

              # 3. Пытаемся достать текст. Если бэк прислал JSON с error, JS покажет этот текст.
              begin
                json_resp = JSON.parse(error_body)
                if json_resp['error'].present?
                  user_error_msg = json_resp['error']
                elsif json_resp['message'].present?
                  user_error_msg = json_resp['message']
                end
              rescue
                # Если это просто текст и он не пустой (и не HTML портянка)
                if error_body.present? && error_body.length < 200
                  user_error_msg = error_body
                end
              end

              # 4. БЕРЕМ РЕАЛЬНЫЙ СТАТУС (например, 403)
              frontend_status = response.code.to_i
              # Защита: если статус вдруг успешный (200), но мы в else, ставим 502
              frontend_status = 502 if frontend_status < 400

              # Возвращаем JSON и ВЫХОДИМ (return), чтобы не пытаться сохранить пустые данные
              return render json: { success: false, error: user_error_msg }, status: frontend_status
            end

          rescue => e
            # Лечим кодировку сообщения об ошибке (тоже может крашнуть)
            safe_msg = e.message.to_s.force_encoding("UTF-8")
            if !safe_msg.valid_encoding?
              safe_msg = safe_msg.encode("UTF-16be", :invalid => :replace).encode('UTF-8')
            end

            Rails.logger.error "❌ [YuLib] API ERROR: #{e.class} - #{safe_msg}"
            return render json: { success: false, error: "Connection failed: #{safe_msg}" }, status: 502
          end
        end

        # 3. СОХРАНЕНИЕ В DISCOURSE
        # Сюда мы попадаем ТОЛЬКО если use_mock=true ИЛИ если HTTPSuccess (успешный ответ).
        # При ошибке выше срабатывает return.
        if user && external_data
          user.custom_fields['yulib_external_user_id'] = external_data[:user_id]
          user.custom_fields['yulib_app_email'] = external_data[:email]
          user.custom_fields['yulib_token'] = external_data[:token]
          user.custom_fields['yulib_app_username'] = external_data[:username]
          user.custom_fields['yulib_user_avatar'] = external_data[:avatar]
          user.custom_fields['yulib_user_uuid'] = external_data[:uuid]

          user.save_custom_fields

          # Лог успешной привязки
          Rails.logger.info "✅ [YuLib] User linked: Forum(#{forum_email}) <-> App(#{external_data[:email]})"

          render json: {
            success: true,
            yulib_profile: external_data,
            push_enabled: user.custom_fields['yulib_push_enabled'] == true
          }
        else
          # Сюда можно попасть, если Mock вернул пустоту, или какая-то логическая ошибка
          render json: { success: false, error: "User not found" }, status: 404
        end
      end

    end
  end

  Discourse::Application.routes.prepend do
    post "/yulib/request-code" => "yulib_integration/yulib#request_code"
    post "/yulib/verify-code" => "yulib_integration/yulib#verify_code"
    get "/yulib/books" => "yulib_integration/yulib#list_books"
    # Добавляем маршрут для отвязки
    post "/yulib/unlink" => "yulib_integration/yulib#unlink"
    post "/yulib/enable-push" => "yulib_integration/yulib#enable_push"
    # Это говорит Rails: "Для этой ссылки используй контроллер настроек пользователя"
    get "/u/:username/preferences/yulib" => "users#preferences", constraints: { username: /[^\/]+/ }
    put "/yulib/toggle-banner" => "yulib_integration/yulib#toggle_banner"
  end
end
