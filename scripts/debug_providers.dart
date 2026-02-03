import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/yummyanime_provider.dart';
import 'package:oxide_film/core/utils/logger.dart';

void main() async {
  Logger.useConsoleLogs = true;

  final client = ApiClient();
  final yummy = YummyAnimeProvider(client);

  print('--- Testing YummyAnime (yummyanime.club) ---');
  print('Base URL: ${yummy.baseUrl}');

  try {
    final search = await yummy.search('Наруто');
    print('Search returned ${search.length} items');
    for (final item in search.take(3)) {
      print('- ${item.title} (${item.id})');
    }
  } catch (e) {
    print('YummyAnime Error: $e');
  }
}
