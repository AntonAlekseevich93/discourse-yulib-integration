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