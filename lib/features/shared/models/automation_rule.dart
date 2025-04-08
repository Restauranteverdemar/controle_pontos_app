// lib/features/shared/models/automation_rule.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // para kDebugMode ou print

// --- Enums Definidos ---

/// Frequência com que a regra deve ser avaliada.
enum TriggerFrequency {
  daily,
  weekly,
  monthly,
  // onOccurrenceCreate, // Reativo - Adicionar se/quando suportado
  // onClockIn,          // Reativo - Adicionar se/quando suportado
}

/// Escopo de aplicação da regra.
enum TargetScope {
  all,
  kitchen,
  hall,
  // individual, // Poderia ter um campo extra 'targetUserId'
}

/// Tipo de condição a ser verificada.
enum ConditionType {
  occurrenceCount, // Contagem de ocorrências de um tipo específico
  absenceOfOccurrence, // Ausência de ocorrências de um tipo específico
  // checklistStatus,   // (Futuro) Verificar status de checklist
  // lateArrivalCount,  // (Futuro) Contagem de atrasos (pode ser caso especial de occurrenceCount)
}

/// Operador para comparação numérica em condições.
enum ComparisonOperator {
  greaterThan,
  lessThan,
  equalTo,
  greaterThanOrEqualTo,
  lessThanOrEqualTo,
  // notEqualTo, // Pode ser útil
}

/// Tipo de ação a ser executada.
enum ActionType {
  createOccurrence,
  // sendNotification, // (Futuro)
}

/// Status possíveis para uma ocorrência. (Reutilizar se já existir em outro lugar)
enum OccurrenceStatus {
  pending,
  approved,
  reproved,
}

// --- Classes de Suporte ---

/// Representa a condição de uma regra automática.
class AutomationRuleCondition {
  final ConditionType type;
  // Campos comuns que podem ou não ser usados dependendo do 'type'
  final String?
      incidentTypeIdCondition; // ID do tipo de ocorrência alvo da condição
  final TriggerFrequency?
      period; // Período de avaliação (ex: últimos 7 dias se TriggerFrequency.weekly) - Simplificado para usar a frequência da regra
  final ComparisonOperator? comparisonOperator; // Para contagens
  final int? threshold; // Limite para contagens
  // Adicionar outros campos conforme necessário (ex: checklistId, maxMinutesLate)

  AutomationRuleCondition({
    required this.type,
    this.incidentTypeIdCondition,
    this.period,
    this.comparisonOperator,
    this.threshold,
  });

  /// Cria a partir de um Map (Firestore).
  factory AutomationRuleCondition.fromMap(Map<String, dynamic> map) {
    return AutomationRuleCondition(
      type: _enumFromString(ConditionType.values, map['type']) ??
          ConditionType.occurrenceCount, // Default seguro
      incidentTypeIdCondition: map['incidentTypeIdCondition'],
      period: _enumFromString(TriggerFrequency.values,
          map['period']), // Armazenar período explicitamente?
      comparisonOperator:
          _enumFromString(ComparisonOperator.values, map['comparisonOperator']),
      threshold: map['threshold'],
    );
  }

  /// Converte para um Map (Firestore).
  Map<String, dynamic> toMap() {
    return {
      'type': type.name, // Salva o nome do enum
      'incidentTypeIdCondition': incidentTypeIdCondition,
      'period': period?.name,
      'comparisonOperator': comparisonOperator?.name,
      'threshold': threshold,
    }..removeWhere((key, value) => value == null); // Remove campos nulos
  }
}

/// Representa a ação de uma regra automática.
class AutomationRuleAction {
  final ActionType type;
  // Campos comuns que podem ou não ser usados dependendo do 'type'
  final String incidentTypeIdAction; // ID do IncidentType a ser criado
  final OccurrenceStatus defaultStatus; // Status inicial da ocorrência criada
  final String? defaultNotes; // Notas padrão para a ocorrência

  AutomationRuleAction({
    required this.type,
    required this.incidentTypeIdAction,
    required this.defaultStatus,
    this.defaultNotes,
  });

  /// Cria a partir de um Map (Firestore).
  factory AutomationRuleAction.fromMap(Map<String, dynamic> map) {
    return AutomationRuleAction(
      type: _enumFromString(ActionType.values, map['type']) ??
          ActionType.createOccurrence, // Default seguro
      incidentTypeIdAction: map['incidentTypeIdAction'] ?? '', // ID é crucial
      defaultStatus:
          _enumFromString(OccurrenceStatus.values, map['defaultStatus']) ??
              OccurrenceStatus.pending, // Default seguro
      defaultNotes: map['defaultNotes'],
    );
  }

