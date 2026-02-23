/// Authenticated user profile returned by `GET /users/me`.
///
/// Contains account info, linked [deviceIds], and an optional [healthProfile].
class User {
  final String id;
  final String email;
  final String name;
  final List<String> deviceIds;
  final HealthProfile? healthProfile;

  User({
    required this.id,
    required this.email,
    required this.name,
    this.deviceIds = const [],
    this.healthProfile,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] ?? json['_id'] ?? '',
        email: json['email'] ?? '',
        name: json['name'] ?? '',
        deviceIds: List<String>.from(json['device_ids'] ?? []),
        healthProfile: json['health_profile'] != null
            ? HealthProfile.fromJson(json['health_profile'])
            : null,
      );
}

/// Patient health profile used by the ML risk model for context-aware predictions.
///
/// Fields map directly to the backend `health_profile` sub-document.
class HealthProfile {
  final int? age;
  final String? sex;
  final double? heightCm;
  final double? weightKg;
  final bool diabetic;
  final bool hypertensive;
  final bool smoker;
  final bool familyHistory;
  final List<String> knownConditions;
  final List<String> medications;

  HealthProfile({
    this.age,
    this.sex,
    this.heightCm,
    this.weightKg,
    this.diabetic = false,
    this.hypertensive = false,
    this.smoker = false,
    this.familyHistory = false,
    this.knownConditions = const [],
    this.medications = const [],
  });

  factory HealthProfile.fromJson(Map<String, dynamic> json) => HealthProfile(
        age: json['age'],
        sex: json['sex'],
        heightCm: (json['height_cm'] as num?)?.toDouble(),
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        diabetic: json['diabetic'] ?? false,
        hypertensive: json['hypertensive'] ?? false,
        smoker: json['smoker'] ?? false,
        familyHistory: json['family_history'] ?? false,
        knownConditions: List<String>.from(json['known_conditions'] ?? []),
        medications: List<String>.from(json['medications'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        if (age != null) 'age': age,
        if (sex != null) 'sex': sex,
        if (heightCm != null) 'height_cm': heightCm,
        if (weightKg != null) 'weight_kg': weightKg,
        'diabetic': diabetic,
        'hypertensive': hypertensive,
        'smoker': smoker,
        'family_history': familyHistory,
        'known_conditions': knownConditions,
        'medications': medications,
      };
}

/// JWT token pair returned by `POST /auth/login` and `POST /auth/register`.
class TokenResponse {
  final String accessToken;
  final String tokenType;

  TokenResponse({required this.accessToken, required this.tokenType});

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
        accessToken: json['access_token'],
        tokenType: json['token_type'] ?? 'bearer',
      );
}
