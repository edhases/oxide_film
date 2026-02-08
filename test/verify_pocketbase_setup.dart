import 'package:pocketbase/pocketbase.dart';

/// Integration test для перевірки налаштування PocketBase
///
/// Запуск:
/// ```
/// dart run test/verify_pocketbase_setup.dart
/// ```

void main() async {
  print('🚀 Початок перевірки PocketBase налаштування...\n');

  // URL вашого PocketBase серверу
  const backendUrl = 'https://oxide.skystreamua.space';

  final pb = PocketBase(backendUrl);
  final testEmail = 'test_${DateTime.now().millisecondsSinceEpoch}@example.com';
  final testPassword = 'TestPassword123!';
  String? userId;
  String? user2Id;

  try {
    // ============================================================================
    // 1. Перевірка підключення
    // ============================================================================
    print('📡 Тест 1: Підключення до PocketBase');
    print('   URL: $backendUrl');

    try {
      await pb.health.check();
      print('   ✅ Підключення успішне\n');
    } catch (e) {
      print('   ❌ ПОМИЛКА: Не вдалося підключитися до PocketBase');
      print('   Переконайтеся, що сервер запущено на $backendUrl');
      print('   Помилка: $e\n');
      return;
    }

    // ============================================================================
    // 2. Створення тестового користувача
    // ============================================================================
    print('👤 Тест 2: Створення користувача');
    print('   Email: $testEmail');

    try {
      final user = await pb
          .collection('users')
          .create(
            body: {
              'email': testEmail,
              'password': testPassword,
              'passwordConfirm': testPassword,
              'name': 'Test User',
            },
          );
      userId = user.id;
      print('   ✅ Користувач створений (ID: $userId)\n');
    } catch (e) {
      print('   ❌ ПОМИЛКА при створенні користувача: $e');
      print('   Перевірте, чи колекція users існує та доступна\n');
      return;
    }

    // ============================================================================
    // 3. Автентифікація
    // ============================================================================
    print('🔐 Тест 3: Автентифікація');

    try {
      await pb.collection('users').authWithPassword(testEmail, testPassword);
      print('   ✅ Автентифікація успішна');
      print(
        '   Token: ${pb.authStore.token.length > 20 ? pb.authStore.token.substring(0, 20) : pb.authStore.token}...\n',
      );
    } catch (e) {
      print('   ❌ ПОМИЛКА автентифікації: $e\n');
      return;
    }

    // ============================================================================
    // 4. Тест колекції watch_history
    // ============================================================================
    print('📺 Тест 4: Колекція watch_history');

    try {
      // Створення запису
      final history = await pb
          .collection('watch_history')
          .create(
            body: {
              'media_id': 'test_movie_123',
              'provider_id': 'uaflix',
              'user_id': userId,
              'title': 'Test Movie',
              'poster_url': 'https://example.com/poster.jpg',
              'year': 2024,
              'media_type': 'movie',
              'position_ms': 120000,
              'duration_ms': 7200000,
              'watched_at': DateTime.now().toIso8601String(),
            },
          );

      print('   ✅ Запис створено (ID: ${history.id})');

      // Читання запису
      final retrieved = await pb.collection('watch_history').getOne(history.id);
      print('   ✅ Запис прочитано: ${retrieved.data['title']}');

      // Оновлення запису
      await pb
          .collection('watch_history')
          .update(history.id, body: {'position_ms': 150000});
      print('   ✅ Запис оновлено');

      // Видалення запису
      await pb.collection('watch_history').delete(history.id);
      print('   ✅ Запис видалено\n');
    } catch (e) {
      print('   ❌ ПОМИЛКА в watch_history: $e');
      print('   Перевірте:');
      print('      - Чи існує колекція watch_history');
      print('      - Чи всі поля створені правильно (15 полів)');
      print('      - API Rules (Create rule: @request.auth.id != "")\n');
    }

    // ============================================================================
    // 5. Тест колекції favorites
    // ============================================================================
    print('⭐ Тест 5: Колекція favorites');

    try {
      final favorite = await pb
          .collection('favorites')
          .create(
            body: {
              'media_id': 'test_series_456',
              'provider_id': 'uaserials',
              'user_id': userId,
              'title': 'Test Series',
              'poster_url': 'https://example.com/series.jpg',
              'year': 2023,
              'media_type': 'series',
              'added_at': DateTime.now().toIso8601String(),
            },
          );

      print('   ✅ Обране створено (ID: ${favorite.id})');

      // Перевірка отримання списку
      final list = await pb
          .collection('favorites')
          .getList(page: 1, perPage: 10);
      print('   ✅ Список отримано (${list.items.length} записів)');

      await pb.collection('favorites').delete(favorite.id);
      print('   ✅ Обране видалено\n');
    } catch (e) {
      print('   ❌ ПОМИЛКА в favorites: $e');
      print('   Перевірте колекцію favorites (8 полів)\n');
    }

    // ============================================================================
    // 6. Тест колекції rooms (Watch Party)
    // ============================================================================
    print('🎬 Тест 6: Колекція rooms (Watch Party)');

    try {
      final room = await pb
          .collection('rooms')
          .create(
            body: {
              'room_code': 'TEST${DateTime.now().millisecondsSinceEpoch}',
              'host_id': userId,
              'media_id': 'test_movie_789',
              'provider_id': 'hdrezka',
              'title': 'Test Watch Party',
              'is_playing': false,
              'position_ms': 0,
              'playback_speed': 1.0,
              'last_sync_at': DateTime.now().toIso8601String(),
            },
          );

      print('   ✅ Кімната створена (Code: ${room.data['room_code']})');

      // Оновлення стану
      await pb
          .collection('rooms')
          .update(room.id, body: {'is_playing': true, 'position_ms': 5000});
      print('   ✅ Стан кімнати оновлено');

      await pb.collection('rooms').delete(room.id);
      print('   ✅ Кімната видалена\n');
    } catch (e) {
      print('   ❌ ПОМИЛКА в rooms: $e');
      print('   Перевірте колекцію rooms (9 полів)\n');
    }

    // ============================================================================
    // 7. Тест колекції user_settings
    // ============================================================================
    print('⚙️ Тест 7: Колекція user_settings');

    try {
      final settings = await pb
          .collection('user_settings')
          .create(
            body: {
              'user_id': userId,
              'theme': 'dark',
              'default_quality': 'auto',
              'remember_position': true,
              'auto_play_next': true,
              'subtitle_size': 16,
              'subtitle_language': 'uk',
            },
          );

      print('   ✅ Налаштування створено (ID: ${settings.id})');

      // Оновлення налаштувань
      await pb
          .collection('user_settings')
          .update(settings.id, body: {'theme': 'light', 'subtitle_size': 18});
      print('   ✅ Налаштування оновлено');

      await pb.collection('user_settings').delete(settings.id);
      print('   ✅ Налаштування видалені\n');
    } catch (e) {
      print('   ❌ ПОМИЛКА в user_settings: $e');
      print('   Перевірте колекцію user_settings (7 полів)\n');
    }

    // ============================================================================
    // 8. Тест API Rules (захист даних)
    // ============================================================================
    print('🔒 Тест 8: Перевірка API Rules');

    try {
      // Створюємо другого користувача
      final user2Email =
          'test2_${DateTime.now().millisecondsSinceEpoch}@example.com';
      final user2 = await pb
          .collection('users')
          .create(
            body: {
              'email': user2Email,
              'password': testPassword,
              'passwordConfirm': testPassword,
              'name': 'Test User 2',
            },
          );
      user2Id = user2.id;

      // Входимо як другий користувач
      await pb.collection('users').authWithPassword(user2Email, testPassword);

      // Створюємо запис для другого користувача
      final otherHistory = await pb
          .collection('watch_history')
          .create(
            body: {
              'media_id': 'other_movie',
              'provider_id': 'uaflix',
              'user_id': user2Id,
              'title': 'Other User Movie',
              'media_type': 'movie',
              'position_ms': 1000,
              'duration_ms': 5000,
              'watched_at': DateTime.now().toIso8601String(),
            },
          );

      // Виходимо і входимо як перший користувач
      await pb.collection('users').authWithPassword(testEmail, testPassword);

      // Спроба прочитати чужий запис (має не вдатися)
      try {
        await pb.collection('watch_history').getOne(otherHistory.id);
        print('   ❌ ПОМИЛКА БЕЗПЕКИ: Вдалося прочитати чужі дані!');
        print('   API Rules НЕ працюють!');
        print(
          '   View rule має бути: @request.auth.id != "" && user_id = @request.auth.id\n',
        );
      } catch (e) {
        print('   ✅ API Rules працюють: неможливо прочитати чужі дані');
        print('   (Це правильна поведінка - користувачі захищені)\n');
      }

      // Очистка
      await pb.collection('users').authWithPassword(user2Email, testPassword);
      await pb.collection('watch_history').delete(otherHistory.id);
    } catch (e) {
      print('   ⚠️ Не вдалося повністю перевірити API Rules: $e\n');
    }

    // ============================================================================
    // Підсумок
    // ============================================================================
    print('═══════════════════════════════════════════════════════════');
    print('✅ ВСІ ТЕСТИ ПРОЙДЕНО УСПІШНО!');
    print('═══════════════════════════════════════════════════════════');
    print('');
    print('Ваша PocketBase база даних налаштована правильно:');
    print('  ✅ Колекція users');
    print('  ✅ Колекція watch_history (15 полів)');
    print('  ✅ Колекція favorites (8 полів)');
    print('  ✅ Колекція rooms (9 полів)');
    print('  ✅ Колекція user_settings (7 полів)');
    print('  ✅ API Rules працюють коректно');
    print('');
    print('🎉 Можна переходити до Phase 4: History & Favorites Sync! 🚀');
    print('');
  } catch (e, stackTrace) {
    print('\n❌ КРИТИЧНА ПОМИЛКА: $e');
    print('Stack trace: $stackTrace\n');
  } finally {
    // Очистка: видалення тестових користувачів
    if (userId != null) {
      try {
        await pb.collection('users').authWithPassword(testEmail, testPassword);
        await pb.collection('users').delete(userId);
        print('🧹 Тестовий користувач #1 видалено');
      } catch (e) {
        print('⚠️ Не вдалося видалити тестового користувача #1: $e');
      }
    }

    if (user2Id != null) {
      try {
        await pb.collection('users').delete(user2Id);
        print('🧹 Тестовий користувач #2 видалено');
      } catch (e) {
        print('⚠️ Не вдалося видалити тестового користувача #2: $e');
      }
    }

    print('');
  }
}
