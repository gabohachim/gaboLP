class CoverCandidate {
  final String coverUrl250;
  final String coverUrl500;
  final String? year;
  final String? mbid; // release-group id (MusicBrainz), opcional

  CoverCandidate({
    required this.coverUrl250,
    required this.coverUrl500,
    this.year,
    this.mbid,
  });
}
