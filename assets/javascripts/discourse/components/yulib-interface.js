import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import I18n from "I18n";

export default class YulibInterface extends Component {
  @service currentUser;
  @service siteSettings; // <--- ДОБАВИЛ, иначе verifyCode упадет

  @tracked codeSent = false;
  @tracked inputCode = "";
  @tracked isLoading = false;
  @tracked errorMessage = null;
  @tracked appEmail = "";

  @tracked yulibProfile = null;
  @tracked books = [];
  @tracked isLoadingBooks = false;

  constructor() {
    super(...arguments);

    // 1. БЕЗОПАСНАЯ ПРОВЕРКА (через ?.)
    // Если currentUser = null (гость), код просто пропустит этот блок
    const profile = this.currentUser?.yulib_profile;

    if (profile) {
      this.yulibProfile = profile;
      this.appEmail = this.currentUser.email; // Тут уже безопасно, раз профиль есть
      this.fetchBooks();
    } else {
      // Если юзера нет, ставим пустую строку, чтобы не было undefined
      this.appEmail = this.currentUser?.email || "";
    }
  }

  get isLinked() {
    return !!this.yulibProfile;
  }

  // --- МЕТОД ЗАГРУЗКИ КНИГ ---
  async fetchBooks() {
    // Если мы не залогинены или не привязаны — нет смысла грузить
    if (!this.currentUser || !this.yulibProfile) return;

    this.isLoadingBooks = true;
    try {
      const result = await ajax("/yulib/books");
      if (result.success) {
        this.books = result.books;
      }
    } catch (error) {
      console.error("[YuLib] Failed to load books", error);
    } finally {
      this.isLoadingBooks = false;
    }
  }

  @action
  async requestCode() {
    // Защита от гостей
    if (!this.currentUser) return;

    this.isLoading = true;
    this.errorMessage = null;
    try {
      await ajax("/yulib/request-code", {
        type: "POST",
        data: {
          app_email: this.appEmail,
          forum_email: this.currentUser.email // Теперь безопасно
        }
      });
      this.codeSent = true;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async unlinkProfile() {
    // Защита от гостей
    if (!this.currentUser) return;

    if (!confirm(I18n.t("yulib_integration.unlink_confirm"))) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = null;

    try {
      await ajax("/yulib/unlink", {
        type: "POST",
        data: { email: this.currentUser.email }
      });

      this.yulibProfile = null;
      this.currentUser.set("yulib_profile", null);
      this.books = []; // Очищаем книги при отвязке

    } catch (error) {
      this.errorMessage = "Ошибка при отвязке аккаунта";
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async verifyCode() {
    // Защита от гостей
    if (!this.currentUser) return;

    this.isLoading = true;
    this.errorMessage = null;

    try {
      const result = await ajax("/yulib/verify-code", {
        type: "POST",
        data: {
          app_email: this.appEmail,
          forum_email: this.currentUser.email,
          code: this.inputCode
        }
      });

      const profile = result.yulib_profile;

      // Теперь siteSettings доступен (благодаря инъекции сервиса в начале)
      const host = this.siteSettings.yulib_avatar_host || "";
      const avatarHost = host.replace(/\/$/, "");

      if (profile && !profile.avatar && profile.uuid) {
        profile.avatar = `${avatarHost}/${profile.uuid}.jpg`;
      }

      this.yulibProfile = profile;
      this.currentUser.set("yulib_profile", profile);
      if (result.push_enabled !== undefined) {
        this.currentUser.set("yulib_push_enabled", result.push_enabled);
      }
      this.codeSent = false;

      // Сразу подгружаем книги после успешной привязки!
      this.fetchBooks();

    } catch (error) {
      console.error("Ошибка в verifyCode:", error);

      // --- ИСПРАВЛЕНИЕ: Читаем текст ошибки с сервера ---
      let serverError = null;

      // Пытаемся достать текст из JSON ответа
      if (error.jqXHR && error.jqXHR.responseJSON && error.jqXHR.responseJSON.error) {
        serverError = error.jqXHR.responseJSON.error;
      }

      if (serverError) {
        // Если сервер прислал текст — показываем его
        this.errorMessage = serverError;
      } else if (error.status === 403) {
        // Фолбэк, если JSON не пришел, но статус 403
        this.errorMessage = "Неверный код";
      } else {
        // Фолбэк для остальных ошибок (500, 502 и т.д.)
        this.errorMessage = "Произошла системная ошибка";
      }
    } finally {
      this.isLoading = false;
    }
  }

  @action
  handleAvatarError(event) {
    event.target.src = "/images/avatar.png";
  }

  @action
  reset() {
    this.codeSent = false;
    this.inputCode = "";
  }

  @action
  async enablePush() {
    if (!this.currentUser) return;

    this.isLoading = true;
    this.errorMessage = null;

    try {
      await ajax("/yulib/enable-push", { type: "POST" });
      this.currentUser.set("yulib_push_enabled", true);
    } catch (error) {
      this.currentUser.set("yulib_push_enabled", false);
      let msg = "Ошибка подключения уведомлений";
      if (error.jqXHR && error.jqXHR.responseJSON && error.jqXHR.responseJSON.error) {
        msg = error.jqXHR.responseJSON.error;
      }
      popupAjaxError({ message: msg });
    } finally {
      this.isLoading = false;
    }
  }

  @action
  copyToClipboard(text) {
    if (!text) return;
    navigator.clipboard.writeText(text).then(() => {
      // Если в плагине доступен Toast, он покажет уведомление
      console.log("Copied:", text);
    }).catch(err => {
      console.error("Ошибка копирования:", err);
    });
  }
}
