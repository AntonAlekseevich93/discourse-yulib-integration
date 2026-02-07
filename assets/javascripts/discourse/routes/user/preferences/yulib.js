import Route from "@ember/routing/route";

export default class UserPreferencesYulibRoute extends Route {
  beforeModel() {
    console.log("YuLib: 1. beforeModel fired (Short name worked!)");
  }

  model() {
    console.log("YuLib: 2. Model hook fired");
    return { name: "YuLib Test" };
  }

  setupController(controller, model) {
    super.setupController(...arguments);
    console.log("YuLib: 3. setupController fired");
  }

  // МЫ УБРАЛИ renderTemplate()
  // Пусть Ember сам сделает стандартный рендер.
}
