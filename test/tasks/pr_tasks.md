# PR Tasks (suggested small PRs)

PR 1 — Test helpers + PlayerController skeleton
- Add: `test/helpers/*` (in_memory_db.dart, mock_services.dart, fake_player.dart, file_system_mocks.dart)
- Add: `test/unit/player/player_controller_test.dart` skeleton
- Add specs for Player tests: `test/specs/player/*`
- Goal: baseline helpers and first PlayerController tests implemented in later PRs.

PR 2 — DAO smoke tests + in-memory DB helper usage
- Add: `test/database/dao_tests/daos_smoke_test.dart` skeleton
- Add specs under `test/specs/dao/*`
- Goal: enable easy DAO unit test implementations.

PR 3 — SyncService & File mocks
- Add: `test/data/sync_service_test.dart`, file_system_mocks, fixtures
- Add specs `test/specs/sync/*`
- Goal: implement export/import tests next.

PR 4 — WatchParty & PlayerPage widget tests
- Add: `test/data/watch_party_service_test.dart`, `test/presentation/pages/player/player_page_test.dart` skeletons
- Add specs `test/specs/watchparty/*` and `test/specs/player/*`
- Goal: start user-oriented interaction tests.

PR 5 — Parsers/Repositories fixtures and tests
- Add: `test/unit/repositories/parsers_test.dart`, fixtures in `test/fixtures/parsers/`
- Add specs `test/specs/repos/*` and `test/specs/parsers/*`

PR 6 — UI widget tests (MediaCard/FocusableCard/RatingBadge)
- Add `test/presentation/widgets/ui_widgets_test.dart` and corresponding specs
- Goal: verify UI behavior and accessibility for TV/Android.

General notes:
- Keep PRs small (5-10 tests each) for quick review.
- Mark integration tests with env flag RUN_INTEGRATION=true.
