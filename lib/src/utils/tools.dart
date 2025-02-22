import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:lolisnatcher/src/data/booru.dart';
import 'package:lolisnatcher/src/data/constants.dart';
import 'package:lolisnatcher/src/handlers/navigation_handler.dart';
import 'package:lolisnatcher/src/widgets/webview/webview_page.dart';

class Tools {
  // code taken from: https://gist.github.com/zzpmaster/ec51afdbbfa5b2bf6ced13374ff891d9
  static String formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(decimals)} ${suffixes[i]}';
  }

  static int boolToInt(bool boolean) {
    return boolean ? 1 : 0;
  }

  static bool intToBool(int boolean) {
    return boolean != 0 ? true : false;
  }

  static bool stringToBool(String boolean) {
    return boolean == "true" ? true : false;
  }

  static String getFileExt(String fileURL) {
    int queryLastIndex = fileURL.lastIndexOf("?"); // if has GET query parameters
    int lastIndex = queryLastIndex != -1 ? queryLastIndex : fileURL.length;
    String fileExt = fileURL.substring(fileURL.lastIndexOf(".") + 1, lastIndex);
    return fileExt;
  }

  static String getFileName(String fileURL) {
    int queryLastIndex = fileURL.lastIndexOf("?"); // if has GET query parameters
    int lastIndex = queryLastIndex != -1 ? queryLastIndex : fileURL.length;
    String fileExt = fileURL.substring(fileURL.lastIndexOf("/") + 1, lastIndex);
    return fileExt;
  }

  static String sanitize(String str, {String replacement = ''}) {
    RegExp illegalRe = RegExp(r'[\/\?<>\\:\*\|"]');
    RegExp controlRe = RegExp(r'[\x00-\x1f\x80-\x9f]');
    RegExp reservedRe = RegExp(r'^\.+$');
    RegExp windowsReservedRe = RegExp(r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\..*)?$', caseSensitive: false);
    RegExp windowsTrailingRe = RegExp(r'[\. ]+$');

    // TODO truncate to 255 symbols for windows?
    return str
        .replaceAll(illegalRe, replacement)
        .replaceAll(controlRe, replacement)
        .replaceAll(reservedRe, replacement)
        .replaceAll(windowsReservedRe, replacement)
        .replaceAll(windowsTrailingRe, replacement)
        .replaceAll("%20", "_");
  }

  // unified http headers list generator for dio in thumb/media/video loaders
  static Future<Map<String, String>> getFileCustomHeaders(
    Booru booru, {
    bool checkForReferer = false,
  }) async {
    // a few boorus don't work without a browser useragent
    Map<String, String> headers = {"User-Agent": browserUserAgent()};
    if(booru.baseURL?.contains("danbooru.donmai.us") ?? false) {
      headers["User-Agent"] = appUserAgent();
    }

    if (!isTestMode) {
      try {
        final cookies = await CookieManager.instance().getCookies(url: Uri.parse(booru.baseURL!));
        if (cookies.isNotEmpty) {
          headers["Cookie"] = cookies.map((e) => "${e.name}=${e.value}").join("; ");
        }
      } catch (e) {
        print('Error getting cookies: $e');
      }
    }

    // some boorus require referer header
    if (checkForReferer) {
      switch (booru.type) {
        case 'World':
          if (booru.baseURL!.contains('rule34.xyz')) {
            headers["Referer"] = "https://rule34xyz.b-cdn.net";
          } else if (booru.baseURL!.contains('rule34.world')) {
            headers["Referer"] = "https://rule34storage.b-cdn.net";
          }
          break;

        default:
          break;
      }
    }

    return headers;
  }

  static IconData getFileIcon(String? mediaType) {
    switch (mediaType) {
      case 'image':
        return Icons.photo;
      case 'video':
        return CupertinoIcons.videocam_fill;
      case 'animation':
        return CupertinoIcons.play_fill;
      case 'not_supported_animation':
        return Icons.play_disabled;
      default:
        return CupertinoIcons.question;
    }
  }

  static void forceClearMemoryCache({bool withLive = false}) {
    // clears memory image cache on timer or when changing tabs
    PaintingBinding.instance.imageCache.clear();
    if (withLive) PaintingBinding.instance.imageCache.clearLiveImages();
  }

  static String pluralize(String str, int count) {
    return count == 1 ? str : '${str}s';
  }

  static bool isGoodStatusCode(int? statusCode) {
    return statusCode != null && statusCode >= 200 && statusCode < 300;
  }

  // TODO move to separate class (something with the name like "Constants")
  static String appUserAgent() => "LoliSnatcher_Droid/${Constants.appVersion}";
  static String browserUserAgent() => "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/111.0";

  static bool get isTestMode => Platform.environment.containsKey('FLUTTER_TEST');

  static Future<bool> checkForCaptcha(Response? response, Uri uri) async {
    if (captchaScreenActive || isTestMode) return false;

    // final RegExp captchaRegex = RegExp(r'captcha', caseSensitive: false);
    // || (response?.data is String && captchaRegex.hasMatch(response?.data as String))
    if (response?.statusCode == 503 || response?.statusCode == 403) {
      captchaScreenActive = true;
      await Navigator.push(
        NavigationHandler.instance.navigatorKey.currentContext!,
        MaterialPageRoute(
          builder: (context) => InAppWebviewView(
            initialUrl: '${uri.scheme}://${uri.host}',
            title: 'Captcha check',
            subtitle: 'Possible captcha detected, please solve it and press back after that. If there is no captcha then it\'s probably some other authentication issue. [Beta]',
          ),
        ),
      );
      captchaScreenActive = false;
      return true;
    }
    return false;
  }

  static Future<String> getCookies(Uri uri) async {
    String cookieString = '';
    if(Platform.isAndroid || Platform.isIOS) {  // TODO add when there is desktop support?
      try {
        final CookieManager cookieManager = CookieManager.instance();
        final List<Cookie> cookies = await cookieManager.getCookies(url: uri);
        for (Cookie cookie in cookies) {
          cookieString += '${cookie.name}=${cookie.value}; ';
        }
      } catch (e) {
        // 
      }
    }

    cookieString = cookieString.trim();

    return cookieString;
  }
}

bool captchaScreenActive = false;
