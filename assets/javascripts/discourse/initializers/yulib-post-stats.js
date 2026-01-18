import {withPluginApi} from "discourse/lib/plugin-api";

export default {
  name: "yulib-stats",

  initialize() {

    document.addEventListener("click", (event) => {
      // Если клик пришелся НЕ на наш элемент (ни на иконку, ни на текст внутри)
      if (!event.target.closest(".y-info-wrapper")) {
        // Находим все открытые тултипы и закрываем их
        document.querySelectorAll(".y-info-wrapper.active").forEach((el) => {
          el.classList.remove("active");
        });
      }
    });

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

        htmlContent += `
                    <div class="y-info-wrapper">
                        <span class="y-info-icon">i</span>
                        <div class="y-info-popup">
                            ${I18n.t("js.yulib_integration.stats_info_tooltip")}
                        </div>
                    </div>
                `;

        // Оборачиваем в контейнер
        elem.insertAdjacentHTML("beforeend", `<div class="yulib-stats-neutral">${htmlContent}</div>`);

        const addedBlock = elem.querySelector(".yulib-stats-neutral .y-info-wrapper");
        if (addedBlock) {
          addedBlock.addEventListener("click", (e) => {
            // ОЧЕНЬ ВАЖНО: stopPropagation запрещает этому клику "всплыть" до document
            // Иначе сработает код выше и сразу же закроет окно обратно
            e.stopPropagation();

            // Если на странице есть ДРУГИЕ открытые тултипы - закроем их
            document.querySelectorAll(".y-info-wrapper.active").forEach((el) => {
              if (el !== addedBlock) el.classList.remove("active");
            });

            // Переключаем текущий
            addedBlock.classList.toggle("active");
          });
        }

      });
    });
  },
};
