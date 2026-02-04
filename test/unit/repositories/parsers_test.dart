// Skeleton tests for repositories + parsers behaviors

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Repositories & Parsers (skeleton)', () {
    test(
      'repository.getDetails uses compute wrapper and returns parsed MediaDetails (spec: test/specs/repos/001_getDetails_compute.md)',
      () async {
        // TODO: mock ApiClient.get to return HTML fixture and assert MediaDetails fields
      },
    );

    test(
      'parser robustly handles missing fields without throwing (spec: test/specs/parsers/001_missing_fields.md)',
      () async {
        // TODO: call parser with malformed HTML fixture and assert non-throwing, returns defaults
      },
    );
  });
}
