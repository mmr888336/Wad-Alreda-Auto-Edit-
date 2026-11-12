import 'package:auto_edit/broll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BrollFetcher result ranking', () {
    test('ranks a relevant portrait Pexels result above an irrelevant landscape one', () {
      final ranked = BrollFetcher.rankPexelsVideos(
        [
          {
            'url': 'https://www.pexels.com/video/ocean-waves-123/',
            'width': 3840,
            'height': 2160,
            'duration': 12,
            'video_files': [
              {
                'link': 'https://cdn.example/ocean.mp4',
                'width': 3840,
                'height': 2160,
                'file_type': 'video/mp4',
              },
            ],
          },
          {
            'url': 'https://www.pexels.com/video/phone-product-closeup-456/',
            'width': 1080,
            'height': 1920,
            'duration': 8,
            'video_files': [
              {
                'link': 'https://cdn.example/phone.mp4',
                'width': 1080,
                'height': 1920,
                'file_type': 'video/mp4',
              },
            ],
          },
        ],
        query: 'phone product',
        portrait: true,
      );

      expect(ranked, hasLength(2));
      expect(ranked.first['url'], contains('phone-product'));
    });

    test('uses a high-quality rendition when video dimensions are absent', () {
      final ranked = BrollFetcher.rankPexelsVideos(
        [
          {
            'url': 'https://www.pexels.com/video/city-night-123/',
            'duration': 7,
            'video_files': [
              {
                'link': 'https://cdn.example/city-small.mp4',
                'width': 640,
                'height': 360,
                'file_type': 'video/mp4',
              },
              {
                'link': 'https://cdn.example/city-hd.mp4',
                'width': 1920,
                'height': 1080,
                'file_type': 'video/mp4',
              },
            ],
          },
        ],
        query: 'city night',
        portrait: false,
      );

      expect(ranked, hasLength(1));
      expect(ranked.single['url'], contains('city-night'));
    });

    test('ranks Pixabay tags that match the requested B-roll topic first', () {
      final ranked = BrollFetcher.rankPixabayHits(
        [
          {
            'tags': 'ocean, waves, sea',
            'pageURL': 'https://pixabay.com/videos/ocean-123/',
            'duration': 9,
            'videos': {
              'large': {
                'url': 'https://cdn.example/ocean.mp4',
                'width': 2160,
                'height': 3840,
              },
            },
          },
          {
            'tags': 'solar panel, renewable energy, technology',
            'pageURL': 'https://pixabay.com/videos/solar-panel-456/',
            'duration': 8,
            'videos': {
              'large': {
                'url': 'https://cdn.example/solar.mp4',
                'width': 1080,
                'height': 1920,
              },
            },
          },
        ],
        query: 'solar panel',
        portrait: true,
      );

      expect(ranked, hasLength(2));
      expect(ranked.first['tags'], contains('solar panel'));
    });

    test('discards unsafe and incomplete Pixabay results', () {
      final ranked = BrollFetcher.rankPixabayHits(
        [
          {
            'tags': 'woman, portrait, fashion',
            'pageURL': 'https://pixabay.com/videos/fashion-123/',
            'duration': 8,
            'videos': {
              'large': {
                'url': 'https://cdn.example/fashion.mp4',
                'width': 1080,
                'height': 1920,
              },
            },
          },
          {
            'tags': 'technology, circuit board',
            'pageURL': 'https://pixabay.com/videos/technology-456/',
            'duration': 8,
            'videos': <String, dynamic>{},
          },
        ],
        query: 'technology',
        portrait: true,
      );

      expect(ranked, isEmpty);
    });

    test('preserves Pexels MP4-only file filtering and quality ordering', () {
      final ranked = BrollFetcher.rankPexelsFiles([
        {
          'link': 'https://cdn.example/low.mp4',
          'width': 640,
          'height': 360,
          'file_type': 'video/mp4',
        },
        {
          'link': 'https://cdn.example/high.mp4',
          'width': 1920,
          'height': 1080,
          'file_type': 'video/mp4',
        },
        {
          'link': 'https://cdn.example/image.jpg',
          'width': 4000,
          'height': 3000,
          'file_type': 'image/jpeg',
        },
      ]);

      expect(ranked, hasLength(2));
      expect(ranked.first['link'], contains('high.mp4'));
    });
  });
}
