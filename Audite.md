Стан розробки:

Всі зміни слід впроваджувати поступово, модуль за модулем.

Почніть з "Етапу 1" (Паралелізація та Оптимізація), це дасть видимий результат одразу.

P2P Синхронізація (Watch Party):

Використовуйте бібліотеку peerdart.

Для сигналінгу (з'єднання пірів) можна використати безкоштовний public STUN сервер Google (stun:stun.l.google.com:19302).

Для обміну ID кімнати (SDP offer/answer) достатньо використати простий QR-код або тимчасовий текстовий обмін (месенджери), без необхідності тримати власний WebSocket сервер. Якщо все ж потрібен signaling сервер - використовуйте Supabase Realtime (Free Tier достатньо для тисяч повідомлень).

База даних:

Drift (SQLite) є ідеальним вибором.

Не забудьте додати функцію "Експорт налаштувань та історії", щоб користувач міг перенести дані на інший пристрій вручну (JSON файл).

Безпека:

Не зберігайте жодних API ключів у репозиторії, навіть якщо вони безкоштовні. Використовуйте секрети і гітігнор.


🗺️ Технічна Дорожня Карта та План Рефакторингу Oxide Film

Версія звіту: 2.0 (Фінальна консолідація)
Мета: Перетворення MVP на стабільний, високопродуктивний продукт без залежності від платних сервісів.

1. 🏗️ Цільова Архітектура

Ми переходимо від "Spaghetti Clean Architecture" (де шари перемішані) до Pragmatic Clean Architecture.

Основні принципи:

Local-First: Уся історія, вибране та налаштування зберігаються локально (SQLite/Drift).

No-Backend Dependency: Додаток працює як "розумний браузер". Логіка обробки контенту — на клієнті.

Isolate-Heavy: Усі операції з рядками (HTML parsing, JSON decoding) — тільки в окремих ізолятах.

Нова структура папок (Проєкт):

lib/
├── core/                  # Базові утиліти, DI, константи
├── domain/                # Чиста бізнес-логіка
│   ├── entities/          # Моделі даних (MediaItem)
│   ├── repositories/      # Інтерфейси (IContentRepository)
│   └── parsers/           # Абстракції парсерів
├── data/
│   ├── parsers/           # Реалізація (UakinoParser, EneyidaParser) - ТІЛЬКИ ЛОГІКА
│   ├── clients/           # HTTP клієнти (UakinoClient) - ТІЛЬКИ МЕРЕЖА
│   ├── repositories/      # Агрегація даних
│   └── local/             # БД (Drift)
└── presentation/
    ├── state/             # Cubit/Provider
    ├── widgets/           # Reusable UI components
    └── pages/             # Екрани


2. 🚦 Етап 1: "Швидка допомога" (Тиждень 1-2)

Мета: Прибрати видимі "гальма" та підвищити FPS.

2.1. Паралелізація запитів (HomePage)

Проблема: Послідовне завантаження await provider.get().

Рішення: Переписати home_page.dart на використання Future.wait.

Результат: Завантаження контенту за 1.5–2 секунди замість 8–10.

2.2. Оптимізація зображень

Проблема: Декодування 4K постерів у списки.

Рішення: Додати memCacheHeight: 400 у всі віджети CachedNetworkImage в media_card.dart.

Результат: Зменшення споживання RAM на 60%, плавний скрол.

2.3. Ізоляція плеєра

Проблема: setState на кожну секунду відео перемальовує весь екран.

Рішення: Винести слайдер і таймер у окремий віджет, огорнутий у ValueListenableBuilder.

Результат: Стабільні 60 FPS під час відтворення, менший нагрів телефону.

3. 🛠️ Етап 2: Глибокий Рефакторинг (Тиждень 3-5)

Мета: Зробити код придатним до тестування та легким для підтримки.

3.1. Декомпозиція "God Classes" (Провайдери)

Розділяємо кожен Provider (напр. Uakino) на три частини:

UakinoClient: Відповідає за заголовки, куки, обхід Cloudflare. Повертає "сирий" HTML.

UakinoParser: Чиста функція. Приймає HTML, повертає List<MediaItem>. Жодного Dio/Http тут.

UakinoRepository: Поєднує клієнт і парсер, викликає compute() для парсингу.

3.2. Створення "Aggregation Layer"

UI не повинен знати про Uakino чи Eneyida.

Створити UnifiedContentRepository.

Він приймає список увімкнених провайдерів і робить merge результатів пошуку.

Це місце для логіки дедуплікації (щоб не було двох "Аватарів" у пошуку).

3.3. Прибирання в UI (PlayerPage)

Розбити player_page.dart (1900 рядків) на:

PlayerGestureLayer (обробка та пів/свайпів).

PlayerControlsOverlay (кнопки, слайдери).

PlayerSettingsSheet (вибір якості/озвучки).

4. 📺 Етап 3: UX та Android TV (Тиждень 6+)

Мета: Перетворити мобільний додаток на повноцінний медіа-центр.

4.1. Адаптація під пульт (D-Pad)

Впровадити віджети Focus та Shortcuts.

Додати візуальний стан фокусу (бордер/збільшення) для карток.

Реалізувати навігацію клавішами (вгору/вниз/ліво/право) у плеєрі.

4.2. Розумний пошук (Smart Search)

Debounce: Затримка запиту на 500мс при наборі тексту.

Local History: Підказки з історії пошуку (вже є, але треба оптимізувати через Drift).

4.3. Skeleton Loaders

Замінити "крутилки" на Shimmer-ефект (сірі прямокутники) під час завантаження списків. Це психологічно прискорює додаток.

5. ❌ Політика "Без Backend & Paid Services"

Як ми вирішуємо задачі без сервера:

Задача

Традиційне рішення (Платне/Лімітне)

Наше рішення (Безкоштовне/Local)

Синхронізація перегляду

Firebase / власний сервер

P2P (WebRTC/PeerDart). Пристрої з'єднуються напряму для Watch Party.

Історія / Вибране

Cloud Database

SQLite (Drift) + Експорт/Імпорт JSON файлу (Backup).

Метадані (Постери, Опис)

TMDB API (має ліміти)

Парсинг сторінки донора. Беремо опис і постер прямо з сайту (Uakino/Eneyida). Використовувати TMDB тільки як запасний варіант.

Аналітика помилок

Sentry (Платний для обсягів)

Локальні логи. Запис помилок у файл на пристрої з можливістю відправки розробнику (email/share) за бажанням користувача.

6. План Рефакторингу "Uakino" (Приклад)

Щоб показати, як це працює на практиці.

Зараз (uakino_provider.dart):

Future<List> getMovies() async {
  var html = await dio.get(...); // Мережа
  var list = [];
  // 200 рядків логіки з RegExp прямо тут
  // Обробка помилок тут же
  return list;
}


Буде:

lib/data/parsers/uakino_parser.dart:

class UakinoParser {
  static List<MediaItem> parseCatalog(String html) {
    // Тільки логіка html/regex. Ніякої мережі.
    // Легко покрити Unit-тестами.
  }
}


lib/data/repositories/uakino_repo.dart:

class UakinoRepository {
  Future<List<MediaItem>> getMovies() async {
    final html = await apiClient.get('/movies');
    // ВИКОНУЄТЬСЯ В ОКРЕМОМУ ПОТОЦІ
    return compute(UakinoParser.parseCatalog, html);
  }
}


7. Чек-ліст для розробника

[ ] Встановити lints (правила аналізатора коду) на "strict".

[ ] Налаштувати Git Hooks (pre-commit), щоб не пускати код з помилками.

[ ] Перевірити всі dispose() методи на витік пам'яті (закриття стрімів, контролерів).

[ ] Замінити всі print() на Logger.

Цей план перетворить Oxide Film на професійний, швидкий та незалежний додаток.

⚡ Керівництво по оптимізації продуктивності (Performance Guide)

Цей документ містить конкретні технічні інструкції для реалізації "Етапу 1" дорожньої карти.

1. Паралелізація запитів (HomePage)

Файл: lib/presentation/pages/home/home_page.dart

Проблема

// ❌ Погано: Послідовне очікування
for (var provider in providers) {
  var items = await provider.getPopular(); // Блокує цикл
  list.addAll(items);
}


Рішення

// ✅ Добре: Паралельний запуск
Future<void> _loadContent() async {
  setState(() => _isLoading = true);

  // Створюємо список задач (Future), але не чекаємо їх тут
  final tasks = providers.map((provider) async {
    try {
      return await provider.getPopular();
    } catch (e) {
      Logger.error('Error loading from ${provider.name}', e);
      return <MediaItem>[]; // Повертаємо пустий список при помилці
    }
  });

  // Чекаємо виконання всіх задач одночасно
  final results = await Future.wait(tasks);
  
  // Об'єднуємо результати
  final allItems = results.expand((x) => x).toList();
  
  // Дедуплікація (опціонально)
  final uniqueItems = _removeDuplicates(allItems);

  if (mounted) {
    setState(() {
      _content = uniqueItems;
      _isLoading = false;
    });
  }
}


2. Оптимізація зображень (MediaCard)

Файл: lib/presentation/widgets/media_card.dart

Проблема

Зображення завантажуються у повному розмірі, що призводить до "Jank" (лагів) при скролінгу списків.

Рішення

Використовуйте memCacheHeight або memCacheWidth (але не обидва одночасно, щоб зберегти аспект).

CachedNetworkImage(
  imageUrl: mediaItem.posterUrl,
  // Вказуємо розмір кешу в пікселях пристрою. 
  // 400px зазвичай достатньо для карток у сітці на мобільному.
  memCacheHeight: 400, 
  fit: BoxFit.cover,
  placeholder: (context, url) => const SkeletonWidget(),
  errorWidget: (context, url, error) => const Icon(Icons.error),
)


3. Ізоляція Парсингу (Compute)

Приклад для будь-якого Провайдера

Проблема

Парсинг HTML займає процесорний час в головному потоці (UI Thread).

Рішення

Функція парсингу має бути static або top-level (поза класом), щоб її можна було передати в compute.

// У файлі парсера (напр. uakino_parser.dart)
List<MediaItem> parseUakinoHtml(String html) {
  final document = parse(html);
  // ... логіка парсингу ...
  return items;
}

// У провайдері
Future<List<MediaItem>> getPopular() async {
  final response = await client.get('/popular');
  
  // ✅ Передаємо важку роботу в інший потік
  return compute(parseUakinoHtml, response.body);
}


4. Оптимізація Плеєра (ValueNotifier)

Файл: lib/presentation/pages/player/player_page.dart

Проблема

Використання setState для оновлення прогрес-бару кожну секунду викликає метод build() для всього екрану.

Рішення

Створіть ValueNotifier<Duration> для позиції.

Оновлюйте лише його в слухачі плеєра.

Огорніть слайдер у ValueListenableBuilder.

// У контролері або State
final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);

