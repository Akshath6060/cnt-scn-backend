/// Coarse entity classes recognised by the local rule-based extractor (§8.1).
///
/// Only [name] and [phone] drive contact creation in the MVP; the remaining
/// classes are retained because their *position* helps identify rows, and
/// because discarding them early would violate §8.5.
enum EntityType {
  name,
  phone,
  email,
  address,
  organization,
  heading,
  serialNumber,
  unknown;

  /// Whether this entity contributes a field to a generated contact.
  bool get isContactField => this == EntityType.name || this == EntityType.phone;

  /// Entities that are structurally useful for row detection but are never
  /// paired into a contact.
  bool get isIgnorable => switch (this) {
        EntityType.email ||
        EntityType.address ||
        EntityType.organization ||
        EntityType.heading ||
        EntityType.serialNumber =>
          true,
        _ => false,
      };

  String get label => switch (this) {
        EntityType.name => 'Name',
        EntityType.phone => 'Phone',
        EntityType.email => 'Email',
        EntityType.address => 'Address',
        EntityType.organization => 'Organisation',
        EntityType.heading => 'Heading',
        EntityType.serialNumber => 'Serial number',
        EntityType.unknown => 'Unknown',
      };
}
