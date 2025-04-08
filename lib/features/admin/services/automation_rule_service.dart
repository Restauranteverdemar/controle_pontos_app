// lib/features/admin/services/automation_rule_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// Importa o modelo REFATORADO e seus componentes
import '../../shared/models/automation_rule.dart';

/// Serviço responsável por gerenciar as regras de automação no Firestore.
class AutomationRuleService with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'automationRules'; // Nome da coleção no Firestore

  /// Obtém um stream com todas as regras, ordenadas por nome.
  /// A ordenação por 'createdAt' também é válida, ajuste conforme necessidade.
  Stream<List<AutomationRule>> getAllRules() {
    return _firestore
        .collection(_collection)
        .orderBy('name') // Ordenar por nome pode ser mais útil para o Admin
        // .orderBy('createdAt', descending: true) // Alternativa
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) =>
                AutomationRule.fromFirestore(doc)) // Usa o factory atualizado
            .toList());
  }

  /// Obtém um stream com as regras ATIVAS para uma FREQUÊNCIA de gatilho específica.
  /// Útil para o backend (Cloud Functions) encontrar as regras a serem executadas.
  Stream<List<AutomationRule>> getActiveRulesByFrequency(
      TriggerFrequency frequency) {
    return _firestore
        .collection(_collection)
        .where('isEnabled', isEqualTo: true) // Filtra por ativas
        .where('triggerFrequency',
            isEqualTo: frequency
                .name) // Filtra pela frequência (usando o nome do enum)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AutomationRule.fromFirestore(doc))
            .toList());
  }

  /// Busca uma regra específica pelo seu ID.
  Future<AutomationRule?> getRuleById(String ruleId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(ruleId).get();
      if (doc.exists) {
        // Usa o factory atualizado do modelo
        return AutomationRule.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('Erro ao buscar regra por ID ($ruleId): $e');
      rethrow; // Propaga o erro para a UI tratar
    }
  }

  /// Cria uma nova regra automática usando os objetos e enums do modelo.
  Future<String> createRule({
    required String name,
    String? description,
    required bool isEnabled,
    required TriggerFrequency triggerFrequency,
    required TargetScope targetScope,
    required AutomationRuleCondition condition,
    required AutomationRuleAction action,
  }) async {
    try {
      final Map<String, dynamic> ruleData = {
        'name': name,
        'description': description,
        'isEnabled': isEnabled,
        'triggerFrequency': triggerFrequency.name, // Salva o nome do enum
        'targetScope': targetScope.name, // Salva o nome do enum
        'condition': condition.toMap(), // Converte objeto para Map
        'action': action.toMap(), // Converte objeto para Map
        'createdAt': FieldValue.serverTimestamp(), // Timestamp do servidor
        'updatedAt': FieldValue.serverTimestamp(), // Timestamp do servidor
      }..removeWhere(
          (key, value) => value == null); // Remove description se for nulo

      final docRef = await _firestore.collection(_collection).add(ruleData);

      notifyListeners(); // Notifica a UI sobre a nova regra
      return docRef.id;
    } catch (e) {
      debugPrint('Erro ao criar regra: $e');
      rethrow;
    }
  }

  /// Atualiza uma regra existente usando um objeto AutomationRule.
  /// Usa o método `toFirestore()` do modelo para gerar os dados.
  Future<void> updateRule(AutomationRule rule) async {
    try {
      // Obtém o Map a partir do modelo (que já lida com enums e objetos aninhados)
      final updateData = rule.toFirestore();
      // Adiciona o timestamp de atualização
      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_collection).doc(rule.id).update(updateData);

      notifyListeners(); // Notifica a UI
    } catch (e) {
      debugPrint('Erro ao atualizar regra (${rule.id}): $e');
      rethrow;
    }
  }

  /// Ativa ou desativa uma regra específica.
  Future<void> toggleRuleStatus(String ruleId, bool isEnabled) async {
    try {
      await _firestore.collection(_collection).doc(ruleId).update({
        'isEnabled': isEnabled, // Atualiza o campo correto
        'updatedAt': FieldValue.serverTimestamp(), // Atualiza timestamp
      });

      notifyListeners(); // Notifica a UI
    } catch (e) {
      debugPrint('Erro ao alternar status da regra ($ruleId): $e');
      rethrow;
    }
  }

  /// Exclui uma regra pelo ID.
  Future<void> deleteRule(String ruleId) async {
    try {
      await _firestore.collection(_collection).doc(ruleId).delete();

      notifyListeners(); // Notifica a UI que um item foi removido
    } catch (e) {
      debugPrint('Erro ao excluir regra ($ruleId): $e');
      rethrow;
    }
  }
}