// У listener плеєра
player.stream.position.listen((pos) {
  positionNotifier.value = pos; // Не викликає setState!
});

// У віджеті (build method)
ValueListenableBuilder<Duration>(
  valueListenable: positionNotifier,
  builder: (context, position, child) {
    return ProgressBar(
      current: position,
      total: duration,
      // ...
    );
  },
);


Приклад Рефакторингу Модуля (Uakino)

Цей файл демонструє, як розбити монолітний провайдер на чисті компоненти.

1. Parser (Чиста логіка)

lib/data/parsers/uakino_parser.dart

import 'package:html/parser.dart';
import 'package:html_unescape/html_unescape.dart';
import '../../domain/entities/media_item.dart';

/// Цей клас не має залежностей від Flutter або Мережі.
/// Його легко тестувати.
class UakinoParser {
  static final _unescape = HtmlUnescape();

  static List<MediaItem> parseCatalog(String htmlString) {
    final document = parse(htmlString);
    final results = <MediaItem>[];

    final elements = document.querySelectorAll('.movie-item');
    
    for (var el in elements) {
      try {
        final title = el.querySelector('.title')?.text.trim() ?? '';
        final link = el.attributes['href'];
        final poster = el.querySelector('img')?.attributes['src'];
        
        if (link != null && title.isNotEmpty) {
           results.add(MediaItem(
             title: _unescape.convert(title),
             url: link,
             posterUrl: _fixPosterUrl(poster),
             source: 'uakino',
           ));
        }
      } catch (e) {
        // Логування помилки конкретного елемента, не ламаючи весь список
        continue;
      }
    }
    return results;
  }

