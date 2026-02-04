import 'package:dio/dio.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';

void main() async {
  final dio = Dio();
  dio.options.headers['User-Agent'] =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

  print('--- FETCHING UAFLIX FILMS ---');
  try {
    // Correct URL for UAFlix films might be /films/
    final response = await dio.get('https://uaflix.net/films/');
    final soup = BeautifulSoup(response.data);
    final cards = soup.findAll('div', class_: 'video-item');
    if (cards.isNotEmpty) {
      print('Found ${cards.length} cards. Dumping first one:');
      print(cards.first.outerHtml);
    } else {
      print('No cards found on /films/');
    }
  } catch (e) {
    print('Error fetching UAFlix: $e');
  }

  print('\n--- FETCHING UASERIALS FILMS ---');
  try {
    final response = await dio.get('https://uaserials.pro/films/');
    final soup = BeautifulSoup(response.data);
    final cards = soup.findAll('div', class_: 'short-item');
    if (cards.isNotEmpty) {
      print('Found ${cards.length} cards. Dumping first one:');
      print(cards.first.outerHtml);
    } else {
      print('No cards found on /films/');
    }
  } catch (e) {
    print('Error fetching UaSerials: $e');
  }
}
