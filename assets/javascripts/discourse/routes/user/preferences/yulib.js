import Route from "@ember/routing/route";

export default class UserPreferencesYulibRoute extends Route {
  beforeModel() {
    console.log("📍 YuLib DEBUG: 1. beforeModel fired (Short name worked!)");
  }

  model() {
    console.log("📍 YuLib DEBUG: 2. Model hook fired");
    return { name: "YuLib Test" };
  }

  setupController(controller, model) {
    super.setupController(...arguments);
    console.log("📍 YuLib DEBUG: 3. setupController fired");
  }

  // МЫ УБРАЛИ renderTemplate()
  // Пусть Ember сам сделает стандартный рендер.
}
