// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Opens [url] in a new browser tab.
void openUrl(String url) {
  html.window.open(url, '_blank');
}
