import 'dart:async';
import 'dart:io';
import 'dart:math';

//import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:photo_view/photo_view.dart';

//import 'package:path/path.dart' as path;

import 'package:lolisnatcher/src/data/booru_item.dart';
import 'package:lolisnatcher/src/handlers/search_handler.dart';
import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/viewer_handler.dart';
import 'package:lolisnatcher/src/services/dio_downloader.dart';
import 'package:lolisnatcher/src/utils/tools.dart';
import 'package:lolisnatcher/src/widgets/common/media_loading.dart';
import 'package:lolisnatcher/src/widgets/thumbnail/thumbnail.dart';

class VideoViewerDesktop extends StatefulWidget {
  const VideoViewerDesktop(Key? key, this.booruItem, this.index) : super(key: key);
  final BooruItem booruItem;
  final int index;

  @override
  State<VideoViewerDesktop> createState() => VideoViewerDesktopState();
}

//begin seekbar
class SeekBar extends StatefulWidget {
  final Player vidcontroller;
  const SeekBar({
    Key? key,
    required this.vidcontroller,
  }) : super(key: key);

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 0.5;

  List<StreamSubscription> subscriptions = [];

  @override
  void initState() {
    super.initState();
    isPlaying = widget.vidcontroller.state.isPlaying;
    position = widget.vidcontroller.state.position;
    duration = widget.vidcontroller.state.duration;
    volume = widget.vidcontroller.state.volume;
    
    subscriptions.addAll(
      [
        widget.vidcontroller.streams.isPlaying.listen((event) {
          setState(() {
            isPlaying = event;
          });
        }),
        widget.vidcontroller.streams.position.listen((event) {
          setState(() {
            position = event;
          });
        }),
        widget.vidcontroller.streams.duration.listen((event) {
          setState(() {
            duration = event;
          });
        }),
        widget.vidcontroller.streams.volume.listen((event) {
          setState(() {
            volume = event;
          });
        }),
      ],
    );
  }

  @override
  void dispose() {
    super.dispose();
    for (final s in subscriptions) {
      s.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: widget.vidcontroller.playOrPause,
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
            ),
            color: Theme.of(context).toggleableActiveColor,
            iconSize: 36.0,
          ),
          Text(position.toString().substring(2, 7)),
          Expanded(
            child: Slider(
              min: 0.0,
              max: duration.inMilliseconds.toDouble(),
              value: position.inMilliseconds.toDouble().clamp(
                    0,
                    duration.inMilliseconds.toDouble(),
                  ),
              onChanged: (e) {
                setState(() {
                  position = Duration(milliseconds: e ~/ 1);
                });
              },
              onChangeEnd: (e) {
                widget.vidcontroller.seek(Duration(milliseconds: e ~/ 1));
              },
            ),
          ),
          Text(duration.toString().substring(2, 7)),
          //IconButton(
          //  onPressed: ,
          //  icon: Icon(
          //    Icons.volume = 0.0 ? Icons.volume_off : Icons.volume_up,,
          //  ),
          //  color: Theme.of(context).primaryColor,
          //  iconSize: 36.0,
          //),
        ],
      )
      
    );
  }
}
//end seekbar

class VideoViewerDesktopState extends State<VideoViewerDesktop> {
  final SettingsHandler settingsHandler = SettingsHandler.instance;
  final SearchHandler searchHandler = SearchHandler.instance;
  final ViewerHandler viewerHandler = ViewerHandler.instance;

  PhotoViewScaleStateController scaleController = PhotoViewScaleStateController();
  PhotoViewController viewController = PhotoViewController();
  //do a thing
  final Player controller = Player();
  //Player? controller;
  VideoController? vidcontroller;
  Media? media;

  final RxInt _total = 0.obs, _received = 0.obs, _startedAt = 0.obs;
  int _lastViewedIndex = -1;
  int isTooBig = 0; // 0 = not too big, 1 = too big, 2 = too big, but allow downloading
  bool isFromCache = false, isStopped = false, firstViewFix = false, isViewed = false, isZoomed = false, isLoaded = false;
  List<String> stopReason = [];

  StreamSubscription? indexListener;

  CancelToken? _cancelToken, _sizeCancelToken;
  DioDownloader? client, sizeClient;
  File? _video;


  Color get accentColor => Theme.of(context).colorScheme.secondary;

