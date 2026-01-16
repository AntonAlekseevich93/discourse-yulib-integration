import Component from "@glimmer/component";
import { service } from "@ember/service"; // Подключаем сервис

export default class YulibBooksList extends Component {
    @service siteSettings; // Внедряем настройки сайта

    get groupedBooks() {
        const books = this.args.books;

        if (!books || books.length === 0) {
            return [];
        }

        // 1. Получаем лимит из настроек (или 30 по умолчанию, если настройка не пришла)
        const limit = this.siteSettings.yulib_max_books_per_status || 30;

        // 2. Группируем
        const groups = books.reduce((acc, book) => {
            const status = book.reading_status || "other";
            if (!acc[status]) {
                acc[status] = [];
            }
            acc[status].push(book);
            return acc;
        }, {});

        // 3. Формируем массив и ОБРЕЗАЕМ (slice) лишние книги
        return Object.keys(groups)
            .sort()
            .map((status) => ({
                statusTitle: this.formatStatus(status),
                // Вот здесь мы берем только первые N книг
                books: groups[status].slice(0, limit),
            }));
    }

    formatStatus(status) {
        return status.charAt(0).toUpperCase() + status.slice(1);
    }
}