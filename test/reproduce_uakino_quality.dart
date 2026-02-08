import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/data/parsers/uakino_parser.dart';

void main() {
  test('Reproduce UAKino quality detection', () {
    // Mock HTML based on logs and assumptions
    // Log URL example: https://jk39ocmjeoyql3tj.ashdi.vip/content/stream/films/harry_potter_and_the_chamber_of_secrets_2002_2xukr_eng_bdrip_1080p_hurtom_hdclub_by_leroykendall_14/hls/1080/segment3.ts
    // The data-file in DOM probably looks like:
    // https://ashdi.vip/video7/3/films/harry_potter_and_the_chamber_of_secrets_2002_2xukr_eng_bdrip_1080p_hurtom_hdclub_by_leroykendall_14/hls/index.m3u8
    // Or maybe something else that trips it up.

    const html = '''
    <div class="playlists-videos">
      <ul>
        <li data-id="1" data-file="https://ashdi.vip/video7/3/films/harry_potter_and_the_chamber_of_secrets_2002_2xukr_eng_bdrip_1080p_hurtom_hdclub_by_leroykendall_14/hls/index.m3u8" data-voice="1+1">1 серія</li>
        <li data-id="2" data-file="https://ashdi.vip/video7/3/films/harry_potter_and_the_chamber_of_secrets_2002_2xukr_eng_bdrip_1080p_hurtom_hdclub_by_leroykendall_14/hls/index.m3u8" data-voice="1+1">2 серія</li>
      </ul>
    </div>
    ''';

    final sources = UakinoParser.parseAjaxPlaylist(html);
    for (final s in sources) {
      print('URL: ${s.url}');
      print('Quality: ${s.quality}');
      print('Type: ${s.type}');
    }
  });

  test('Check URL quality parsing logic', () {
    final urls = [
      'https://ashdi.vip/video7/3/films/harry_potter_and_the_chamber_of_secrets_2002_2xukr_eng_bdrip_1080p_hurtom_hdclub_by_leroykendall_14/hls/index.m3u8',
      'https://somesite.com/video/480p/index.m3u8',
      'https://somesite.com/video/1080p/index.m3u8',
      'https://ashdi.vip/master.m3u8',
    ];

    // Accessing private method via reflection is hard, so we just copy logic or test via parseAjaxPlaylist
    // But parseAjaxPlaylist calls _parseQualityFromUrl.
    // Let's verify by constructing a simple mock for each URL.

    for (final url in urls) {
      final html =
          '<div class="playlists-videos"><ul><li data-file="$url" data-voice="Dub">1 серія</li></ul></div>';
      final sources = UakinoParser.parseAjaxPlaylist(html);
      if (sources.isNotEmpty) {
        print('URL: $url -> ${sources.first.quality}');
      } else {
        print('URL: $url -> No sources found');
      }
    }
  });
}
