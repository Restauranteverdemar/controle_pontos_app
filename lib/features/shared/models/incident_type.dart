// lib/features/shared/models/incident_type.dart
import 'package:cloud_firestore/cloud_firestore.dart';
// <<< ADICIONADO: Import necessário para comparar listas >>>
import 'package:collection/collection.dart';

/// Representa um tipo de ocorrência no sistema.
///
/// Esta classe modela os diferentes tipos de incidentes que podem ser
/// registrados para funcionários, como atrasos, faltas, elogios, etc.
class IncidentType {
  final String id; // Document ID from Firestore
  final String name;
  final int defaultPoints;
  final String? description;
  final bool isActive;
  final Timestamp? createdAt; // Firestore Timestamp
  final Timestamp? updatedAt; // Firestore Timestamp
  final String? createdBy; // UID of the admin who created/updated
  final List<String> applicableDepartments; // Departamentos aplicáveis

  // Construtor mantém o default para applicableDepartments
  IncidentType({
    required this.id,
    required this.name,
    required this.defaultPoints,
    this.description,
    required this.isActive,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.applicableDepartments = const ['Cozinha', 'Salão'],
  });

  // Factory fromSnapshot mantém a lógica de fallback
  factory IncidentType.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    List<String> departments = [];
    if (data?['applicableDepartments'] != null &&
        data!['applicableDepartments'] is List) {
      // <<< REFINADO: Garante que é uma lista antes de tentar converter >>>
      departments = List<String>.from(
          data['applicableDepartments'].map((e) => e.toString()));
    } else {
      // Fallback para retrocompatibilidade
      departments = ['Cozinha', 'Salão'];
    }

    return IncidentType(
      id: doc.id,
      name: data?['name'] ?? 'Nome Indefinido',
      defaultPoints: data?['defaultPoints'] ?? 0,
      description: data?['description'],
      isActive: data?['isActive'] ?? true,
      createdAt: data?['createdAt'] as Timestamp?,
      updatedAt: data?['updatedAt'] as Timestamp?,
      createdBy: data?['createdBy'],
      applicableDepartments: departments,
    );
  }

  // toMap mantém a adição de applicableDepartments
  Map<String, dynamic> toMap({bool isCreating = true, String? adminUserId}) {
    // Adicionado adminUserId aqui
    final map = <String, dynamic>{
      'name': name.trim(),
      'defaultPoints': defaultPoints,
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
      'applicableDepartments': applicableDepartments.isNotEmpty
          ? applicableDepartments
          // <<< MELHORIA: Remover fallback daqui, validação deve ocorrer na UI >>>
          // A lista não deve estar vazia ao salvar.
          : [
              'Cozinha',
              'Salão'
            ], // MANTIDO por enquanto, mas idealmente validar antes
    };

    if (description != null && description!.trim().isNotEmpty) {
      map['description'] = description!.trim();
    } else {
      // Define como null se vazio/nulo
      map['description'] = null;
    }

    if (isCreating) {
      map['createdAt'] = FieldValue.serverTimestamp();
      // <<< CORRIGIDO: Adiciona createdBy usando adminUserId na criação >>>
      if (adminUserId != null) {
        map['createdBy'] = adminUserId;
      }
    } else if (createdAt != null) {
      map['createdAt'] = createdAt;
      // <<< CORRIGIDO: Preserva createdBy na atualização >>>
      if (createdBy != null) {
        map['createdBy'] = createdBy;
      }
    }

    return map;
  }

  // copyWith mantém a modificação de applicableDepartments
  IncidentType copyWith({
    String? id,
    String? name,
    int? defaultPoints,
    // Usa ValueGetter para permitir setar null explicitamente
    ValueGetter<String?>? description,
    bool? isActive,
    Timestamp? createdAt,
    Timestamp? updatedAt,
    ValueGetter<String?>? createdBy,
    List<String>? applicableDepartments,
  }) {
    return IncidentType(
      id: id ?? this.id,
      name: name ?? this.name,
      defaultPoints: defaultPoints ?? this.defaultPoints,
      description: description != null ? description() : this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy != null ? createdBy() : this.createdBy,
      applicableDepartments:
          applicableDepartments ?? this.applicableDepartments,
    );
  }

  @override
  String toString() {
    return 'IncidentType(id: $id, name: $name, points: $defaultPoints, active: $isActive, departments: $applicableDepartments)';
  }

  bool get isPositive => defaultPoints >= 0;

  // <<< CORRIGIDO: Restaura a comparação detalhada usando DeepCollectionEquality >>>
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    final listEquals = const DeepCollectionEquality().equals;

    return other is IncidentType &&
        other.id == id &&
        other.name == name &&
        other.defaultPoints == defaultPoints &&
        other.description == description &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        // other.updatedAt == updatedAt && // Comparar pode ser instável
        other.createdBy == createdBy &&
        listEquals(other.applicableDepartments, applicableDepartments);
  }

  // <<< CORRIGIDO: Restaura o hashCode detalhado usando DeepCollectionEquality >>>
  @override
  int get hashCode => Object.hash(
        id,
        name,
        defaultPoints,
        description,
        isActive,
        createdAt,
        // updatedAt, // Incluir pode ser instável
        createdBy,
        const DeepCollectionEquality().hash(applicableDepartments),
      );

  // Helper mantido
  bool isApplicableToDepartment(String department) {
    // <<< MELHORIA: Comparação case-insensitive se necessário >>>
    // return applicableDepartments.any((d) => d.toLowerCase() == department.toLowerCase());
    return applicableDepartments.contains(department);
  }
}

// Helper para copyWith mantido
typedef ValueGetter<T> = T Function();
