import Component from "@glimmer/component";

export default class YulibVerifiedBadge extends Component {
    get isVerified() {
        const args = this.args.outletArgs;

        // ЛОГИРОВАНИЕ ДЛЯ ОТЛАДКИ
        // Посмотри в консоль, когда заходишь в профиль.
        // Если видишь "Profile Model", значит компонент жив.
        if (args?.model) {
            console.log("🚀 [YuLib] Profile Model Check:", args.model.yulib_verified, args.model);
        }

        // 1. Профиль (UserSerializer)
        if (args?.model?.yulib_verified) {
            return true;
        }

        // 2. Карточка (UserCardSerializer)
        if (args?.user?.yulib_verified) {
            return true;
        }

        return false;
    }
}