  @override
  void didUpdateWidget(VideoViewerDesktop oldWidget) {
    // force redraw on item data change
    if(oldWidget.booruItem != widget.booruItem) {
      // reset stuff here
      firstViewFix = false;
      //resetZoom();
      //switch (settingsHandler.videoCacheMode) {
      //  case 'Cache':
      //    // TODO load video in bg without destroying the player object, then replace with a new one
      //    killLoading([]);
      //    initVideo(false);
      //    break;
//
      //  case 'Stream+Cache':
      //    changeNetworkVideo();
      //    break;
//
      //  case 'Stream':
      //  default:
      //    changeNetworkVideo();
      //    break;
      //}
      updateState();
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> _downloadVideo() async {
    isStopped = false;
    _startedAt.value = DateTime.now().millisecondsSinceEpoch;

    if(!settingsHandler.mediaCache) {
      // Media caching disabled - don't cache videos
      initPlayer();
      getSize();
      return;
    }
    switch (settingsHandler.videoCacheMode) {
      case 'Cache':
        // Cache to device from custom request
        break;

      case 'Stream+Cache':
        // Load and stream from default player network request, cache to device from custom request
        // TODO: change video handler to allow viewing and caching from single network request
        initPlayer();
        break;

      case 'Stream':
      default:
        // Only stream, notice the return
        initPlayer();
        getSize();
        return;
    }

    _cancelToken = CancelToken();
    client = DioDownloader(
      widget.booruItem.fileURL,
      headers: Tools.getFileCustomHeaders(searchHandler.currentBooru, checkForReferer: true),
      cancelToken: _cancelToken,
      onProgress: _onBytesAdded,
      onEvent: _onEvent,
      onError: _onError,
      onDoneFile: (File file, String url) {
        _video = file;
        // save video from cache, but restate only if player is not initialized yet
        if(controller == null && !isLoaded) {
          initPlayer();
          updateState();
        }
      },
      cacheEnabled: settingsHandler.mediaCache,
      cacheFolder: 'media',
      fileNameExtras: widget.booruItem.fileNameExtras
    );
    // client!.runRequest();
    if(settingsHandler.disableImageIsolates) {
      client!.runRequest();
    } else {
      client!.runRequestIsolate();
    }
    return;
  }

  Future<void> getSize() async {
    _sizeCancelToken = CancelToken();
    sizeClient = DioDownloader(
      widget.booruItem.fileURL,
      headers: Tools.getFileCustomHeaders(searchHandler.currentBooru, checkForReferer: true),
      cancelToken: _sizeCancelToken,
      onEvent: _onEvent,
      fileNameExtras: widget.booruItem.fileNameExtras
    );
    sizeClient!.runRequestSize();
    return;
  }

  void onSize(int size) {
    // TODO find a way to stop loading based on size when caching is enabled
    const int maxSize = 1024 * 1024 * 200;
    // print('onSize: $size $maxSize ${size > maxSize}');
    if(size == 0) {
      killLoading(['File is zero bytes']);
    } else if ((size > maxSize) && isTooBig != 2) {
      // TODO add check if resolution is too big
      isTooBig = 1;
      killLoading(['File is too big', 'File size: ${Tools.formatBytes(size, 2)}', 'Limit: ${Tools.formatBytes(maxSize, 2)}']);
    }

    if (size > 0 && widget.booruItem.fileSize == null) {
      // set item file size if it wasn't received from api
      widget.booruItem.fileSize = size;
      // if(isAllowedToRestate) updateState();
    }
  }

  void _onBytesAdded(int received, int total) {
    // bool isAllowedToRestate = settingsHandler.videoCacheMode == 'Cache' || _video == null;

    _received.value = received;
    _total.value = total;
    onSize(total);
  }

  void _onEvent(String event, dynamic data) {
    switch (event) {
      case 'loaded':
        // 
        break;
      case 'size':
        onSize(data as int);
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
      if(error is DioError) {
        killLoading(['Loading Error: ${error.message}']);
      } else {
        killLoading(['Loading Error: $error']);
      }
      // print('Dio request cancelled: $error');
    }
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      vidcontroller = await VideoController.create(controller.handle);
      setState(() {});
      //sleep(Duration(seconds:1));
      playVid();
    });
          
    viewerHandler.addViewed(widget.key);

    isViewed = settingsHandler.appMode.value.isMobile
      ? searchHandler.viewedIndex.value == widget.index
      : searchHandler.viewedItem.value.fileURL == widget.booruItem.fileURL;
    indexListener = searchHandler.viewedIndex.listen((int value) {
      final bool prevViewed = isViewed;
      final bool isCurrentIndex = value == widget.index;
      final bool isCurrentItem = searchHandler.viewedItem.value.fileURL == widget.booruItem.fileURL;
      if (settingsHandler.appMode.value.isMobile ? isCurrentIndex : isCurrentItem) {
        isViewed = true;
      } else {
        isViewed = false;
      }
      if (prevViewed != isViewed) {
        if (!isViewed) {
         // reset zoom if not viewed
         resetZoom();
        }
        updateState();
      }
    });

    bool isVisible = false;
    initVideo(false);
  }