  static String? _fixPosterUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('/')) return '[https://uakino.best](https://uakino.best)$url';
    return url;
  }
}


2. Repository (Робота з даними)

lib/data/repositories/uakino_repository.dart

import 'package:flutter/foundation.dart'; // Для compute
import '../../core/network/api_client.dart';
import '../parsers/uakino_parser.dart';
import '../../domain/entities/media_item.dart';

class UakinoRepository {
  final ApiClient _client;

  UakinoRepository(this._client);

  Future<List<MediaItem>> getPopularMovies() async {
    try {
      final response = await _client.get('/kino/');
      
      // Виконуємо парсинг в ізоляті
      return await compute(UakinoParser.parseCatalog, response.body);
      
    } catch (e) {
      // Обробка мережевих помилок
      throw Exception('Failed to load Uakino movies: $e');
    }
  }
}


3. Provider (Адаптер для додатку)

Цей клас залишається для сумісності з поточним ProviderRegistry, але тепер він дуже тонкий.

lib/data/providers/uakino_provider.dart

class UakinoProvider extends ContentProvider {
  final UakinoRepository _repository;

  UakinoProvider(ApiClient client) : _repository = UakinoRepository(client);

  @override
  String get name => 'Uakino';

  @override
  Future<List<MediaItem>> getPopular() async {
    return _repository.getPopularMovies();
  }
  
