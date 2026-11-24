import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// OpenStreetMap view (free, no API key) with one truck marker.
class LiveMap extends StatelessWidget {
  final double lat, lng;
  const LiveMap({super.key, required this.lat, required this.lng});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          key: ValueKey('$lat,$lng'),
          options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: 14),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.briedibleoils.br_edible_oils_erp',
            ),
            MarkerLayer(markers: [
              Marker(point: LatLng(lat, lng), width: 44, height: 44,
                  child: const Icon(Icons.local_shipping, size: 36, color: Colors.red)),
            ]),
            const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
          ],
        ),
      ),
    );
  }
}
