// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Returns true when running in a mobile/tablet browser (iOS, Android, iPadOS).
bool isMobileOrTabletBrowser() {
  final ua = html.window.navigator.userAgent.toLowerCase();
  return ua.contains('ipad') ||
      ua.contains('iphone') ||
      ua.contains('android') ||
      ua.contains('mobile') ||
      // iPad on iOS 13+ reports as "macintosh" but has touch support
      (ua.contains('macintosh') &&
          html.window.navigator.maxTouchPoints != null &&
          html.window.navigator.maxTouchPoints! > 0);
}