  /// Converte para um Map (Firestore).
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'incidentTypeIdAction': incidentTypeIdAction,
      'defaultStatus': defaultStatus.name,
      'defaultNotes': defaultNotes,
    }..removeWhere((key, value) => value == null);
  }
}

// --- Classe Principal do Modelo ---

/// Modelo para representar uma regra de automação no sistema.
class AutomationRule {
  final String id;
  final String name; // Nome da regra (substitui ruleName)
  final String? description; // Descrição opcional
  final bool isEnabled; // Se a regra está ativa (substitui isActive)
  final TriggerFrequency
      triggerFrequency; // Frequência (substitui triggerEvent)
  final TargetScope targetScope; // Escopo de aplicação
  final AutomationRuleCondition condition; // Objeto de condição
  final AutomationRuleAction action; // Objeto de ação
  final DateTime createdAt;
  final DateTime updatedAt;

  AutomationRule({
    required this.id,
    required this.name,
    this.description,
    required this.isEnabled,
    required this.triggerFrequency,
    required this.targetScope,
    required this.condition,
    required this.action,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Cria a partir de um Documento Firestore.
  factory AutomationRule.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ??
        {}; // Garante que data não seja nulo

    // Tratamento seguro para Timestamps
    DateTime parseTimestamp(Timestamp? timestamp) {
      return timestamp?.toDate() ??
          DateTime(1970); // Default muito antigo em caso de erro/ausência
    }

    return AutomationRule(
      id: doc.id,
      name: data['name'] ?? 'Regra Sem Nome', // Default seguro
      description: data['description'],
      isEnabled: data['isEnabled'] ?? false, // Default seguro
      // Converte string salva no Firestore de volta para Enum
      triggerFrequency:
          _enumFromString(TriggerFrequency.values, data['triggerFrequency']) ??
              TriggerFrequency.daily, // Default seguro
      targetScope: _enumFromString(TargetScope.values, data['targetScope']) ??
          TargetScope.all, // Default seguro
      // Cria objetos aninhados a partir dos Maps
      condition: AutomationRuleCondition.fromMap(
          Map<String, dynamic>.from(data['condition'] ?? {})),
      action: AutomationRuleAction.fromMap(
          Map<String, dynamic>.from(data['action'] ?? {})),
      createdAt: parseTimestamp(data['createdAt'] as Timestamp?),
      updatedAt: parseTimestamp(data['updatedAt'] as Timestamp?),
    );
  }

  /// Converte para um Map para salvar no Firestore.
  /// Note: Não inclui 'id', 'createdAt', 'updatedAt' pois são gerenciados de forma diferente.
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'isEnabled': isEnabled,
      'triggerFrequency': triggerFrequency.name, // Salva o nome do enum
      'targetScope': targetScope.name, // Salva o nome do enum
      'condition': condition.toMap(), // Converte objeto aninhado para Map
      'action': action.toMap(), // Converte objeto aninhado para Map
      // createdAt e updatedAt são adicionados/atualizados pelo serviço usando FieldValue.serverTimestamp()
    }..removeWhere((key, value) =>
        value == null); // Limpa nulos opcionais como description
  }

  /// Cria uma cópia com valores alterados.
  AutomationRule copyWith({
    String? id,
    String? name,
    String? description,
    bool? isEnabled,
    TriggerFrequency? triggerFrequency,
    TargetScope? targetScope,
    AutomationRuleCondition? condition,
    AutomationRuleAction? action,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AutomationRule(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ??
          this.description, // Cuidado com null vs valor existente
      isEnabled: isEnabled ?? this.isEnabled,
      triggerFrequency: triggerFrequency ?? this.triggerFrequency,
      targetScope: targetScope ?? this.targetScope,
      condition: condition ?? this.condition,
      action: action ?? this.action,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'AutomationRule(id: $id, name: $name, isEnabled: $isEnabled, frequency: ${triggerFrequency.name}, scope: ${targetScope.name})';
  }
}

// --- Helper para converter String para Enum com segurança ---
T? _enumFromString<T>(List<T> values, String? value) {
  if (value == null) return null;
  try {
    // Tenta encontrar pelo nome (case-insensitive pode ser adicionado se necessário)
    return values
        .firstWhere((type) => type.toString().split('.').last == value);
  } catch (e) {
    // Se não encontrar, retorna null (ou loga um erro)
    if (kDebugMode) {
      // Evita prints em produção
      print('Erro ao converter string "$value" para enum $T: $e');
    }
    return null;
  }
}
