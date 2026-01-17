# frozen_string_literal: true
require "net/https"
require "json"

module ::YulibIntegration
  class Pusher

    # Формируем сообщение и отправляем НА ВСЕ устройства
    def self.push(user, payload)
      message = {
        title: self.get_title(payload),
        message: payload[:excerpt],
        url: "#{Discourse.base_url}/#{payload[:post_url]}"
      }
      self.send_notification(user, message)
    end

    # Сохранение списка токенов (принимаем Array)
    def self.subscribe(user, tokens)
      # Превращаем в массив, убираем дубли и пустые, сохраняем как JSON
      safe_tokens = Array(tokens).flatten.compact.uniq

      return if safe_tokens.empty?

      # Сохраняем в НОВОЕ поле во множественном числе
      user.custom_fields['yulib_push_tokens'] = safe_tokens.to_json
      user.save_custom_fields(true)
      Rails.logger.info "📱 [YuLib] Saved #{safe_tokens.size} tokens for #{user.username}"
    end

    # Полная отписка (удаляем все токены)
    def self.unsubscribe(user)
      user.custom_fields.delete('yulib_push_tokens')
      user.save_custom_fields(true)
    end

    # Приветственный пуш (возвращает true, если ХОТЯ БЫ ОДИН прошел)
    def self.confirm_subscription(user)
      message = {
        title: I18n.t("discourse_fcm_notifications.confirm_title", site_title: SiteSetting.title),
        message: I18n.t("discourse_fcm_notifications.confirm_body"),
        url: "#{Discourse.base_url}"
      }
      return self.send_notification(user, message)
    end

    private

    def self.get_title(payload)
      type = Notification.types[payload[:notification_type]]
      I18n.t(
        "discourse_fcm_notifications.popup.#{type}",
        site_title: SiteSetting.title,
        topic: payload[:topic_title],
        username: payload[:username],
        default: "#{SiteSetting.title}: New notification"
      )
    end

    # Основной метод рассылки
    def self.send_notification(user, message_hash)
      return false unless user && message_hash

      # 1. Проверяем файл ключа
      filename = "yulib_gcp_key.json"
      if !File.exist?(filename) && SiteSetting.yulib_fcm_google_json.present?
        File.open(filename, 'w') { |file| file.write(SiteSetting.yulib_fcm_google_json) }
      end
      return false unless File.exist?(filename)

      # 2. Получаем токены
      raw_tokens = user.custom_fields['yulib_push_tokens']
      return false if raw_tokens.blank?

      # Парсим JSON. Если там старый формат (строка), превращаем в массив
      begin
        tokens_list = JSON.parse(raw_tokens)
      rescue JSON::ParserError
        tokens_list = [raw_tokens] # Обратная совместимость
      end

      tokens_list = Array(tokens_list).compact.uniq
      return false if tokens_list.empty?

      fcm = FCM.new(SiteSetting.yulib_fcm_api_key, filename, SiteSetting.yulib_fcm_project_id)

      success_count = 0
      tokens_to_remove = []

      # 3. ЦИКЛ ПО ВСЕМ ТОКЕНАМ
      tokens_list.each do |token|
        payload = {
          'token': token,
          'data': { "link" => message_hash[:url] },
          'notification': {
            title: message_hash[:title],
            body: message_hash[:message],
          },
          'android': { "priority": "normal" },
          'apns': {
            headers: { "apns-priority": "5" },
            payload: { aps: { "category": "NEW_MESSAGE", "sound": "default" } },
          }
        }

        response = fcm.send_v1(payload)

        if response[:response] == 'success'
          success_count += 1
        else
          # Если токен невалиден (404/400/410), помечаем на удаление
          if [400, 404, 410].include?(response[:status_code])
            tokens_to_remove << token
          else
            Rails.logger.error "❌ [YuLib] FCM Error for user #{user.username}: #{response[:status_code]} - #{response[:body]}"
          end
        end
      end

      # 4. Чистка мертвых токенов
      if tokens_to_remove.any?
        tokens_list -= tokens_to_remove
        if tokens_list.empty?
          self.unsubscribe(user) # Все токены сдохли
        else
          user.custom_fields['yulib_push_tokens'] = tokens_list.to_json
          user.save_custom_fields(true)
        end
        Rails.logger.warn "🧹 [YuLib] Removed #{tokens_to_remove.size} dead tokens for #{user.username}"
      end

      if success_count > 0
        Rails.logger.info "🚀 [YuLib] Push sent to #{success_count} devices for #{user.username}"
        return true
      else
        return false
      end
    end
  end
end