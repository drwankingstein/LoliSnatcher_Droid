class BooruItem{
  String fileURL,sampleURL,thumbnailURL,tagString,postURL,fileExt;
  List tagsList;
  BooruItem(this.fileURL,this.sampleURL,this.thumbnailURL,this.tagsList,this.postURL, this.fileExt){
    if (this.sampleURL.isEmpty){
      this.sampleURL = this.thumbnailURL;
    }
  }

  String get file{
    return fileURL;
  }
  String get sample{
    return sampleURL;
  }
  String get thumbnail {
    return thumbnailURL;
  }
  List<String> get tags{
    return tagString.split(" ");
  }
  toJSON(){
    return {'postURL': "$postURL",'fileURL': "$fileURL", 'sampleURL': "$sampleURL", 'thumbnailURL': "$thumbnailURL", 'tags': tagsList, 'fileExt': fileExt};
  }
}



