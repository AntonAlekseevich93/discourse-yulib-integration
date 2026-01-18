import { withPluginApi } from "discourse/lib/plugin-api";
import YulibIcon from "../components/yulib-icon"; // Старый компонент для постов (он работает)
import YulibVerifiedBadge from "../components/yulib-verified-badge"; // Для карточки
import I18n from "I18n";

// HTML нашей иконки (синий цвет зашит жестко)
const ICON_HTML = `
  <span class="yulib-profile-badge" title="${I18n.t("yulib_integration.user_verified")}">
    <svg class="fa d-icon svg-icon svg-string" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16">
      <path fill="#0061ff" fill-rule="evenodd" clip-rule="evenodd" d="M14.6563 5.24291C15.4743 5.88358 16 6.8804 16 8C16 9.11964 15.4743 10.1165 14.6562 10.7572C14.7816 11.7886 14.4485 12.8652 13.6568 13.6569C12.8651 14.4486 11.7885 14.7817 10.7571 14.6563C10.1164 15.4743 9.1196 16 8 16C6.88038 16 5.88354 15.4743 5.24288 14.6562C4.21141 14.7817 3.13481 14.4485 2.34312 13.6568C1.55143 12.8652 1.2183 11.7886 1.34372 10.7571C0.525698 10.1164 0 9.1196 0 8C0 6.88038 0.525715 5.88354 1.34376 5.24288C1.21834 4.21141 1.55147 3.13481 2.34316 2.34312C3.13485 1.55143 4.21145 1.2183 5.24291 1.34372C5.88358 0.525698 6.8804 0 8 0C9.11964 0 10.1165 0.525732 10.7572 1.3438C11.7886 1.21838 12.8652 1.55152 13.6569 2.3432C14.4486 3.13488 14.7817 4.21146 14.6563 5.24291ZM12.2071 6.20711L10.7929 4.79289L7 8.58579L5.20711 6.79289L3.79289 8.20711L7 11.4142L12.2071 6.20711Z"/>
    </svg>
  </span>
`;

export default {
    name: "yulib-icon-nuclear",

    initialize() {
        withPluginApi("1.0.0", (api) => {
            // 1. Посты и Карточка (оставляем, раз они работают)
            api.modifyClass("model:post", { pluginId: "yulib", yulib_verified: null });
            api.renderInOutlet("post-meta-data-poster-name-user-link", YulibIcon);
            api.renderInOutlet("user-card-after-username", YulibVerifiedBadge);

            // 2. ПРОФИЛЬ: Глобальный наблюдатель
            api.onPageChange((url) => {
                // Если мы не на странице пользователя, уходим
                if (!url.match(/^\/u\//)) return;

                // Получаем контроллер пользователя, чтобы взять данные
                const userController = api.container.lookup("controller:user");
                if (!userController || !userController.model) return;

                const user = userController.model;

                // ПРОВЕРКА ДАННЫХ В КОНСОЛИ
                console.log("🚀 [YuLib] Profile Check for:", user.username, "Verified:", user.yulib_verified);

                if (user.yulib_verified) {
                    // Запускаем поиск элемента в DOM (с повторами, так как рендер может задерживаться)
                    tryInjectIcon();
                }
            });
        });
    },
};

// Функция-ищейка
function tryInjectIcon(attempts = 0) {
    if (attempts > 20) return; // Сдаемся через 2 секунды

    // Ищем контейнер имени (тот самый div из твоего HTML)
    const nameContainer = document.querySelector(".user-profile-names__primary");

    if (nameContainer) {
        // Проверяем, нет ли уже иконки
        if (!nameContainer.querySelector(".yulib-profile-badge")) {
            nameContainer.insertAdjacentHTML("beforeend", ICON_HTML);
            console.log("✅ [YuLib] Icon injected into DOM!");
        }
    } else {
        // Если элемент еще не отрисовался, ждем 100мс и пробуем снова
        setTimeout(() => tryInjectIcon(attempts + 1), 100);
    }
}
