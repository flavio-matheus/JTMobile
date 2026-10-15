import 'dart:math';

/// Localizador Maidenhead (4 ou 6 caracteres) -> centro (lat, lon) em graus. Null se inválido.
({double lat, double lon})? gridToLatLon(String grid) {
  final g = grid.trim().toUpperCase();
  if (!RegExp(r'^[A-R]{2}[0-9]{2}([A-X]{2})?$').hasMatch(g)) return null;
  var lon = (g.codeUnitAt(0) - 65) * 20.0 - 180.0;
  var lat = (g.codeUnitAt(1) - 65) * 10.0 - 90.0;
  lon += (g.codeUnitAt(2) - 48) * 2.0;
  lat += (g.codeUnitAt(3) - 48) * 1.0;
  if (g.length >= 6) {
    lon += (g.codeUnitAt(4) - 65) * (2.0 / 24) + (1.0 / 24);
    lat += (g.codeUnitAt(5) - 65) * (1.0 / 24) + (0.5 / 24);
  } else {
    lon += 1.0;
    lat += 0.5;
  }
  return (lat: lat, lon: lon);
}

double _rad(double d) => d * pi / 180.0;

/// Distância (km) e azimute inicial (graus) entre dois pontos.
({double km, double bearing}) distanceBearing(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final p1 = _rad(lat1), p2 = _rad(lat2);
  final dl = _rad(lon2 - lon1);
  final dp = p2 - p1;
  final a = pow(sin(dp / 2), 2) + cos(p1) * cos(p2) * pow(sin(dl / 2), 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  final y = sin(dl) * cos(p2);
  final x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl);
  final brg = (atan2(y, x) * 180 / pi + 360) % 360;
  return (km: r * c, bearing: brg);
}

String bearingCompass(double b) {
  const names = ['N', 'NE', 'L', 'SE', 'S', 'SO', 'O', 'NO'];
  return names[((b + 22.5) % 360 ~/ 45)];
}
