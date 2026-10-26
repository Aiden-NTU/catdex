/// CARTO basemap for the live street. Override at build time with
/// `--dart-define=CATDEX_CARTO_API_KEY=...` so the key is not baked into
/// release binaries you share publicly.
class MapBasemap {
  MapBasemap._();

  static const apiKey = String.fromEnvironment(
    'CATDEX_CARTO_API_KEY',
    defaultValue: 'cb1_4v48_1_3743bc5b91b844c749decf21',
  );

  /// Voyager raster — bright “virtual world” streets (PNG tiles).
  static String get rasterUrlTemplate =>
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png'
      '?key=$apiKey';

  /// Vector style for a future MapLibre mobile path.
  static String get vectorStyleUrl =>
      'https://basemaps.cartocdn.com/gl/voyager-gl-style/style.json'
      '?key=$apiKey';

  static const attribution = '© OpenStreetMap · © CARTO';
}
