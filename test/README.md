# Test Guide for Oxide Film

This directory contains unit, widget, and integration test scaffolding and specifications.

Running tests:
- Unit tests: flutter test test/unit
- Widget tests: flutter test test/presentation
- Integration tests (network): set env var `RUN_INTEGRATION=true` and run `flutter test test/integration` or run manual scripts.

Fixtures:
- Place HTML/JSON fixtures in `test/fixtures/` and reference them from specs.

Specs:
- Detailed test specifications live under `test/specs/`.

Helpers:
- `test/helpers/in_memory_db.dart` for in-memory Drift DB
- `test/helpers/mock_services.dart` contains mock classes for common services
- `test/helpers/fake_player.dart` provides a simple player stub for controller tests
- `test/helpers/file_system_mocks.dart` helps stubbing path_provider/file picker

Notes:
- Use `mocktail` for mocks/stubbing; prefer `FakeAsync` to control timers in tests.
- Integration tests that hit real provider endpoints should be gated via `RUN_INTEGRATION=true` and use recorded fixtures when possible.
