import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' as GET;

import 'package:LoliSnatcher/SettingsHandler.dart';
import 'package:LoliSnatcher/widgets/CustomImageProvider.dart';
import 'package:LoliSnatcher/widgets/DioDownloader.dart';



class CachedFavicon extends StatefulWidget {
  final String faviconURL;
  CachedFavicon(this.faviconURL);

  @override
  _CachedFaviconState createState() => _CachedFaviconState();
}

class _CachedFaviconState extends State<CachedFavicon> {
  final SettingsHandler settingsHandler = GET.Get.find();

  bool isFailed = false;
  CancelToken? _dioCancelToken;
  ImageProvider? faviconProvider;

  @override
  void didUpdateWidget(CachedFavicon oldWidget) {
    // force redraw on tab change
    if(oldWidget.faviconURL != widget.faviconURL) {
      restartLoading();
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> downloadThumb() async {
    _dioCancelToken = CancelToken();
    final DioLoader client = DioLoader(
      widget.faviconURL,
      cancelToken: _dioCancelToken,
      onError: _onError,
      onDone: (Uint8List bytes, String url) {
        if(!isFailed) {
          faviconProvider = getImageProvider(bytes, url);
          updateState();
        }
      },
      cacheEnabled: settingsHandler.imageCache,
      cacheFolder: 'favicons',
      timeoutTime: 2000,
    );
    client.runRequest();
    return;
  }

  ImageProvider getImageProvider(Uint8List bytes, String url) {
    return MemoryImageTest(bytes, imageUrl: url);
  }

  void _onError(Exception error) {
    //// Error handling
    if (error is DioError && CancelToken.isCancel(error)) {
      // print('Canceled by user: $error');
    } else {
      isFailed = true;
      updateState();
      // print('Dio request cancelled: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    downloadThumb();
  }

  void updateState() {
    if(this.mounted) setState(() { });
  }

  void restartLoading() {
    disposables();

    // faviconProvider?.evict();
    faviconProvider = null;
    updateState();

    downloadThumb();
  }

  @override
  void dispose() {
    disposables();
    super.dispose();
  }

  void disposables() {
    faviconProvider?.evict();
    if (!(_dioCancelToken != null && _dioCancelToken!.isCancelled)){
      _dioCancelToken?.cancel();
    }
  }

  Widget loadingElementBuilder(BuildContext ctx) {
    // if (loadingProgress == null && !settingsHandler.imageCache) {
    //   // Resulting image for network loaded thumbnail
    //   return child;
    // }

    if (isFailed) {
      return Center(
        child: InkWell(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image, size: 20),
            ]
          ),
          onTap: () {
            isFailed = false;
            restartLoading();
          },
        )
      );
    } else {
      return const Icon(null); // Center(child: CircularProgressIndicator());
    }
  }

  @override
  Widget build(BuildContext context) {
    const double iconSize = 20;

    return Container(
      width: iconSize,
      height: iconSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if(faviconProvider == null)
            loadingElementBuilder(context),

          AnimatedOpacity(
            opacity: faviconProvider != null ? 1.0 : 0.0,
            duration: Duration(milliseconds: 300),
            child: faviconProvider != null
              ? Image(
                  image: faviconProvider!,
                  width: iconSize,
                  height: iconSize,
                  errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
                    isFailed = true;
                    return loadingElementBuilder(context);
                    // return const Icon(Icons.broken_image, size: iconSize);
                  },
                )
              : null
          ),

          // Image(
          //   image: NetworkImage(widget.faviconURL),
          //   width: iconSize,
          //   height: iconSize,
            // errorBuilder: (BuildContext context, Object exception, StackTrace? stackTrace) {
            //   return const Icon(Icons.broken_image, size: iconSize);
            // },
          // )
        ]
      )
    );
  }
}
