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
        data: {
          app_email: this.appEmail,        // Почта для проверки кода
          forum_email: this.currentUser.email, // Почта форума
          code: this.inputCode             // Сам код
        }
      });

      // Обновляем локально
      this.yulibProfile = result.yulib_profile;

      // Обновляем глобально (для F5) - Ember сам смерджит это
      this.currentUser.set("yulib_profile", result.yulib_profile);

      this.codeSent = false;
    } catch {
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

  @action
  enablePush() {
    alert("Функционал ручного подключения будет добавлен позже. Попробуйте перепривязать аккаунт.");
  }
}
