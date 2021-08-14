import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:typed_data';

import 'package:LoliSnatcher/ViewUtils.dart';
import 'package:LoliSnatcher/widgets/CachedThumb.dart';
import 'package:LoliSnatcher/widgets/CachedThumbBetter.dart';
import 'package:LoliSnatcher/widgets/CustomImageProvider.dart';
import 'package:LoliSnatcher/widgets/DioDownloader.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' as GET;
import 'package:photo_view/photo_view.dart';
import 'package:dio/dio.dart';

import 'package:LoliSnatcher/SettingsHandler.dart';
import 'package:LoliSnatcher/SearchGlobals.dart';
import 'package:LoliSnatcher/Tools.dart';
import 'package:LoliSnatcher/libBooru/BooruItem.dart';
import 'package:LoliSnatcher/widgets/BorderedText.dart';

class MediaViewerBetter extends StatefulWidget {
  final BooruItem booruItem;
  final int index;
  final SearchGlobal searchGlobal;
  MediaViewerBetter(this.booruItem, this.index, this.searchGlobal);

  @override
  _MediaViewerBetterState createState() => _MediaViewerBetterState();
}

class _MediaViewerBetterState extends State<MediaViewerBetter> {
  final SettingsHandler settingsHandler = GET.Get.find<SettingsHandler>();
  final SearchHandler searchHandler = GET.Get.find<SearchHandler>();

  PhotoViewScaleStateController scaleController = PhotoViewScaleStateController();
  PhotoViewController viewController = PhotoViewController();
  StreamSubscription<bool>? appbarListener;

  int _total = 0, _received = 0;
  int _prevReceivedAmount = 0, _lastReceivedAmount = 0, _lastReceivedTime = 0, _startedAt = 0;
  Timer? _checkInterval, _debounceBytes;
  bool isFromCache = false, isStopped = false, isZoomed = false, isZoomButtonVisible = true;
  List<String> stopReason = [];

  ImageProvider? mainProvider;
  late String imageURL;
  late String imageFolder;
  CancelToken _dioCancelToken = CancelToken();

  @override
  void didUpdateWidget(MediaViewerBetter oldWidget) {
    // force redraw on tab change
    if(oldWidget.booruItem != widget.booruItem) {
      killLoading([]);
      initViewer(false);
    }
    super.didUpdateWidget(oldWidget);
  }

  /// Author: [Nani-Sore] ///
  Future<void> _downloadImage() async {
    _dioCancelToken = CancelToken();
    final DioLoader client = DioLoader(
      imageURL,
      headers: ViewUtils.getFileCustomHeaders(widget.searchGlobal, checkForReferer: true),
      cancelToken: _dioCancelToken,
      onProgress: _onBytesAdded,
      onEvent: _onEvent,
      onError: _onError,
      onDone: (Uint8List bytes, String url) {
        mainProvider = getImageProvider(bytes, url);
        updateState();
      },
      cacheEnabled: settingsHandler.imageCache,
      cacheFolder: imageFolder,
    );
    client.runRequest();
    return;
  }

  void _onBytesAdded(int received, int total) {
    // always save incoming bytes, but restate only after [debounceDelay]MS
    const int debounceDelay = 100;
    bool isActive = _debounceBytes?.isActive ?? false;

    _received = received;
    _total = total;
    if (!isActive) {
      updateState();
      _debounceBytes = Timer(const Duration(milliseconds: debounceDelay), () {});
    }
  }

  void _onEvent(String event) {
    switch (event) {
      case 'loaded':
        // 
        break;
      case 'isFromCache':
        isFromCache = true;
        break;
      case 'isFromNetwork':
        isFromCache = false;
        break;
      default:
    }
    updateState();
  }

