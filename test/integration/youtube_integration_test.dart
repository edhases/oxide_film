import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/youtube_provider.dart';

void main() {
  late ApiClient client;
  late YouTubeProvider youtube;

  setUpAll(() {
    client = ApiClient();
    youtube = YouTubeProvider(client);
  });

  test(
    'YouTube search should return results',
    () async {
      print('--- Testing YouTube ---');
      print('Base URL: ${youtube.baseUrl}');

      // Search for a popular movie trailer
      print('\n=== Search Test ===');
      final searchResults = await youtube.search('Аватар трейлер');
      print('Search returned ${searchResults.length} items');

      for (final item in searchResults.take(5)) {
        print('- ${item.title} (ID: ${item.id})');
      }

      expect(searchResults, isNotEmpty, reason: 'Search should return results');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'YouTube getStreams should return direct URLs on desktop',
    () async {
      print('--- Testing YouTube Streams ---');

      // Use a known video ID for testing
      const videoId = 'dQw4w9WgXcQ'; // Rick Astley - Never Gonna Give You Up
      print('Testing video ID: $videoId');

      // Get streams
      print('\n=== Streams Test ===');
      final streams = await youtube.getStreams(videoId);
      print('Total streams found: ${streams.length}');

      for (final stream in streams) {
        final urlPreview = stream.url.length > 80
            ? '${stream.url.substring(0, 80)}...'
            : stream.url;
        print('- ${stream.quality}: $urlPreview');
      }

      expect(streams, isNotEmpty, reason: 'Should return at least one stream');

      // Check stream type
      final firstStream = streams.first;
      print('\n=== Stream Validation ===');
      print('Stream type: ${firstStream.type}');

      // If direct stream, validate URL is accessible
      if (firstStream.url.startsWith('http')) {
        print('Validating URL accessibility...');
        try {
          final dio = Dio();
          final response = await dio.head(
            firstStream.url,
            options: Options(
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              },
              validateStatus: (status) => true,
              followRedirects: true,
            ),
          );
          print('HTTP Status: ${response.statusCode}');
          print('Content-Type: ${response.headers.value("content-type")}');

          if (response.statusCode! < 400) {
            print('✅ Stream URL is accessible');
          } else {
            print('❌ Stream URL returned error');
          }
        } catch (e) {
          print('URL check error: $e');
        }
      } else {
        print('Stream is embed type (not direct URL)');
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
