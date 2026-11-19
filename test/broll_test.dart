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

  group('BrollFetcher story context (focus and props)', () {
    Map<String, dynamic> pexelsVideo(String slug) {
      return {
        'url': 'https://www.pexels.com/video/$slug/',
        'width': 1080,
        'height': 1920,
        'duration': 8,
        'video_files': [
          {
            'link': 'https://cdn.example/$slug.mp4',
            'width': 1080,
            'height': 1920,
            'file_type': 'video/mp4',
          },
        ],
      };
    }

    test('contextWords joins the focus and the props, split into words', () {
      final words = BrollFetcher.contextWords(
        focus: 'problem',
        props: <String>['crumpled_paper', 'warning', 'clock'],
      );

      expect(
        words,
        containsAll(<String>['problem', 'crumpled', 'paper', 'warning', 'clock']),
      );
    });

    test('contextWords ignores an unknown focus and an empty context', () {
      expect(BrollFetcher.contextWords(focus: 'none'), isEmpty);
      expect(BrollFetcher.contextWords(), isEmpty);
    });

    test('props of the story beat pick the clip that shows them', () {
      final videos = [
        pexelsVideo('business-growth-forest-456'),
        pexelsVideo('business-growth-coins-123'),
      ];

      final withoutContext = BrollFetcher.rankPexelsVideos(
        videos,
        query: 'business growth',
        portrait: true,
      );
      expect(withoutContext.first['url'], contains('forest'));

      final withContext = BrollFetcher.rankPexelsVideos(
        videos,
        query: 'business growth',
        portrait: true,
        focus: 'money',
        props: <String>['coins', 'chart', 'wallet'],
      );
      expect(withContext.first['url'], contains('coins'));
    });

    test('a focus of none leaves the ranking unchanged', () {
      final videos = [
        pexelsVideo('business-growth-forest-456'),
        pexelsVideo('business-growth-coins-123'),
      ];

      final ranked = BrollFetcher.rankPexelsVideos(
        videos,
        query: 'business growth',
        portrait: true,
        focus: 'none',
      );

      expect(ranked.first['url'], contains('forest'));
    });

    test('the story context never beats a clip that matches the query', () {
      final ranked = BrollFetcher.rankPexelsVideos(
        [
          pexelsVideo('coins-chart-wallet-789'),
          pexelsVideo('phone-product-closeup-456'),
        ],
        query: 'phone product',
        portrait: true,
        focus: 'money',
        props: <String>['coins', 'chart', 'wallet'],
      );

      expect(ranked.first['url'], contains('phone-product'));
    });

    test('Pixabay tags that mention the props rank higher', () {
      Map<String, dynamic> hit(String tags) {
        return {
          'tags': tags,
          'pageURL': 'https://pixabay.com/videos/clip/',
          'duration': 8,
          'videos': {
            'large': {
              'url': 'https://cdn.example/clip.mp4',
              'width': 1080,
              'height': 1920,
            },
          },
        };
      }

      final hits = [hit('success, nature'), hit('success, trophy')];

      final withoutContext = BrollFetcher.rankPixabayHits(
        hits,
        query: 'success',
        portrait: true,
      );
      expect(withoutContext.first['tags'], contains('nature'));

      final withContext = BrollFetcher.rankPixabayHits(
        hits,
        query: 'success',
        portrait: true,
        focus: 'success',
        props: <String>['trophy', 'flag', 'stairs'],
      );
      expect(withContext.first['tags'], contains('trophy'));
    });
  });
}
