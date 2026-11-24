/// Google Maps links (free, no API key needed). They open the Google Maps app, or the website.
Uri mapsPoint(num lat, num lng) =>
    Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'});

/// Driving route. Origin is optional (blank = the phone's own location).
Uri mapsRoute({num? lat, num? lng, required String dest}) =>
    Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      if (lat != null && lng != null) 'origin': '$lat,$lng',
      'destination': dest,
      'travelmode': 'driving',
    });