  void _onError(Exception error) {
    //// Error handling
    if (error is DioError && CancelToken.isCancel(error)) {
      // print('Canceled by user: $imageURL | $error');
    } else {
      killLoading(['Loading Error: $error']);
      print('Dio request cancelled: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    isZoomButtonVisible = settingsHandler.zoomButtonPosition != "Disabled" && settingsHandler.appMode != "Desktop";
    appbarListener = searchHandler.displayAppbar.listen((bool value) {
      if(settingsHandler.zoomButtonPosition != "Disabled" && settingsHandler.appMode != "Desktop") {
        isZoomButtonVisible = value;
      }
      updateState();
    });
    initViewer(false);
  }

  void initViewer(bool ignoreTagsCheck) {
    if ((settingsHandler.galleryMode == "Sample" && widget.booruItem.sampleURL.isNotEmpty && widget.booruItem.sampleURL != widget.booruItem.thumbnailURL) || widget.booruItem.sampleURL == widget.booruItem.fileURL){
      // use sample file if (sample gallery quality && sampleUrl exists && sampleUrl is not the same as thumbnailUrl) OR sampleUrl is the same as full res fileUrl
      imageURL = widget.booruItem.sampleURL;
      imageFolder = 'samples';
    } else {
      imageURL = widget.booruItem.fileURL;
      imageFolder = 'media';
    }

    if(widget.booruItem.isHated.value) {
      List<List<String>> hatedAndLovedTags = settingsHandler.parseTagsList(widget.booruItem.tagsList, isCapped: true);
      if (hatedAndLovedTags[0].length > 0 && !ignoreTagsCheck) {
        killLoading(['Contains Hated tags:', ...hatedAndLovedTags[0]]);
        return;
      }
    }

    // debug output
    // viewController..outputStateStream.listen(onViewStateChanged);
    scaleController..outputScaleStateStream.listen(onScaleStateChanged);

    _checkInterval?.cancel();
    _checkInterval = Timer.periodic(const Duration(seconds: 1), (timer) {
      // force restate every second to refresh all timers/indicators, even when loading has stopped
      updateState();
    });

    isStopped = false;
    _startedAt = DateTime.now().millisecondsSinceEpoch;

    updateState();

    _downloadImage();
  }

  ImageProvider getImageProvider(Uint8List bytes, String url) {
    return ResizeImage(MemoryImageTest(bytes, imageUrl: url), width: (settingsHandler.deviceSize!.width * settingsHandler.devicePixelRatio! * 2).round());
  }

  void killLoading(List<String> reason) {
    disposables();

    _total = 0;
    _received = 0;

    _prevReceivedAmount = 0;
    _lastReceivedAmount = 0;
    _lastReceivedTime = 0;
    _startedAt = 0;

    isFromCache = false;
    isStopped = true;
    stopReason = reason;

    updateState();
  }

  @override
  void dispose() {
    disposables();
    super.dispose();
  }

  void updateState() {
    if(this.mounted) setState(() { });
  }

  void disposables() {
    mainProvider?.evict();
    mainProvider = null;
    // mainProvider?.evict().then((bool success) {
    //   if(success) {
    //     ServiceHandler.displayToast('main image evicted');
    //     print('main image evicted');
    //   } else {
    //     ServiceHandler.displayToast('main image eviction failed');
    //     print('main image eviction failed');
    //   }
    // });

    _debounceBytes?.cancel();
    _checkInterval?.cancel();

    appbarListener?.cancel();

    if (!(_dioCancelToken.isCancelled)){
      _dioCancelToken.cancel();
    }
  }

  // debug functions
  void onScaleStateChanged(PhotoViewScaleState scaleState) {
    print(scaleState);

    // manual zoom || double tap || double tap AFTER double tap
    isZoomed = scaleState == PhotoViewScaleState.zoomedIn || scaleState == PhotoViewScaleState.covering || scaleState == PhotoViewScaleState.originalSize;
    updateState();
  }
  void onViewStateChanged(PhotoViewControllerValue viewState) {
    print(viewState);
  }

  void resetZoom() {
    scaleController.scaleState = PhotoViewScaleState.initial;
    updateState();
  }

  void doubleTapZoom() {
    scaleController.scaleState = PhotoViewScaleState.covering;
    updateState();
  }

  Widget zoomButtonBuild() {
    if(isZoomButtonVisible && mainProvider != null) {
      return Positioned(
        bottom: 180,
        right: settingsHandler.zoomButtonPosition == "Right" ? -10 : null,
        left: settingsHandler.zoomButtonPosition == "Left" ? -10 : null,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            primary: Theme.of(context).accentColor.withOpacity(0.33),
            minimumSize: Size(28, 28),
            padding: EdgeInsets.all(3),
          ),
          icon: Icon(isZoomed ? Icons.zoom_out : Icons.zoom_in, size: 28),
          label: Text(''),
          onPressed: isZoomed ? resetZoom : doubleTapZoom,
        )
      );
    } else {
      return const SizedBox();
    }
  }