  // Інші методи...
}



Покращення UX: Skeleton Loaders

Використовуйте цей код для створення ефекту плавного завантаження замість CircularProgressIndicator.

Skeleton Widget

lib/presentation/widgets/common/skeleton.dart

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class Skeleton extends StatelessWidget {
  final double? height;
  final double? width;
  final double radius;

  const Skeleton({
    super.key, 
    this.height, 
    this.width, 
    this.radius = 8.0
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[700]! : Colors.grey[100]!,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.black, // Колір не важливий через Shimmer
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}


Використання в Grid (Media List)

lib/presentation/widgets/media_grid_skeleton.dart

class MediaGridSkeleton extends StatelessWidget {
  const MediaGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // Адаптуйте під ширину екрану
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 12, // Показуємо 12 "заглушок"
      itemBuilder: (context, index) => const Skeleton(),
    );
  }
}



Адаптація для Android TV (Focus & Shortcuts)

Щоб зробити додаток зручним для керування пультом, кожен інтерактивний елемент (картка фільму) має бути обгорнутий у віджет з підтримкою фокусу.

Focusable Media Card Wrapper

lib/presentation/widgets/tv/focusable_card.dart

import 'package:flutter/material.dart';

class FocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scaleFactor;

  const FocusableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.scaleFactor = 1.05,
  });

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKey: (node, event) {
        // Обробка натискання "Enter" на пульті
        if (event.logicalKey.keyLabel == 'Select' || 
            event.logicalKey.keyLabel == 'Enter') {
             // Викликаємо onTap тільки на UP event, щоб уникнути дублікатів
             // (Або використовуйте Shortcuts/Actions API для чистоти)
             widget.onTap();
             return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: _isFocused ? widget.scaleFactor : 1.0,
          child: Container(
            decoration: _isFocused 
                ? BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ]
                  )
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}



# Цей скрипт допомагає візуалізувати або створити структуру папок для рефакторингу

import os

def create_structure():
    base_dirs = [
        "lib/core/network",
        "lib/core/utils",
        "lib/domain/entities",
        "lib/domain/repositories",
        "lib/domain/parsers",
        "lib/data/parsers",
        "lib/data/repositories",
        "lib/data/clients",
        "lib/data/local/dao",
        "lib/presentation/state",
        "lib/presentation/widgets/tv",
        "lib/presentation/widgets/common",
    ]

    files_to_create = {
        "lib/data/parsers/uakino_parser.dart": "// Pure Dart parsing logic",
        "lib/data/parsers/eneyida_parser.dart": "// Pure Dart parsing logic",
        "lib/data/repositories/unified_content_repository.dart": "// Aggregation logic",
        "lib/presentation/widgets/common/skeleton.dart": "// Shimmer loading widget",
        "lib/presentation/widgets/tv/focusable_card.dart": "// Android TV focus wrapper",
    }

    print("Планована структура папок:")
    for directory in base_dirs:
        print(f"📁 {directory}")
        # os.makedirs(directory, exist_ok=True) # Розкоментуйте для створення

    print("\nПлановані ключові файли:")
    for path, content in files_to_create.items():
        print(f"📄 {path}")
        # with open(path, 'w') as f: f.write(content) # Розкоментуйте для створення

if __name__ == "__main__":
    create_structure()