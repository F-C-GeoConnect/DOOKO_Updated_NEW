class ProduceListing {
  final String id;
  final String userId;
  final String name;
  final double price;
  final double? quantity;
  final String? unit;
  final String? imageUrl;
  final String? description;
  final bool available;
  final DateTime? harvestDate;

  // Joined data from nearby_produce function
  final String? farmerName;
  final double? distanceKm;

  ProduceListing({
    required this.id,
    required this.userId,
    required this.name,
    required this.price,
    this.quantity,
    this.unit,
    this.imageUrl,
    this.description,
    this.available = true,
    this.harvestDate,
    this.farmerName,
    this.distanceKm,
  });

  factory ProduceListing.fromJson(Map<String, dynamic> json) {
    return ProduceListing(
      id: json['listing_id'] ?? json['id'],
      userId: json['farmer_id'] ?? json['user_id'],
      name: json['produce_name'] ?? json['name'],
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] != null
          ? (json['quantity'] as num).toDouble()
          : null,
      unit: json['unit'],
      imageUrl: json['image_url'],
      description: json['description'],
      available: json['available'] ?? true,
      harvestDate: json['harvest_date'] != null
          ? DateTime.parse(json['harvest_date'])
          : null,
      farmerName: json['farmer_name'],
      distanceKm: json['distance_km'] != null
          ? (json['distance_km'] as num).toDouble()
          : null,
    );
  }
}