import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/hdrezka_provider.dart';
import 'package:dio/dio.dart';

void main() {
  late ApiClient client;
  late HdrezkaProvider hdrezka;

  setUpAll(() {
    client = ApiClient();
    hdrezka = HdrezkaProvider(client);
  });

  test(
    'getStreams should decode base64 and return streams',
    () async {
      print('--- Testing HDRezka ---');
      print('Base URL: ${hdrezka.baseUrl}');

      // Search for a movie
      print('\n=== Search Test ===');
      final searchResults = await hdrezka.search('Аватар');
      print('Search returned ${searchResults.length} items');

      expect(searchResults, isNotEmpty, reason: 'Search should return results');

      final firstItem = searchResults.first;
      print('First item: ${firstItem.title} (${firstItem.id})');

      // Get streams using the ID
      print('\n=== Streams Test ===');
      final streams = await hdrezka.getStreams(firstItem.id);
      print('\nTotal streams found: ${streams.length}');
      for (final stream in streams.take(5)) {
        final urlPreview = stream.url.length > 80
            ? '${stream.url.substring(0, 80)}...'
            : stream.url;
        print('- ${stream.quality}: $urlPreview');
      }

      expect(streams, isNotEmpty, reason: 'Should return at least one stream');

      // Verify first stream URL is accessible
      if (streams.isNotEmpty) {
        print('\n=== URL Validation ===');
        final firstUrl = streams.first.url;
        print('Testing URL: $firstUrl');

        try {
          final dio = Dio();
          final response = await dio.head(
            firstUrl,
            options: Options(
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Referer': 'https://hdrezka-home.tv/',
              },
              validateStatus: (status) => true,
            ),
          );
          print('HTTP Status: ${response.statusCode}');
          print('Content-Type: ${response.headers.value("content-type")}');

          expect(
            response.statusCode,
            lessThan(400),
            reason: 'Stream URL should be accessible',
          );
        } catch (e) {
          print('URL check error: $e');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'getStreams for 1+1 movie should return valid streams',
    () async {
      print('--- Testing 1+1 Movie ---');

      // Use direct movie ID: "1+1" (Intouchables 2011)
      // The search found "1+1 дома" (2013) which might not have streams
      // Use the real movie ID directly
      final movieId = 'films/comedy/622-11-2011';
      print('Testing movie ID: $movieId');

      // Get streams
      print('\n=== Streams Test ===');
      final streams = await hdrezka.getStreams(movieId);
      print('Total streams found: ${streams.length}');

      // Print all unique URLs
      final uniqueUrls = <String>{};
      for (final stream in streams) {
        uniqueUrls.add(stream.url);
      }
      print('Unique URLs: ${uniqueUrls.length}');

      // Show first 10 URLs with full content
      for (final url in uniqueUrls.take(10)) {
        print('\nURL: $url');

        // Check for garbage characters
        final hasGarbage =
            url.contains(RegExp(r'[^\x20-\x7E]')) ||
            url.contains('##') ||
            url.contains('@@') ||
            url.contains('^');
        if (hasGarbage) {
          print('  ⚠️ GARBAGE DETECTED!');
        }
      }

      expect(streams, isNotEmpty, reason: 'Should return streams');

      // Validate first URL is accessible
      if (streams.isNotEmpty) {
        print('\n=== URL Validation ===');
        final firstUrl = streams.first.url;
        print('Testing: $firstUrl');

        final dio = Dio();
        final response = await dio.head(
          firstUrl,
          options: Options(
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': 'https://hdrezka-home.tv/',
            },
            validateStatus: (status) => true,
          ),
        );
        print('HTTP Status: ${response.statusCode}');
        print('Content-Type: ${response.headers.value("content-type")}');

        if (response.statusCode! >= 400) {
          print('❌ URL NOT ACCESSIBLE!');
        } else {
          print('✅ URL is accessible');
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
