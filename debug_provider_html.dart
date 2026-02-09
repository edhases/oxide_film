// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';

void main() async {
  final dio = Dio();
  dio.options.headers['User-Agent'] =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

  print('--- FETCHING UAFLIX ---');
  try {
    final response = await dio.get('https://uaflix.net');
    final soup = BeautifulSoup(response.data);
    final cards = soup.findAll('div', class_: 'video-item');
    if (cards.isEmpty) {
      print(
        'No cards found with class "video-item". Printing first 1000 chars of body:',
      );
      print(soup.body?.text.substring(0, 1000));
    } else {
      print('Found ${cards.length} cards. Dumping first one:');
      print(cards.first.outerHtml);
    }
  } catch (e) {
    print('Error fetching UAFlix: $e');
  }

  print('\n--- FETCHING UASERIALS ---');
  try {
    final response = await dio.get('https://uaserials.pro');
    final soup = BeautifulSoup(response.data);
    final cards = soup.findAll('div', class_: 'short-item');
    if (cards.isEmpty) {
      print(
        'No cards found with class "short-item". Checking for "movie-item"...',
      );
      final cards2 = soup.findAll('div', class_: 'movie-item');
      if (cards2.isNotEmpty) {
        print(
          'Found ${cards2.length} cards with "movie-item". Dumping first one:',
        );
        print(cards2.first.outerHtml);
      } else {
        print('No cards found. Dumping first 1000 chars:');
        print(soup.body?.text.substring(0, 1000));
      }
    } else {
      print('Found ${cards.length} cards. Dumping first one:');
      print(cards.first.outerHtml);
    }
  } catch (e) {
    print('Error fetching UaSerials: $e');
  }
}
