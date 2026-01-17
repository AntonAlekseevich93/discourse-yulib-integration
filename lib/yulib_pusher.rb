# frozen_string_literal: true
require "net/https"

module ::YulibIntegration
  class Pusher

    # Формируем сообщение и отправляем
    def self.push(user, payload)
      message = {
        title: self.get_title(payload),
        message: payload[:excerpt],
        url: "#{Discourse.base_url}/#{payload[:post_url]}"
      }
      self.send_notification(user, message)
    end

    # Сохранение токена
    def self.subscribe(user, token)
      return if token.blank?

      if user.custom_fields['yulib_push_token'] != token
        user.custom_fields['yulib_push_token'] = token
        user.save_custom_fields(true)
        Rails.logger.info "📱 [YuLib] New FCM token saved for user #{user.username}"
      end
    end

    # Удаление токена
    def self.unsubscribe(user)
      if user.custom_fields['yulib_push_token'].present?
        user.custom_fields.delete('yulib_push_token')
        user.save_custom_fields(true)
      end
    end

    # --- ВОТ ЭТОТ НОВЫЙ МЕТОД, КОТОРЫЙ МЫ ДОБАВЛЯЛИ ---
    def self.confirm_subscription(user)
      message = {
        title: I18n.t(
          "discourse_fcm_notifications.confirm_title",
          site_title: SiteSetting.title
        ),
        message: I18n.t("discourse_fcm_notifications.confirm_body"),
        url: "#{Discourse.base_url}"
      }
      # Возвращаем результат (true/false)
      return self.send_notification(user, message)
    end
    # --------------------------------------------------

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

    def self.send_notification(user, message_hash)
      return false unless user && message_hash

      filename = "yulib_gcp_key.json"

      if !File.exist?(filename) && SiteSetting.yulib_fcm_google_json.present?
        File.open(filename, 'w') { |file| file.write(SiteSetting.yulib_fcm_google_json) }
      end

      unless File.exist?(filename)
        Rails.logger.warn "⚠️ [YuLib] FCM Error: Missing google json key file"
        return false
      end

      fcm = FCM.new(SiteSetting.yulib_fcm_api_key, filename, SiteSetting.yulib_fcm_project_id)
      token = user.custom_fields['yulib_push_token']

      unless token
        return false
      end

      payload = {
        'token': token,
        'data': {
          "link" => message_hash[:url]
        },
        'notification': {
          title: message_hash[:title],
          body: message_hash[:message],
        },
        'android': {
          "priority": "normal",
        },
        'apns': {
          headers: { "apns-priority": "5" },
          payload: {
            aps: { "category": "NEW_MESSAGE", "sound": "default" }
          },
        }
      }

      response = fcm.send_v1(payload)

      if response[:response] == 'success'
        Rails.logger.info "🚀 [YuLib] Push sent to #{user.username}"
        return true
      else
        if response[:status_code] == 404 || response[:status_code] == 400
          Rails.logger.warn "⚠️ [YuLib] Bad token for #{user.username}, removing..."
          self.unsubscribe(user)
        else
          Rails.logger.error "❌ [YuLib] FCM Error: #{response[:status_code]} - #{response[:body]}"
        end
        return false
      end
    end
  end
end