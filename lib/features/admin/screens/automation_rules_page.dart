// lib/features/admin/screens/automation_rules_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Adicionado import para Firestore

// --- IMPORTS NECESSÁRIOS (AJUSTE OS CAMINHOS SE NECESSÁRIO) ---
import '../services/automation_rule_service.dart';
import '../../shared/models/automation_rule.dart'; // Contém AutomationRule, Enums, Condition, Action
import 'create_edit_rule_page.dart';
// --- Fim dos Imports ---

/// Tela para listar e gerenciar regras automáticas configuradas no sistema.
class AutomationRulesPage extends StatelessWidget {
  const AutomationRulesPage({super.key});

  // Cache para evitar consultas repetidas ao Firestore
  static final Map<String, String> _incidentTypeNamesCache = {};

  @override
  Widget build(BuildContext context) {
    final automationRuleService = Provider.of<AutomationRuleService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Regras Automáticas'),
        backgroundColor: Colors.orange[700],
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToCreateEdit(context),
        backgroundColor: Colors.orange[700],
        tooltip: 'Criar Nova Regra',
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderCard(context),
            const SizedBox(height: 16),
            Expanded(
              child: _buildRulesList(automationRuleService, context),
            ),
          ],
        ),
      ),
    );
  }

  // Método para navegar para tela de criação/edição (reduz duplicação de código)
  void _navigateToCreateEdit(BuildContext context, {String? ruleId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateEditRulePage(ruleId: ruleId),
      ),
    );
  }

  /// Busca o nome do tipo de incidente a partir do ID (com cache)
  Future<String> _getIncidentTypeName(String incidentTypeId) async {
    // Usa cache para evitar múltiplas consultas para o mesmo ID
    if (_incidentTypeNamesCache.containsKey(incidentTypeId)) {
      return _incidentTypeNamesCache[incidentTypeId]!;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('incidentTypes')
          .doc(incidentTypeId)
          .get();

      final name =
          doc.exists ? (doc.data()?['name'] ?? incidentTypeId) : incidentTypeId;

      // Armazena no cache para futuras consultas
      _incidentTypeNamesCache[incidentTypeId] = name;

      return name;
    } catch (e) {
      print('Erro ao buscar nome do tipo de incidente: $e');
      return incidentTypeId; // Retorna o ID em caso de erro
    }
  }

  /// Constrói o card de cabeçalho com informações sobre regras automáticas
  Widget _buildHeaderCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.orange[700], size: 28),
                const SizedBox(width: 12),
                Text(
                  'Gerenciador de Regras',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Configure regras para criar ocorrências automaticamente (bônus ou advertências) '
              'com base em condições de desempenho ou eventos.',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildInfoChip('Verificação Agendada', Icons.calendar_today),
                _buildInfoChip('Ações Automáticas', Icons.task_alt),
                _buildInfoChip('Escopo Definido', Icons.group_work),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói chips informativos para o cabeçalho
  Widget _buildInfoChip(String label, IconData iconData) {
    return Chip(
      avatar: Icon(iconData, size: 16, color: Colors.orange[700]),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: Colors.orange[50],
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  /// Constrói a lista de regras automáticas configuradas
  Widget _buildRulesList(AutomationRuleService service, BuildContext context) {
    return StreamBuilder<List<AutomationRule>>(
      stream: service.getAllRules(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Erro ao carregar regras: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          );
        }

        final rules = snapshot.data ?? [];

        if (rules.isEmpty) {
          return _buildEmptyState(context);
        }

        // Usar ListView.builder é mais eficiente para listas longas
        return ListView.builder(
          itemCount: rules.length,
          itemBuilder: (context, index) {
            final rule = rules[index];
            return _buildRuleCard(rule, service, context);
          },
        );
      },
    );
  }

  /// Constrói o estado vazio (quando não há regras configuradas)
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rule_folder_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma regra automática configurada ainda',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Clique no botão + abaixo para criar sua primeira regra de automação.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () =>
                _navigateToCreateEdit(context), // Usa método centralizado
            icon: const Icon(Icons.add),
            label: const Text('Criar Nova Regra'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói um card para exibir uma regra automática
  Widget _buildRuleCard(AutomationRule rule, AutomationRuleService service,
      BuildContext context) {
    final Color statusColor = rule.isEnabled ? Colors.green : Colors.grey;
    final IconData statusIcon =
        rule.isEnabled ? Icons.check_circle : Icons.pause_circle_filled;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _navigateToCreateEdit(context,
            ruleId: rule.id), // Usa método centralizado
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho do Card
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rule.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Switch(
                    value: rule.isEnabled,
                    activeColor: Colors.green,
                    onChanged: (value) =>
                        _toggleRuleStatus(context, service, rule.id, value),
                  ),
                ],
              ),
              const Divider(height: 16),

              // Detalhes da Regra
              _buildRuleProperty(
                'Gatilho:',
                _getTriggerName(rule.triggerFrequency),
                Icons.play_circle_outline,
                context,
              ),
              const SizedBox(height: 8),
              _buildRuleProperty(
                'Aplicado a:',
                _getScopeName(rule.targetScope),
                Icons.people_outline,
                context,
              ),
              const SizedBox(height: 8),
              _buildRuleProperty(
                'Condição:',
                _getConditionDescription(
                    rule.condition), // Agora retorna Future<String>
                Icons.checklist_rtl,
                context,
              ),
              const SizedBox(height: 8),
              _buildRuleProperty(
                'Ação:',
                _getActionDescription(
                    rule.action), // Agora retorna Future<String>
                Icons.task_alt,
                context,
              ),
              const Divider(height: 20),

              // Botões de Ação
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _navigateToCreateEdit(context,
                        ruleId: rule.id), // Usa método centralizado
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue[700],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () =>
                        _showDeleteConfirmation(context, rule, service),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Excluir'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red[700],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Método para alternar status da regra (ativo/inativo)
  Future<void> _toggleRuleStatus(BuildContext context,
      AutomationRuleService service, String ruleId, bool value) async {
    try {
      await service.toggleRuleStatus(ruleId, value);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Constrói uma linha com propriedade da regra (label: valor)
  /// Modificado para suportar tanto String quanto Future<String>
  Widget _buildRuleProperty(
      String label, dynamic value, IconData iconData, BuildContext context) {
    // Se value é um Future, usamos FutureBuilder
    if (value is Future<String>) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconData, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: FutureBuilder<String>(
              future: value,
              builder: (context, snapshot) {
                final displayValue =
                    snapshot.connectionState == ConnectionState.waiting
                        ? "Carregando..."
                        : snapshot.data ?? "Não disponível";

                return RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context)
                        .style
                        .copyWith(fontSize: 13),
                    children: [
                      TextSpan(
                        text: '$label ',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[800],
                        ),
                      ),
                      TextSpan(text: displayValue),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
    // Para valores String normais
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(iconData, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
              children: [
                TextSpan(
                  text: '$label ',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                ),
                TextSpan(text: value.toString()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Converte o enum TriggerFrequency para um nome amigável
  String _getTriggerName(TriggerFrequency frequency) {
    switch (frequency) {
      case TriggerFrequency.daily:
        return 'Verificação Diária';
      case TriggerFrequency.weekly:
        return 'Verificação Semanal';
      case TriggerFrequency.monthly:
        return 'Verificação Mensal';
      default:
        return 'Desconhecido';
    }
  }

  /// Converte o enum TargetScope para um nome amigável
  String _getScopeName(TargetScope scope) {
    switch (scope) {
      case TargetScope.all:
        return 'Todos os Funcionários';
      case TargetScope.kitchen:
        return 'Apenas Cozinha';
      case TargetScope.hall:
        return 'Apenas Salão';
      default:
        return 'Desconhecido';
    }
  }

  /// Gera uma descrição legível da condição da regra
  /// Modificado para buscar o nome real do tipo de incidente
  Future<String> _getConditionDescription(
      AutomationRuleCondition condition) async {
    // Busca o nome do tipo de incidente
    String incidentTypeName =
        condition.incidentTypeIdCondition ?? 'ID não definido';

    if (condition.incidentTypeIdCondition != null) {
      incidentTypeName =
          await _getIncidentTypeName(condition.incidentTypeIdCondition!);
    }

    switch (condition.type) {
      case ConditionType.occurrenceCount:
        final opSymbol = _getOperatorSymbol(condition.comparisonOperator);
        final periodName = _getPeriodName(condition.period);
        return 'Contagem: $incidentTypeName $opSymbol ${condition.threshold ?? '?'} no $periodName';

      case ConditionType.absenceOfOccurrence:
        final periodName = _getPeriodName(condition.period);
        return 'Ausência de: $incidentTypeName no $periodName';
      default:
        return 'Condição não detalhada';
    }
  }

  /// Helper para obter o símbolo do operador de comparação
  String _getOperatorSymbol(ComparisonOperator? op) {
    switch (op) {
      case ComparisonOperator.greaterThan:
        return '>';
      case ComparisonOperator.lessThan:
        return '<';
      case ComparisonOperator.equalTo:
        return '=';
      case ComparisonOperator.greaterThanOrEqualTo:
        return '>=';
      case ComparisonOperator.lessThanOrEqualTo:
        return '<=';
      default:
        return '?';
    }
  }

  /// Helper para obter o nome do período (baseado em TriggerFrequency por simplicidade)
  String _getPeriodName(TriggerFrequency? period) {
    switch (period) {
      case TriggerFrequency.daily:
        return 'último dia';
      case TriggerFrequency.weekly:
        return 'última semana';
      case TriggerFrequency.monthly:
        return 'último mês';
      default:
        return 'ciclo';
    }
  }

  /// Gera uma descrição legível da ação da regra
  /// Modificado para buscar o nome real do tipo de incidente
  Future<String> _getActionDescription(AutomationRuleAction action) async {
    // Busca o nome do tipo de incidente
    final typeName = await _getIncidentTypeName(action.incidentTypeIdAction);

    switch (action.type) {
      case ActionType.createOccurrence:
        final status = action.defaultStatus == OccurrenceStatus.approved
            ? 'Aprovada'
            : 'Pendente';
        return 'Criar Ocorrência: "$typeName" (Status: $status)';
      default:
        return 'Ação desconhecida';
    }
  }

  /// Exibe um diálogo de confirmação para exclusão de regra
  void _showDeleteConfirmation(BuildContext context, AutomationRule rule,
      AutomationRuleService service) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text(
            'Tem certeza que deseja excluir permanentemente a regra "${rule.name}"?\n\nEsta ação não pode ser desfeita.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => _deleteRule(
                dialogContext, context, service, rule.id, rule.name),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  // Método para excluir uma regra
  Future<void> _deleteRule(BuildContext dialogContext, BuildContext mainContext,
      AutomationRuleService service, String ruleId, String ruleName) async {
    // Fecha o diálogo
    Navigator.of(dialogContext).pop();

    try {
      await service.deleteRule(ruleId);
      if (!mainContext.mounted) return;

      ScaffoldMessenger.of(mainContext).showSnackBar(
        SnackBar(
          content: Text('Regra "$ruleName" excluída com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mainContext.mounted) return;

      ScaffoldMessenger.of(mainContext).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir regra: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
