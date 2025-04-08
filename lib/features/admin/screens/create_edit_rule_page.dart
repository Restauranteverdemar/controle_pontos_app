// lib/features/admin/screens/create_edit_rule_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/automation_rule_service.dart';
import '../../shared/models/automation_rule.dart';
import '../../shared/models/incident_type.dart';
import '../../shared/services/point_occurrence_service.dart';

class CreateEditRulePage extends StatefulWidget {
  final String? ruleId;

  const CreateEditRulePage({super.key, this.ruleId});

  @override
  State<CreateEditRulePage> createState() => _CreateEditRulePageState();
}

class _CreateEditRulePageState extends State<CreateEditRulePage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers - agrupados por função
  final _textControllers = {
    'name': TextEditingController(),
    'description': TextEditingController(),
    'conditionThreshold': TextEditingController(),
    'actionNotes': TextEditingController(),
  };

  // Estado - agrupado por categoria
  final _loadingState = {
    'page': false,
    'incidentTypes': false,
  };

  // Configuração da regra
  bool _isEnabled = true;
  TriggerFrequency _selectedFrequency = TriggerFrequency.daily;
  TargetScope _selectedScope = TargetScope.all;

  // Condição
  ConditionType _selectedConditionType = ConditionType.occurrenceCount;
  ComparisonOperator _selectedComparisonOperator =
      ComparisonOperator.greaterThanOrEqualTo;
  String? _selectedConditionIncidentTypeId;

  // Ação
  ActionType _selectedActionType = ActionType.createOccurrence;
  OccurrenceStatus _selectedActionStatus = OccurrenceStatus.pending;
  String? _selectedActionIncidentTypeId;

  // Dados auxiliares
  List<IncidentType> _incidentTypeOptions = [];
  bool _isEditMode = false;
  AutomationRule? _originalRule;

  // Services
  late AutomationRuleService _automationRuleService;
  late PointOccurrenceService _pointOccurrenceService;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.ruleId != null;

    // Adiado para depois da construção do widget para evitar erros de contexto
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServices();
      _loadInitialData();
    });
  }

  // Extraído inicialização de serviços para método dedicado
  void _initializeServices() {
    _automationRuleService =
        Provider.of<AutomationRuleService>(context, listen: false);
    _pointOccurrenceService =
        Provider.of<PointOccurrenceService>(context, listen: false);
  }

  // Método centralizado para carregamento de dados iniciais
  Future<void> _loadInitialData() async {
    await _loadIncidentTypes();
    if (_isEditMode) {
      await _loadRuleData();
    }
  }

  @override
  void dispose() {
    // Limpeza de controladores em loop para evitar duplicação
    _textControllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  /// Carrega Incident Types usando PointOccurrenceService
  Future<void> _loadIncidentTypes() async {
    if (!mounted) return;

    _setLoading('incidentTypes', true);

    try {
      final types = await _pointOccurrenceService.getIncidentTypes();

      if (mounted) {
        setState(() {
          _incidentTypeOptions = types;

          // Define valores padrão apenas se necessário
          if (_incidentTypeOptions.isNotEmpty && !_isEditMode) {
            _selectedConditionIncidentTypeId ??= _incidentTypeOptions.first.id;
            _selectedActionIncidentTypeId ??= _incidentTypeOptions.first.id;
          }
        });
      }
    } catch (e) {
      _showErrorMessage('Erro ao carregar tipos de ocorrência: $e');
    } finally {
      _setLoading('incidentTypes', false);
    }
  }

  /// Carrega dados da regra para edição
  Future<void> _loadRuleData() async {
    if (!_isEditMode || widget.ruleId == null || !mounted) return;

    _setLoading('page', true);

    try {
      final rule = await _automationRuleService.getRuleById(widget.ruleId!);

      if (rule != null && mounted) {
        _populateFormWithRule(rule);
      } else if (mounted) {
        _showErrorMessage('Regra não encontrada.');
        Navigator.pop(context);
      }
    } catch (e) {
      _showErrorMessage('Erro ao carregar dados da regra: $e');
      if (mounted) Navigator.pop(context);
    } finally {
      _setLoading('page', false);
    }
  }

  // Extraído lógica de preenchimento do formulário para método dedicado
  void _populateFormWithRule(AutomationRule rule) {
    setState(() {
      _originalRule = rule;
      _textControllers['name']!.text = rule.name;
      _textControllers['description']!.text = rule.description ?? '';
      _isEnabled = rule.isEnabled;
      _selectedFrequency = rule.triggerFrequency;
      _selectedScope = rule.targetScope;
      _selectedConditionType = rule.condition.type;
      _selectedConditionIncidentTypeId = rule.condition.incidentTypeIdCondition;
      _textControllers['conditionThreshold']!.text =
          rule.condition.threshold?.toString() ?? '';
      _selectedComparisonOperator = rule.condition.comparisonOperator ??
          ComparisonOperator.greaterThanOrEqualTo;
      _selectedActionType = rule.action.type;
      _selectedActionIncidentTypeId = rule.action.incidentTypeIdAction;
      _selectedActionStatus = rule.action.defaultStatus;
      _textControllers['actionNotes']!.text = rule.action.defaultNotes ?? '';
    });
  }

  // Simplificado manipulação de estado de carregamento
  void _setLoading(String key, bool value) {
    if (mounted) {
      setState(() => _loadingState[key] = value);
    }
  }

  /// Salva a regra (cria ou atualiza)
  Future<void> _saveRule() async {
    if (!_validateForm()) return;

    if (!mounted) return;
    _setLoading('page', true);

    try {
      if (_isEditMode && _originalRule != null) {
        await _updateExistingRule();
      } else {
        await _createNewRule();
      }

      if (mounted) {
        _showSuccessMessage(_isEditMode
            ? 'Regra atualizada com sucesso!'
            : 'Regra criada com sucesso!');
        Navigator.pop(context);
      }
    } catch (e) {
      _showErrorMessage('Erro ao salvar regra: $e');
    } finally {
      _setLoading('page', false);
    }
  }

  // Separada validação do formulário em método dedicado
  bool _validateForm() {
    if (!_formKey.currentState!.validate()) {
      _showErrorMessage('Por favor, corrija os erros no formulário.');
      return false;
    }

    // Validação para condição de contagem de ocorrências
    if ((_selectedConditionType == ConditionType.occurrenceCount ||
            _selectedConditionType == ConditionType.absenceOfOccurrence) &&
        (_selectedConditionIncidentTypeId == null ||
            _selectedConditionIncidentTypeId!.isEmpty)) {
      _showErrorMessage('Selecione o tipo de ocorrência para a condição.');
      return false;
    }

    // Validação para tipo de ocorrência da ação
    if (_selectedActionIncidentTypeId == null ||
        _selectedActionIncidentTypeId!.isEmpty) {
      _showErrorMessage('Selecione o tipo de ocorrência para a ação.');
      return false;
    }

    return true;
  }

  // Extraída lógica de criação de condição para método dedicado
  AutomationRuleCondition _buildCondition() {
    switch (_selectedConditionType) {
      case ConditionType.occurrenceCount:
        final threshold =
            int.tryParse(_textControllers['conditionThreshold']!.text.trim());
        if (threshold == null) {
          throw Exception("Valor inválido para o limite da condição.");
        }
        return AutomationRuleCondition(
          type: _selectedConditionType,
          incidentTypeIdCondition: _selectedConditionIncidentTypeId,
          comparisonOperator: _selectedComparisonOperator,
          threshold: threshold,
          period: _selectedFrequency,
        );
      case ConditionType.absenceOfOccurrence:
        return AutomationRuleCondition(
          type: _selectedConditionType,
          incidentTypeIdCondition: _selectedConditionIncidentTypeId,
          period: _selectedFrequency,
        );
      default:
        throw Exception("Tipo de condição inválido.");
    }
  }

  // Extraída lógica de criação de ação para método dedicado
  AutomationRuleAction _buildAction() {
    return AutomationRuleAction(
      type: _selectedActionType,
      incidentTypeIdAction: _selectedActionIncidentTypeId!,
      defaultStatus: _selectedActionStatus,
      defaultNotes: _textControllers['actionNotes']!.text.trim().isEmpty
          ? null
          : _textControllers['actionNotes']!.text.trim(),
    );
  }

  // Extraída lógica de atualização para método dedicado
  Future<void> _updateExistingRule() async {
    final updatedRule = _originalRule!.copyWith(
      name: _textControllers['name']!.text.trim(),
      description: _textControllers['description']!.text.trim().isEmpty
          ? null
          : _textControllers['description']!.text.trim(),
      isEnabled: _isEnabled,
      triggerFrequency: _selectedFrequency,
      targetScope: _selectedScope,
      condition: _buildCondition(),
      action: _buildAction(),
    );

    await _automationRuleService.updateRule(updatedRule);
  }

  // Extraída lógica de criação para método dedicado
  Future<void> _createNewRule() async {
    await _automationRuleService.createRule(
      name: _textControllers['name']!.text.trim(),
      description: _textControllers['description']!.text.trim().isEmpty
          ? null
          : _textControllers['description']!.text.trim(),
      isEnabled: _isEnabled,
      triggerFrequency: _selectedFrequency,
      targetScope: _selectedScope,
      condition: _buildCondition(),
      action: _buildAction(),
    );
  }

  // --- Métodos auxiliares para UI ---
  void _showErrorMessage(String message) {
    if (!mounted) return;
    _showSnackBar(message, Colors.red);
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    _showSnackBar(message, Colors.green);
  }

  // Refatorado para método comum de SnackBar para evitar duplicação
  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Seção de cabeçalho extraída para método reutilizável
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.orange[700], size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const Divider(thickness: 1),
        ],
      ),
    );
  }

  // Método para criar dropdowns de tipos de incidente reutilizável
  Widget _buildIncidentTypeDropdown({
    required String labelText,
    required String hintText,
    required String? selectedValue,
    required Function(String?) onChanged,
    required String? Function(String?)? validator,
  }) {
    if (_loadingState['incidentTypes']!) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: Text('Carregando tipos...'),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: selectedValue,
      disabledHint: _incidentTypeOptions.isEmpty
          ? const Text("Nenhum tipo cadastrado")
          : null,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        border: const OutlineInputBorder(),
      ),
      isExpanded: true,
      items: _incidentTypeOptions
          .map((IncidentType type) => DropdownMenuItem(
                value: type.id,
                child: Text(type.name),
              ))
          .toList(),
      onChanged: _incidentTypeOptions.isEmpty ? null : onChanged,
      validator: validator,
    );
  }

  // --- Seções de UI refatoradas em métodos separados ---
  Widget _buildBasicInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Informações Básicas', Icons.info_outline),
        TextFormField(
          controller: _textControllers['name'],
          decoration: const InputDecoration(
            labelText: 'Nome da Regra*',
            hintText: 'Ex: Bônus Semanal - Sem Faltas',
            border: OutlineInputBorder(),
          ),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'O nome da regra é obrigatório'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _textControllers['description'],
          decoration: const InputDecoration(
            labelText: 'Descrição (Opcional)',
            hintText: 'Explique o propósito da regra',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Regra Ativa'),
          subtitle: Text(_isEnabled
              ? 'Sim, a regra será avaliada'
              : 'Não, a regra está desativada'),
          value: _isEnabled,
          activeColor: Colors.green,
          onChanged: (value) => setState(() => _isEnabled = value),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildTriggerAndScopeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Gatilho e Escopo', Icons.settings_ethernet),
        DropdownButtonFormField<TriggerFrequency>(
          value: _selectedFrequency,
          decoration: const InputDecoration(
            labelText: 'Quando avaliar a regra?*',
            border: OutlineInputBorder(),
          ),
          items: TriggerFrequency.values
              .map((freq) => DropdownMenuItem(
                    value: freq,
                    child: Text(_getTriggerFrequencyName(freq)),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _selectedFrequency = value!),
          validator: (value) => value == null ? 'Selecione a frequência' : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<TargetScope>(
          value: _selectedScope,
          decoration: const InputDecoration(
            labelText: 'Aplicar a quem?*',
            border: OutlineInputBorder(),
          ),
          items: TargetScope.values
              .map((scope) => DropdownMenuItem(
                    value: scope,
                    child: Text(_getTargetScopeName(scope)),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _selectedScope = value!),
          validator: (value) => value == null ? 'Selecione o escopo' : null,
        ),
      ],
    );
  }

  Widget _buildConditionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Condição para Ativação', Icons.rule),
        DropdownButtonFormField<ConditionType>(
          value: _selectedConditionType,
          decoration: const InputDecoration(
            labelText: 'Tipo de Condição*',
            border: OutlineInputBorder(),
          ),
          items: ConditionType.values
              .map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(_getConditionTypeName(type)),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _selectedConditionType = value!),
          validator: (value) =>
              value == null ? 'Selecione o tipo de condição' : null,
        ),
        const SizedBox(height: 16),
        _buildConditionFields(),
      ],
    );
  }

  Widget _buildActionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Ação a ser Tomada', Icons.play_arrow_outlined),
        _buildIncidentTypeDropdown(
          labelText: 'Criar qual Tipo de Ocorrência?*',
          hintText: 'Selecione o bônus ou advertência',
          selectedValue: _selectedActionIncidentTypeId,
          onChanged: (value) =>
              setState(() => _selectedActionIncidentTypeId = value),
          validator: (value) => (value == null || value!.isEmpty)
              ? 'Selecione o tipo para a ação'
              : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<OccurrenceStatus>(
          value: _selectedActionStatus,
          decoration: const InputDecoration(
            labelText: 'Status Inicial da Ocorrência*',
            border: OutlineInputBorder(),
          ),
          items: OccurrenceStatus.values
              .where((s) => s != OccurrenceStatus.reproved)
              .map((status) => DropdownMenuItem(
                    value: status,
                    child: Text(_getOccurrenceStatusName(status)),
                  ))
              .toList(),
          onChanged: (value) => setState(() => _selectedActionStatus = value!),
          validator: (value) =>
              value == null ? 'Selecione o status inicial' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _textControllers['actionNotes'],
          decoration: const InputDecoration(
            labelText: 'Observações da Ocorrência (Opcional)',
            hintText: 'Ex: Bônus aplicado automaticamente',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: Text(_isEditMode ? 'Atualizar Regra' : 'Salvar Nova Regra'),
          onPressed: _loadingState['page']! ? null : _saveRule,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange[700],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (!_isEditMode)
          Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: TextButton(
              onPressed:
                  _loadingState['page']! ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ),
      ],
    );
  }

  /// Constrói os campos específicos da condição selecionada
  Widget _buildConditionFields() {
    switch (_selectedConditionType) {
      case ConditionType.occurrenceCount:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIncidentTypeDropdown(
              labelText: 'Contar qual Tipo de Ocorrência?*',
              hintText: 'Selecione a ocorrência a ser contada',
              selectedValue: _selectedConditionIncidentTypeId,
              onChanged: (value) =>
                  setState(() => _selectedConditionIncidentTypeId = value),
              validator: (value) => (value == null || value!.isEmpty)
                  ? 'Selecione o tipo para a condição'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ComparisonOperator>(
              value: _selectedComparisonOperator,
              decoration: const InputDecoration(
                labelText: 'Operador de Comparação*',
                border: OutlineInputBorder(),
              ),
              items: ComparisonOperator.values
                  .map((op) => DropdownMenuItem(
                        value: op,
                        child: Text(_getComparisonOperatorSymbolAndName(op)),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _selectedComparisonOperator = value!),
              validator: (value) =>
                  value == null ? 'Selecione o operador' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _textControllers['conditionThreshold'],
              decoration: const InputDecoration(
                labelText: 'Limite Numérico*',
                hintText: 'Ex: 3 (aciona se >= 3)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: _validateThreshold,
            ),
          ],
        );

      case ConditionType.absenceOfOccurrence:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildIncidentTypeDropdown(
              labelText: 'Verificar Ausência de qual Tipo?*',
              hintText: 'Selecione a ocorrência que NÃO deve existir',
              selectedValue: _selectedConditionIncidentTypeId,
              onChanged: (value) =>
                  setState(() => _selectedConditionIncidentTypeId = value),
              validator: (value) => (value == null || value!.isEmpty)
                  ? 'Selecione o tipo para verificar ausência'
                  : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'A regra será acionada se NENHUMA ocorrência deste tipo for encontrada no período avaliado.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // Extraído validador de threshold para função separada
  String? _validateThreshold(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Informe o limite';
    }
    if (int.tryParse(value.trim()) == null) {
      return 'Valor inválido';
    }
    if (int.parse(value.trim()) < 0) {
      return 'Valor não pode ser negativo';
    }
    return null;
  }

  // --- Funções Helper para Nomes de Enums ---
  String _getTriggerFrequencyName(TriggerFrequency freq) {
    switch (freq) {
      case TriggerFrequency.daily:
        return 'Diária';
      case TriggerFrequency.weekly:
        return 'Semanal';
      case TriggerFrequency.monthly:
        return 'Mensal';
    }
  }

  String _getTargetScopeName(TargetScope scope) {
    switch (scope) {
      case TargetScope.all:
        return 'Todos';
      case TargetScope.kitchen:
        return 'Cozinha';
      case TargetScope.hall:
        return 'Salão';
    }
  }

  String _getConditionTypeName(ConditionType type) {
    switch (type) {
      case ConditionType.occurrenceCount:
        return 'Contagem de Ocorrências';
      case ConditionType.absenceOfOccurrence:
        return 'Ausência de Ocorrência';
    }
  }

  String _getComparisonOperatorSymbolAndName(ComparisonOperator op) {
    switch (op) {
      case ComparisonOperator.greaterThan:
        return '> (Maior que)';
      case ComparisonOperator.lessThan:
        return '< (Menor que)';
      case ComparisonOperator.equalTo:
        return '= (Igual a)';
      case ComparisonOperator.greaterThanOrEqualTo:
        return '>= (Maior ou Igual a)';
      case ComparisonOperator.lessThanOrEqualTo:
        return '<= (Menor ou Igual a)';
    }
  }

  String _getOccurrenceStatusName(OccurrenceStatus status) {
    switch (status) {
      case OccurrenceStatus.pending:
        return 'Pendente';
      case OccurrenceStatus.approved:
        return 'Aprovado';
      case OccurrenceStatus.reproved:
        return 'Reprovado';
    }
  }

  // --- Build Method reorganizado para usar as seções refatoradas ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isEditMode ? 'Editar Regra Automática' : 'Criar Nova Regra'),
        backgroundColor: Colors.orange[700],
        foregroundColor: Colors.white,
      ),
      body: _loadingState['page']!
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBasicInfoSection(),
                    _buildTriggerAndScopeSection(),
                    _buildConditionSection(),
                    _buildActionSection(),
                    const SizedBox(height: 32),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
    );
  }
}
