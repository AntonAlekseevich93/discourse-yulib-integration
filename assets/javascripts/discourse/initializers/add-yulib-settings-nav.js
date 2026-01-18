import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "add-yulib-settings-nav",

  initialize() {
    // === 1. ЗАГРУЗКА ФАЙЛОВ ===
    let YulibRoute, YulibTemplate;
    let YulibComponent, YulibComponentTemplate;

    // Загружаем Роут и его Шаблон (как делали раньше)
    try {
      YulibRoute =
        require("discourse/plugins/discourse-yulib-integration/discourse/routes/user/preferences/yulib").default;
    } catch (e) {
      console.error("❌ Route JS missing", e);
    }

    try {
      YulibTemplate =
        require("discourse/plugins/discourse-yulib-integration/discourse/templates/user/preferences/yulib").default;
    } catch (e) {
      console.error("❌ Route Template missing", e);
    }

    // Загружаем КОМПОНЕНТ и его Шаблон
    try {
      YulibComponent =
        require("discourse/plugins/discourse-yulib-integration/discourse/components/yulib-interface").default;
      console.log("✅ Component JS loaded");
    } catch (e) {
      console.error("❌ Component JS missing", e);
    }

    try {
      // Шаблоны компонентов лежат в templates/components/
      YulibComponentTemplate =
        require("discourse/plugins/discourse-yulib-integration/discourse/templates/components/yulib-interface").default;
      console.log("✅ Component Template loaded");
    } catch (e) {
      // Иногда путь бывает другим, попробуем альтернативный (без templates)
      try {
        YulibComponentTemplate =
          require("discourse/plugins/discourse-yulib-integration/discourse/components/yulib-interface").default;
      } catch (e2) {
        console.error("❌ Component Template missing", e);
      }
    }

    // ЗАГРУЗКА НОВОГО КОМПОНЕНТА (BOOKS LIST)
    let YulibBooksListComponent, YulibBooksListTemplate;
    try {
      YulibBooksListComponent = require("discourse/plugins/discourse-yulib-integration/discourse/components/yulib-books-list").default;
      YulibBooksListTemplate = require("discourse/plugins/discourse-yulib-integration/discourse/components/yulib-books-list").default; // Ember ищет шаблон там же, если это collocated component, но лучше проверить путь templates/components/...
    } catch (e) {
      // Для шаблона путь может отличаться
      try {
        YulibBooksListTemplate = require("discourse/plugins/discourse-yulib-integration/discourse/templates/components/yulib-books-list").default;
      } catch(e2) { console.error("Books List Template missing"); }
    }
    // КОНЕЦ НОВОГО КОМПОНЕНТА (BOOKS LIST)

    withPluginApi("0.8.7", (api) => {
      const registry = api.container.registry;

      // === 2. РЕГИСТРАЦИЯ РОУТА ===
      if (YulibRoute) {
        registry.register("route:preferences.yulib", YulibRoute); // Короткое имя
        registry.register("route:user/preferences/yulib", YulibRoute); // Длинное имя
      }

      if (YulibTemplate) {
        registry.register("template:preferences.yulib", YulibTemplate);
        registry.register("template:user/preferences/yulib", YulibTemplate);
      }

      // === 3. РЕГИСТРАЦИЯ КОМПОНЕНТА ===
      if (YulibComponent) {
        // Регистрируем класс компонента
        registry.register("component:yulib-interface", YulibComponent);
        console.log("✅ Component registered: component:yulib-interface");
      }

      if (YulibComponentTemplate) {
        // Регистрируем шаблон компонента
        registry.register(
          "template:components/yulib-interface",
          YulibComponentTemplate
        );
        console.log("✅ Component Template registered");
      }

      // === 4. КНОПКА В МЕНЮ ===
      if (api.addUserPreferencesNavItem) {
        api.addUserPreferencesNavItem({
          route: "yulib",
          title: "yulib_integration.menu_title",
        });
      }
    });
  },
};
