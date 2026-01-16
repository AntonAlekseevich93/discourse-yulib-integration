import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class YulibInterface extends Component {
  @service currentUser;

  @tracked codeSent = false;
  @tracked inputCode = "";
  @tracked isLoading = false;
  @tracked errorMessage = null;

  // Здесь теперь храним весь объект профиля
  @tracked yulibProfile = null;

  constructor() {
    super(...arguments);
    // Пытаемся достать профиль из загруженного пользователя
    if (this.currentUser && this.currentUser.yulib_profile) {
      this.yulibProfile = this.currentUser.yulib_profile;
    }
  }

  get isLinked() {
    return !!this.yulibProfile;
  }

  @action
  async requestCode() {
    this.isLoading = true;
    this.errorMessage = null;
    try {
      await ajax("/yulib/request-code", { type: "POST", data: { email: this.currentUser.email } });
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
    if (!confirm("Вы уверены, что хотите отвязать аккаунт приложения?")) {
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
        data: { email: this.currentUser.email, code: this.inputCode }
      });

      // Обновляем локально
      this.yulibProfile = result.yulib_profile;

      // Обновляем глобально (для F5) - Ember сам смерджит это
      this.currentUser.set("yulib_profile", result.yulib_profile);

      this.codeSent = false;
    } catch (error) {
      this.errorMessage = "Неверный код";
    } finally {
      this.isLoading = false;
    }
  }

  @action
  reset() {
    this.codeSent = false;
    this.inputCode = "";
  }
}
