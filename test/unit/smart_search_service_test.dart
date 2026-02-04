// Skeleton tests for SmartSearchService

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartSearchService (skeleton)', () {
    test(
      'search returns empty for blank queries (spec: test/specs/smart_search/001_blank_query.md)',
      () async {
        // TODO: Mock dependencies and assert SmartSearchResult.empty
      },
    );

    test(
      'search emits intermediate and final results and caches final result (spec: test/specs/smart_search/002_streaming_and_cache.md)',
      () async {
        // TODO: use compute isolates stub if necessary and assert caching
      },
    );
  });
}
