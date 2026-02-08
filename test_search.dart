import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/yummyanime_provider.dart';
import 'package:oxide_film/domain/entities/entities.dart';
import 'dart:io';

void main() async {
  final client = ApiClient();
  final provider = YummyAnimeProvider(client);

  print('Searching for "Иная"...');
  final items = await provider.search('Иная');

  if (items.isEmpty) {
    print('No items found for "Иная"');
    return;
  }

  for (final item in items) {
    print('ID: ${item.id}, Title: ${item.title}');

    print('Fetching details for ${item.id}...');
    try {
      final details = await provider.getDetails(item.id);
      print('Details found: ${details.item.title}');
      print('Seasons: ${details.seasons?.length ?? 0}');
      if (details.seasons != null && details.seasons!.isNotEmpty) {
        print(
          'Episodes in Season 1: ${details.seasons!.first.episodes.length}',
        );
      }

      print('Fetching streams for ${item.id}...');
      final streams = await provider.getStreams(item.id, episodeNum: 1);
      print('Streams: ${streams.length}');
      for (final s in streams) {
        print(
          '  Source: ${s.sourceName}, Quality: ${s.quality.displayName}, URL: ${s.url}',
        );
      }
    } catch (e) {
      print('Error getting details/streams: $e');
    }
    print('---');
  }

  exit(0);
}
