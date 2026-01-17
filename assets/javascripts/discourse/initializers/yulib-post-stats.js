import { withPluginApi } from "discourse/lib/plugin-api";

export default {
    name: "yulib-stats",

    initialize() {
        withPluginApi("1.0.0", (api) => {
            api.decorateCookedElement((elem, helper) => {
                if (!helper) return;

                const post = helper.getModel();
                // Проверяем данные и не дублируем ли мы блок
                if (!post || !post.yulib_stats || elem.querySelector(".yulib-stats-neutral")) return;

                const s = post.yulib_stats;
                // Если все нули - выходим
                if (!s.id_reading && !s.id_planned && !s.id_done) return;

                // Собираем HTML. Просто текст и цифры.
                let htmlContent = "";

                if (s.id_done) {
                    htmlContent += `<span class="y-item">Прочитано: <b>${s.id_done}</b></span>`;
                }
                if (s.id_planned) {
                    htmlContent += `<span class="y-item">В планах: <b>${s.id_planned}</b></span>`;
                }
                // if (s.id_reading) {
                //     htmlContent += `<span class="y-item">Читаю: <b>${s.id_reading}</b></span>`;
                // }

                // Оборачиваем в контейнер
                elem.insertAdjacentHTML("beforeend", `<div class="yulib-stats-neutral">${htmlContent}</div>`);
            });
        });
    },
};