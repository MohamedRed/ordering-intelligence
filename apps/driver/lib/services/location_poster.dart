abstract class LocationPoster {
  Future<void> postLocation({
    required double lat,
    required double lng,
    double accuracyM = 0,
  });
}
