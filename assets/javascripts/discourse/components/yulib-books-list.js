import Component from "@glimmer/component";
import { service } from "@ember/service";
import { action } from "@ember/object"; // <--- ВАЖНО: Добавь этот импорт

const STATUS_MAP = {
    "id_reading":  { title: "Читаю",     priority: 0 },
    "id_planned":  { title: "Планирую",  priority: 1 },
    "id_done":     { title: "Прочитано", priority: 2 },
    "id_deferred": { title: "Отложено",  priority: 3 }
};

const CARD_THRESHOLD = 5;

export default class YulibBooksList extends Component {
    @service siteSettings;

    // Ссылка на сайт (фоллбэк)
    get appUrl() {
        return "https://yulib.ru/";
    }

    // === НОВЫЙ МЕТОД ДЛЯ КЛИКА ПО КАРТОЧКЕ "БОЛЬШЕ" ===
    @action
    openApp(webUrl, event) {
        // Отменяем стандартный переход по ссылке (чтобы не открылось #)
        if (event) {
            event.preventDefault();
        }

        // 1. Проверка на Android (взято из твоего кода)
        const isAndroid = navigator.userAgent && /Android/i.test(navigator.userAgent);

        if (isAndroid) {
            // === ЛОГИКА ДЛЯ ANDROID ===
            const encodedFallback = encodeURIComponent(webUrl);

            // Формируем Intent.
            // Т.к. это не конкретная книга, используем 'main' или просто открываем схему.
            // Если твое приложение поддерживает yulib://main - сработает идеально.
            // Если нет, Android попробует открыть, и если не выйдет - откроет browser_fallback_url
            const intentUrl = `intent://main#Intent;scheme=yulib;S.browser_fallback_url=${encodedFallback};end`;

            // Перенаправляем в текущем окне (Android сам перехватит)
            window.location.href = intentUrl;
        } else {
            // === ДЛЯ ВСЕХ ОСТАЛЬНЫХ (iOS, PC) ===
            // Открываем сайт в новой вкладке
            window.open(webUrl, '_blank');
        }
    }
    // =================================================

    get groupedBooks() {
        const books = this.args.books;

        if (!books || books.length === 0) {
            return [];
        }

        const limit = this.siteSettings.yulib_max_books_per_status || 30;

        const groups = books.reduce((acc, book) => {
            const statusKey = book.reading_status;
            if (STATUS_MAP[statusKey]) {
                if (!acc[statusKey]) {
                    acc[statusKey] = [];
                }
                acc[statusKey].push(book);
            }
            return acc;
        }, {});

        return Object.keys(groups)
            .map((statusKey) => {
                const config = STATUS_MAP[statusKey];
                const allBooks = groups[statusKey];
                const visibleBooks = allBooks.slice(0, limit);
                const showMoreCard = visibleBooks.length > CARD_THRESHOLD;

                return {
                    statusTitle: config.title,
                    priority: config.priority,
                    books: visibleBooks,
                    showMoreCard: showMoreCard,
                    appUrl: this.appUrl
                };
            })
            .sort((a, b) => a.priority - b.priority);
    }
}