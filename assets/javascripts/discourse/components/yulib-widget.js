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
    @tracked isCollapsedLocal = false;


    constructor() {
        super(...arguments);

        // 1. ПРОВЕРКА: Безопасно получаем данные (добавил ?.)
        // Если currentUser нет (гость), вернется undefined, код не упадет.
        const fromRoot = this.currentUser?.yulib_banner_collapsed;
        const fromCustom = this.currentUser?.custom_fields?.yulib_banner_collapsed;

        console.log("=== YULIB DEBUG ===");
        console.log("Status from Root:", fromRoot);
        console.log("Status from CustomFields:", fromCustom);

        // 2. Устанавливаем значение.
        if (fromRoot !== undefined) {
            this.isCollapsedLocal = fromRoot;
        } else {
            // Фолбэк на старый метод.
            // Если fromCustom undefined (гость), выражение даст false.
            this.isCollapsedLocal = fromCustom === 'true' || fromCustom === true;
        }

        console.log("FINAL Local Status:", this.isCollapsedLocal);
    }

    @action
    navigateToSettings(event) {
        // Если пользователя нет, никуда не идем
        if (!this.currentUser) return;

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
        // Безопасная проверка ?.
        const profile = this.currentUser?.yulib_profile;
        if (!profile) { return null; }

        const host = (this.siteSettings.yulib_avatar_host || "").replace(/\/$/, "");

        return {
            ...profile,
            avatar: profile.avatar || (profile.uuid ? `${host}/${profile.uuid}.jpg` : "/images/avatar.png")
        };
    }

    get isCollapsed() {
        // Безопасная проверка ?.
        return this.currentUser?.custom_fields?.yulib_banner_collapsed === 'true';
    }

    @action
    async toggleBanner() {
        // Защита: гость не может переключать баннер
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

            if (this.currentUser.custom_fields) {
                this.currentUser.custom_fields.yulib_banner_collapsed = this.isCollapsedLocal.toString();
            }

            // Обновляем модель Ember
            this.currentUser.set('yulib_banner_collapsed', this.isCollapsedLocal);

        } catch (e) {
            console.error("ОШИБКА СОХРАНЕНИЯ:", e);
        }
    }

    @action
    async enablePush() {
        // Защита: гость не может включать пуши
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