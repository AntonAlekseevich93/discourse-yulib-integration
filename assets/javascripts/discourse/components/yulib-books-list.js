import Component from "@glimmer/component";

export default class YulibBooksList extends Component {
    // Ember автоматически кладет переданные аргументы в this.args
    // Поэтому обращаемся к книгам через this.args.books

    get groupedBooks() {
        const books = this.args.books;

        if (!books || books.length === 0) {
            return [];
        }

        // Группируем книги по полю reading_status
        const groups = books.reduce((acc, book) => {
            // Если статуса нет, кидаем в "other"
            const status = book.reading_status || "other";

            if (!acc[status]) {
                acc[status] = [];
            }
            acc[status].push(book);
            return acc;
        }, {});

        // Превращаем в массив для отрисовки
        // Сортируем статусы, чтобы 'reading' был выше 'done' (опционально)
        return Object.keys(groups)
            .sort() // Можно убрать или написать свою сортировку
            .map((status) => ({
                statusTitle: this.formatStatus(status), // Для заголовка
                books: groups[status],
            }));
    }

    formatStatus(status) {
        // Делаем первую букву заглавной
        return status.charAt(0).toUpperCase() + status.slice(1);
    }
}