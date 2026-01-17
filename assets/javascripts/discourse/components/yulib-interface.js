import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import I18n from "I18n";
export default class YulibInterface extends Component {
  @service currentUser;

  @tracked codeSent = false;
  @tracked inputCode = "";
  @tracked isLoading = false;
  @tracked errorMessage = null;
  @tracked appEmail = "";

  // Здесь теперь храним весь объект профиля
  @tracked yulibProfile = null;

  @tracked books = [];
  @tracked isLoadingBooks = false; // Отдельный флаг для загрузки книг

  constructor() {
    super(...arguments);
    // Пытаемся достать профиль из загруженного пользователя
    if (this.currentUser && this.currentUser.yulib_profile) {
      this.yulibProfile = this.currentUser.yulib_profile;
      this.appEmail = this.currentUser.email;
      // Если профиль есть — сразу грузим книги
      this.fetchBooks();
    } else {
      this.appEmail = this.currentUser?.email || "";
    }
  }

  get isLinked() {
    return !!this.yulibProfile;
  }

  // --- МЕТОД ЗАГРУЗКИ КНИГ ---
  async fetchBooks() {
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
    this.isLoading = true;
    this.errorMessage = null;
    try {
      await ajax("/yulib/request-code", {
        type: "POST",
        data: {
          app_email: this.appEmail,       // Почта, которую ввел юзер (для кода)
          forum_email: this.currentUser.email // Почта на форуме (на всякий случай)
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
    // 1. Спрашиваем подтверждение (хорошая практика UX)
    if (!confirm(I18n.t("yulib_integration.unlink_confirm"))) {
      return;
    }

    this.isLoading = true;
    this.errorMessage = null;

    try {
      // 2. Отправляем запрос на бэкенд
      await ajax("/yulib/unlink", {
        type: "POST",
        data: { email: this.currentUser.email }
      });

      // 3. Очищаем данные локально (чтобы интерфейс перерисовался)
      this.yulibProfile = null;

      // 4. Очищаем данные в currentUser (чтобы при переходе на другие страницы не "мигало")
      this.currentUser.set("yulib_profile", null);

    } catch (error) {
      this.errorMessage = "Ошибка при отвязке аккаунта";
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  @action
  async verifyCode() {
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

      // 1. Сначала подготавливаем данные
      const profile = result.yulib_profile;

      // Безопасное получение хоста (проверяем наличие siteSettings)
      const host = this.siteSettings?.yulib_avatar_host || "";
      const avatarHost = host.replace(/\/$/, "");

      if (profile && !profile.avatar && profile.uuid) {
        profile.avatar = `${avatarHost}/${profile.uuid}.jpg`;
      }

      // 2. ОБНОВЛЯЕМ ЛОКАЛЬНЫЕ СВОЙСТВА (используем измененный profile!)
      this.yulibProfile = profile;

      // 3. ОБНОВЛЯЕМ ТЕКУЩЕГО ПОЛЬЗОВАТЕЛЯ
      this.currentUser.set("yulib_profile", profile);

      this.codeSent = false;
    } catch (error) {
      // ВЫВОДИМ РЕАЛЬНУЮ ОШИБКУ В КОНСОЛЬ, чтобы не гадать
      console.error("Ошибка в verifyCode:", error);

      if (error.status === 403) {
        this.errorMessage = "Неверный код";
      } else {
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
    this.isLoading = true;
    this.errorMessage = null;

    try {
      // 1. Шлем запрос на наш новый метод
      await ajax("/yulib/enable-push", { type: "POST" });

      // 2. Если успех (не вылетело в catch) - обновляем статус
      this.currentUser.set("yulib_push_enabled", true);

      // Можно показать всплывающее уведомление, что все ок
      // (В Discourse это делается так, если хочешь):
      // const { icon } = require("discourse-common/lib/icon-library");
      // document.querySelector(".d-header").insertAdjacentHTML("afterend", "...");
      // Но у нас и так галочка появится, этого достаточно.

    } catch (error) {
      // 3. Если ошибка (502 или 400)
      this.currentUser.set("yulib_push_enabled", false);

      // Вытаскиваем текст ошибки с сервера, если он есть
      let msg = "Ошибка подключения уведомлений";
      if (error.jqXHR && error.jqXHR.responseJSON && error.jqXHR.responseJSON.error) {
        msg = error.jqXHR.responseJSON.error;
      }

      // Показываем стандартный попап с ошибкой
      popupAjaxError({ message: msg }); // Или просто alert(msg)
    } finally {
      this.isLoading = false;
    }
  }
}
