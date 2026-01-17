import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class YulibWidget extends Component {
    @service currentUser;
    @service siteSettings;
    @tracked isLoading = false;
    @tracked errorMessage = null;
    @tracked avatarFailed = false;
    @tracked isCollapsedLocal = false;


    constructor() {
        super(...arguments);

        // 1. ПРОВЕРКА: Что реально пришло с сервера?
        const fromRoot = this.currentUser.yulib_banner_collapsed;
        const fromCustom = this.currentUser.custom_fields?.yulib_banner_collapsed;

        console.log("=== YULIB DEBUG ===");
        console.log("Status from Root:", fromRoot);
        console.log("Status from CustomFields:", fromCustom);

        // 2. Устанавливаем значение.
        // Мы теперь доверяем Root (из add_to_serializer), там точно boolean
        if (fromRoot !== undefined) {
            this.isCollapsedLocal = fromRoot;
        } else {
            // Фолбэк на старый метод (если вдруг сериалайзер не сработал)
            this.isCollapsedLocal = fromCustom === 'true' || fromCustom === true;
        }

        console.log("FINAL Local Status:", this.isCollapsedLocal);
    }

    get settingsUrl() {
        if (!this.currentUser) { return "#"; }
        return `/u/${this.currentUser.username.toLowerCase()}/preferences/yulib`;
    }

    get yulibProfile() {
        const profile = this.currentUser?.yulib_profile;
        if (!profile) { return null; }

        const host = (this.siteSettings.yulib_avatar_host || "").replace(/\/$/, "");

        return {
            ...profile,
            avatar: profile.avatar || (profile.uuid ? `${host}/${profile.uuid}.jpg` : "/images/avatar.png")
        };
    }

    // Геттер для определения состояния (читаем из custom_fields)
    get isCollapsed() {
        return this.currentUser?.custom_fields?.yulib_banner_collapsed === 'true';
    }

    @action
    async toggleBanner() {
        // 1. Мгновенно меняем переключатель визуально
        this.isCollapsedLocal = !this.isCollapsedLocal;
        console.log("Локально переключили на:", this.isCollapsedLocal);

        try {
            // ВАЖНО: Шлем запрос на НАШ СПЕЦИАЛЬНЫЙ МЕТОД, а не на стандартный api пользователя
            // Это и есть тот самый пункт 4
            await ajax("/yulib/toggle-banner", {
                type: "PUT",
                data: {
                    // Просто отправляем true или false
                    state: this.isCollapsedLocal
                }
            });

            console.log("Сервер подтвердил сохранение!");

            // 2. Обновляем локальный кеш юзера (чтобы при переходе по страницам не прыгало)

            // Обновляем в custom_fields (для совместимости)
            if (this.currentUser.custom_fields) {
                this.currentUser.custom_fields.yulib_banner_collapsed = this.isCollapsedLocal.toString();
            }

            // ВАЖНО: Обновляем в корне объекта (так как конструктор читает оттуда)
            this.currentUser.set('yulib_banner_collapsed', this.isCollapsedLocal);

        } catch (e) {
            console.error("ОШИБКА СОХРАНЕНИЯ:", e);
        }
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

    @action
    handleAvatarError(event) {
        this.avatarFailed = true;
        event.target.src = "/images/avatar.png";
    }
}