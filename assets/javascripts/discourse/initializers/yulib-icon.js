import { withPluginApi } from "discourse/lib/plugin-api";
import YulibIcon from "../components/yulib-icon";

export default {
    name: "yulib-icon-final-fix",

    initialize() {
        withPluginApi("1.0.0", (api) => {
            // Регистрируем поле в модели
            api.modifyClass("model:post", {
                pluginId: "yulib-integration",
                yulib_verified: null,
            });

            // Вставляем в розетку-враппер
            api.renderInOutlet("post-meta-data-poster-name-user-link", YulibIcon);

            console.log("🚀 [YuLib] Icon integrated into name-user-link");
        });
    },
};