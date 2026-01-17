import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DiscourseURL from "discourse/lib/url";

export default class YulibWidget extends Component {
    @service currentUser;
    @service siteSettings;

    @tracked isLoading = false;
    @tracked errorMessage = null;
    @tracked avatarFailed = false;

    // По умолчанию false, что идеально для гостей
    @tracked isCollapsedLocal = false;


    constructor() {
        super(...arguments);

        // Если пользователя нет (гость), мы НЕМЕДЛЕННО выходим.
        // Переменные остаются дефолтными (false), ошибок нет.
        if (!this.currentUser) {
            return;
        }

        // Дальше код выполняется только если this.currentUser существует
        console.log("=== YULIB DEBUG (User exists) ===");

        // Теперь можно обращаться без опаски
        const fromRoot = this.currentUser.yulib_banner_collapsed;

        // Для custom_fields нужна проверка, т.к. само поле может быть null даже у юзера
        const customFields = this.currentUser.custom_fields || {};
        const fromCustom = customFields.yulib_banner_collapsed;

        console.log("Status from Root:", fromRoot);
        console.log("Status from CustomFields:", fromCustom);

        // 2. Устанавливаем значение.
        if (fromRoot !== undefined && fromRoot !== null) {
            this.isCollapsedLocal = fromRoot;
        } else {
            // Фолбэк на старый метод
            this.isCollapsedLocal = fromCustom === 'true' || fromCustom === true;
        }

        console.log("FINAL Local Status:", this.isCollapsedLocal);
    }

    @action
    navigateToSettings(event) {
        if (!this.currentUser) return; // Защита

        // Проверка клика на интерактивные элементы
        if (event.target.closest("button") || event.target.closest(".btn") || event.target.closest(".d-icon")) {
            return;
        }

        DiscourseURL.routeTo(this.settingsUrl);
    }

    get settingsUrl() {
        if (!this.currentUser) { return "#"; }
        return `/u/${this.currentUser.username.toLowerCase()}/preferences/yulib`;
    }

    get yulibProfile() {
        if (!this.currentUser) { return null; }

        const profile = this.currentUser.yulib_profile; // Без ?. так как проверили выше
        if (!profile) { return null; }

        const host = (this.siteSettings.yulib_avatar_host || "").replace(/\/$/, "");

        return {
            ...profile,
            avatar: profile.avatar || (profile.uuid ? `${host}/${profile.uuid}.jpg` : "/images/avatar.png")
        };
    }

    get isCollapsed() {
        if (!this.currentUser) return false;
        // Безопасный доступ к вложенным полям
        return (this.currentUser.custom_fields && this.currentUser.custom_fields.yulib_banner_collapsed === 'true');
    }

    @action
    async toggleBanner() {
        if (!this.currentUser) return;

        this.isCollapsedLocal = !this.isCollapsedLocal;
        console.log("Локально переключили на:", this.isCollapsedLocal);

        try {
            await ajax("/yulib/toggle-banner", {
                type: "PUT",
                data: {
                    state: this.isCollapsedLocal
                }
            });

            console.log("Сервер подтвердил сохранение!");

            // Обновляем custom_fields если они есть
            if (this.currentUser.custom_fields) {
                this.currentUser.custom_fields.yulib_banner_collapsed = this.isCollapsedLocal.toString();
            }

            // Обновляем модель
            this.currentUser.set('yulib_banner_collapsed', this.isCollapsedLocal);

        } catch (e) {
            console.error("ОШИБКА СОХРАНЕНИЯ:", e);
        }
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
    handleAvatarError(event) {
        this.avatarFailed = true;
        event.target.src = "/images/avatar.png";
    }
}