import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";

export default class YulibCardStats extends Component {
  @tracked showTooltip = false;

  @action
  toggleTooltip(event) {
    event.preventDefault();
    event.stopPropagation();

    this.showTooltip = !this.showTooltip;

    // 💡 Если открыли — вешаем слушатель на закрытие по клику в любом месте
    if (this.showTooltip) {
      const closeMenu = () => {
        this.showTooltip = false;
        document.removeEventListener("click", closeMenu);
      };
      document.addEventListener("click", closeMenu);
    }
  }
}