  /// Author: [Nani-Sore] ///
  Widget loadingElementBuilder(BuildContext ctx, ImageChunkEvent? loadingProgress) {
    if(settingsHandler.shitDevice) {
      if(settingsHandler.loadingGif) {
        return Expanded(
          child: Image(image: AssetImage('assets/images/loading.gif'))
        );
      } else {
        return Center(child: CircularProgressIndicator());
      }
    }


    bool hasProgressData = (loadingProgress != null && loadingProgress.expectedTotalBytes != null) || (_total > 0);
    int expectedBytes = hasProgressData
        ? _received
        : 0;
    int totalBytes = hasProgressData
        ? _total
        : 0;

    double speedCheckInterval = 1000 / 4;
    int nowMils = DateTime.now().millisecondsSinceEpoch;
    if((nowMils - _lastReceivedTime) > speedCheckInterval && hasProgressData) {
      _prevReceivedAmount = _lastReceivedAmount;
      _lastReceivedAmount = expectedBytes;

      _lastReceivedTime = nowMils;
    }

    double? percentDone = hasProgressData ? (expectedBytes / totalBytes) : null;
    String loadedSize = hasProgressData ? Tools.formatBytes(expectedBytes, 1) : '';
    String expectedSize = hasProgressData ? Tools.formatBytes(totalBytes, 1) : '';

    int expectedSpeed = hasProgressData ? ((_lastReceivedAmount - _prevReceivedAmount) * (1000 / speedCheckInterval).round()) : 0;
    String expectedSpeedText = (hasProgressData && percentDone! < 1) ? (Tools.formatBytes(expectedSpeed, 1) + '/s') : '';
    double expectedTime = hasProgressData ? ((totalBytes - expectedBytes) / expectedSpeed) : 0;
    String expectedTimeText = (hasProgressData && expectedTime > 0 && percentDone! < 1) ? ("~" + expectedTime.toStringAsFixed(1) + " second${expectedTime == 1 ? '' : 's'} left") : '';
    int sinceStart = Duration(milliseconds: nowMils - _startedAt).inSeconds;
    String sinceStartText = "Started " + sinceStart.toString() + " second${sinceStart == 1 ? '' : 's'} ago";

    String percentDoneText = hasProgressData
        ? ((percentDone == 1 || mainProvider != null) ? 'Rendering...' : '${(percentDone! * 100).toStringAsFixed(2)}%')
        : 'Loading${isFromCache ? ' from cache' : ''}...';
    String filesizeText = hasProgressData ? ('$loadedSize / $expectedSize') : '';

    // start opacity from (0% if hated) OR (50% if of sample qulaity) OR (33% if no progress data) OR 20%
    bool isMovedBelow = settingsHandler.previewMode == 'Sample' && !widget.booruItem.isHated.value;

    return Container(
      child: Row(
        // mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(
            width: 6,
            child: RotatedBox(
              quarterTurns: -1,
              child: LinearProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(GET.Get.theme.primaryColor),
                  backgroundColor: Colors.transparent,
                  value: percentDone),
            ),
          ),
          Expanded(
            child: Padding(padding: EdgeInsets.fromLTRB(10, 10, 10, 30), child: Column(
              // move loading info lower if preview is of sample quality (except when item is hated)
              mainAxisAlignment: isMovedBelow ? MainAxisAlignment.end : MainAxisAlignment.center,
              children: isStopped
                ? [
                    ...stopReason.map((reason){
                      return BorderedText(
                        strokeWidth: 3,
                        child: Text(
                          reason,
                          style: TextStyle(
                            fontSize: 18,
                          ),
                        )
                      );
                    }),
                    TextButton.icon(
                      icon: Icon(Icons.play_arrow, size: 44),
                      label: BorderedText(
                        strokeWidth: 3,
                        child: Text(
                          widget.booruItem.isHated.value ? 'Load Anyway' : 'Restart Loading',
                          style: TextStyle(
                            fontSize: 18,
                          ),
                        )
                      ),
                      onPressed: () {
                        initViewer(true);
                      },
                    ),
                    if(isMovedBelow) const SizedBox(height: 60),
                  ]
                : (settingsHandler.loadingGif
                  ? [
                    // TODO redo
                    Center(child: Expanded(
                      child: Image(image: AssetImage('assets/images/loading.gif'))
                    )),
                    const SizedBox(height: 30),
                  ]
                  : [
                    if(percentDoneText != '')
                      BorderedText(
                        strokeWidth: 3,
                        child: Text(
                          percentDoneText,
                          style: TextStyle(
                            fontSize: 18,
                          ),
                        )
                      ),
                    if(filesizeText != '')
                      BorderedText(
                        strokeWidth: 3,
                        child: Text(
                          filesizeText,
                          style: TextStyle(
                            fontSize: 16,
                          ),
                        )
                      ),
                    if(expectedSpeedText != '')
                      BorderedText(
                        strokeWidth: 3,
                        child: Text(
                          expectedSpeedText,
                          style: TextStyle(
                            fontSize: 14,
                          ),
                        )
                      ),
                    if(expectedTimeText != '')
                      BorderedText(
                        strokeWidth: 3,
                        child: Text(
                          expectedTimeText,
                          style: TextStyle(
                            fontSize: 14,
                          ),
                        )
                      ),
                    if(sinceStartText != '')
                      BorderedText(
                        strokeWidth: 3,
                        child: Text(
                          sinceStartText,
                          style: TextStyle(
                            fontSize: 14,
                          ),
                        )
                      ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      icon: Icon(Icons.stop, size: 44, color: Colors.red),
                      label: BorderedText(
                        strokeWidth: 3,
                        child: Text(
                          'Stop Loading',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.red,
                          ),
                        )
                      ),
                      onPressed: () {
                        killLoading(['Stopped by User']);
                      },
                    ),
                    if(isMovedBelow) const SizedBox(height: 60),
                  ]
                )
            ))
          ),
          SizedBox(
            width: 6,
            child: RotatedBox(
              quarterTurns: percentDone != null ? -1 : 1,
              child: LinearProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(GET.Get.theme.primaryColor),
                backgroundColor: Colors.transparent,
                value: percentDone
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget build(BuildContext context) {
    final bool isViewed = widget.searchGlobal.viewedIndex.value == widget.index;
    if (!isViewed) {
      // reset zoom if not viewed
      resetZoom();
    }

    return Hero(
      tag: 'imageHero' + (isViewed ? '' : 'ignore') + widget.index.toString(),
      child: Material( // without this every text element will have broken styles on first frames
        child: Stack(
          alignment: Alignment.center,
          children: [
            CachedThumbBetter(widget.booruItem, widget.index, widget.searchGlobal, 1, false),
            loadingElementBuilder(context, null),
            AnimatedSwitcher(
              child: mainProvider != null
                ? PhotoView(
                  //resizeimage if resolution is too high (in attempt to fix crashes if multiple very HQ images are loaded), only check by width, otherwise looooooong/thin images could look bad
                  imageProvider: mainProvider,
                  filterQuality: FilterQuality.high,
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 8,
                  initialScale: PhotoViewComputedScale.contained,
                  enableRotation: false,
                  basePosition: Alignment.center,
                  controller: viewController,
                  // tightMode: true,
                  // heroAttributes: PhotoViewHeroAttributes(tag: 'imageHero' + (widget.viewedIndex == widget.index ? '' : 'ignore') + widget.index.toString()),
                  scaleStateController: scaleController,
                  // loadingBuilder: loadingElementBuilder,
                )
                : null,
              duration: Duration(milliseconds: 400)
            ),

            zoomButtonBuild(),
          ]
        )
      )
    );
  }
}