  void updateState() {
    if(mounted) {
      setState(() { });
    }
  }

  void initVideo(bool ignoreTagsCheck) {
    if (widget.booruItem.isHated.value && !ignoreTagsCheck) {
      List<List<String>> hatedAndLovedTags = settingsHandler.parseTagsList(widget.booruItem.tagsList, isCapped: true);
      killLoading(['Contains Hated tags:', ...hatedAndLovedTags[0]]);
    } else {
      _downloadVideo();
    }
  }

  void killLoading(List<String> reason) {
    disposables();

    _video = null;
    media = null;

    _total.value = 0;
    _received.value = 0;
    _startedAt.value = 0;

    isLoaded = false;
    isFromCache = false;
    isStopped = true;
    stopReason = reason;

    firstViewFix = false;

    resetZoom();

    updateState();
  }

  @override
  void dispose() {
    disposables();

    indexListener?.cancel();
    indexListener = null;

    viewerHandler.removeViewed(widget.key);
    super.dispose();
  }

  void disposeClient() {
    client?.dispose();
    client = null;
    sizeClient?.dispose();
    sizeClient = null;
  }

  void disposables() {
    // controller?.setVolume(0);
    controller.pause();
    controller.dispose();
    vidcontroller?.dispose();
    //controller = null;

    if (!(_cancelToken != null && _cancelToken!.isCancelled)){
      _cancelToken?.cancel();
    }
    if (!(_sizeCancelToken != null && _sizeCancelToken!.isCancelled)){
      _sizeCancelToken?.cancel();
    }
    disposeClient();
  }


  // debug functions
  void onScaleStateChanged(PhotoViewScaleState scaleState) {
    // print(scaleState);

    isZoomed = scaleState == PhotoViewScaleState.zoomedIn || scaleState == PhotoViewScaleState.covering || scaleState == PhotoViewScaleState.originalSize;
    viewerHandler.setZoomed(widget.key, isZoomed);
  }

  void onViewStateChanged(PhotoViewControllerValue viewState) {
    // print(viewState);
    viewerHandler.setViewState(widget.key, viewState);
  }

  void resetZoom() {
    scaleController.scaleState = PhotoViewScaleState.initial;
  }


  void doubleTapZoom() {
    viewController.scale = 2;
    // scaleController.scaleState = PhotoViewScaleState.originalSize;
  }


  Future<void> initPlayer() async {
    if(_video != null) { 
      print(_video!.path);

      media = Media(
        _video!.path,

      );
    } else {
      print(widget.booruItem.fileURL);
      media = Media(
        Uri.encodeFull(widget.booruItem.fileURL),
      );
    }
    isLoaded = true;
    controller.volume = viewerHandler.videoVolume;

    // Ensure the first frame is shown after the video is initialized, even before the play button has been pressed.
    updateState();
  }

  Future<void> playVid() async {
    await controller.open(
      Playlist(
        [
          media!
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // print('!!! Build video desktop ${widget.index}!!!');
    
    bool initialized = isLoaded; // controller != null;
    bool isVisible = false;
    bool mounted = false;

    // protects from video restart when something forces restate here while video is active (example: favoriting from appbar)
    int viewedIndex = searchHandler.viewedIndex.value;
    bool needsRestart = _lastViewedIndex != viewedIndex;

    if (initialized) {
      if (isViewed) {
        // Reset video time if came into view
        if(needsRestart) {
          controller.seek(Duration.zero);
        }

        //if(!firstViewFix) {
        //  playVid();
        //  firstViewFix = true;
        //}

        // TODO managed to fix videos starting, but needs more fixing to make sure everything is okay
        //if (settingsHandler.autoPlayEnabled) {
        //// autoplay if viewed and setting is enabled
        //  controller.play();
        //} else {
        //  controller.pause();
        //}

      //if (viewerHandler.videoAutoMute) {
      //  controller.volume = 0;
      //}
      //} else {
      //  controller.pause();
      }
    }

    if(needsRestart) {
      _lastViewedIndex = viewedIndex;
    }

    return Stack(
           //alignment: Alignment.bottomCenter,
            children: [
             Center(child: Video(controller: vidcontroller)),
                //if(isVisible)
                Container(
                  child: Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    color: Color.fromARGB(125, 0, 0, 0),
                    child: SeekBar(vidcontroller: controller),
                  )
                )
              ),
              MouseRegion(
                onEnter: (PointerEvent details)=>setState(()=>isVisible = true),
                onExit: (PointerEvent details)=>setState(()=>isVisible = false),
                opaque: false,
              )
            ]
          );
          
          
  }
}
