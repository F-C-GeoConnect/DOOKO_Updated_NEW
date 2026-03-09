import 'package:latlong2/latlong.dart';

enum UserRole { farmer, consumer, both }

class UserProfile {
  final String id;
  final String name;
  final String phone;
  final UserRole role;
  final LatLng? location;
  final String? address;
  final double deliveryRadiusKm;
  final String? profileImageUrl;

  UserProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.location,
    this.address,
    this.deliveryRadiusKm = 5.0,
    this.profileImageUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      name: json['name'],
      phone: json['phone'],
      role: _parseRole(json['role']),
      location: json['location'] != null
          ? _parseLocation(json['location'])
          : null,
      address: json['address'],
      deliveryRadiusKm: (json['delivery_radius_km'] ?? 5.0).toDouble(),
      profileImageUrl: json['profile_image_url'],
    );
  }

  static UserRole _parseRole(String role) {
    switch (role) {
      case 'farmer': return UserRole.farmer;
      case 'consumer': return UserRole.consumer;
      case 'both': return UserRole.both;
      default: return UserRole.consumer;
    }
  }

  static LatLng? _parseLocation(dynamic location) {
    // PostGIS returns GeoJSON or WKT
    if (location is Map) {
      final coords = location['coordinates'] as List;
      return LatLng(coords[1], coords[0]); // lat, lng
    }
    return null;
  }

  bool get isFarmer => role == UserRole.farmer || role == UserRole.both;
  bool get isConsumer => role == UserRole.consumer || role == UserRole.both;
}