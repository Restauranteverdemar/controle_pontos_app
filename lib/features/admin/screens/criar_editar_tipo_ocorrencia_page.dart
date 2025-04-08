import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para input formatters
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Para pegar UID do admin
import '../../shared/models/incident_type.dart'; // Modelo IncidentType

class CriarEditarTipoOcorrenciaPage extends StatefulWidget {
  final IncidentType? incidentType;

  const CriarEditarTipoOcorrenciaPage({super.key, this.incidentType});

  @override
  State<CriarEditarTipoOcorrenciaPage> createState() =>
      _CriarEditarTipoOcorrenciaPageState();
}

class _CriarEditarTipoOcorrenciaPageState
    extends State<CriarEditarTipoOcorrenciaPage> {
  // Constantes
  static const double _espacamentoVertical = 16.0;
  static const double _espacamentoVerticalMaior = 24.0;
  static const double _paddingTela = 16.0;
  // <<< ADICIONADO: Lista de departamentos disponíveis >>>
  final List<String> _availableDepartments = ['Cozinha', 'Salão'];

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _pointsController;
  late TextEditingController _descriptionController;
  late bool _isActive;
  // <<< ADICIONADO: Estado para controlar os departamentos selecionados >>>
  // Usar Set garante que não haverá duplicatas
  late Set<String> _selectedDepartments;

  bool _isLoading = false;
  bool _formSubmitted = false;
  bool get _isEditing => widget.incidentType != null;

  // MELHORADO: Adicionada referência ao Firestore e Auth como propriedades para evitar repetição
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    final type = widget.incidentType;

    _nameController = TextEditingController(text: type?.name ?? '');
    _pointsController = TextEditingController(
        text: type?.defaultPoints != null ? '${type!.defaultPoints}' : '0');
    _descriptionController =
        TextEditingController(text: type?.description ?? '');
    _isActive = type?.isActive ?? true;

    // <<< ADICIONADO: Inicializa os departamentos selecionados >>>
    if (_isEditing && type != null) {
      // Se editando, carrega os departamentos existentes do tipo
      // Garante que sejam apenas os departamentos válidos conhecidos pela UI
      _selectedDepartments = Set<String>.from(type.applicableDepartments
          .where((dep) => _availableDepartments.contains(dep)));
      // Se por algum motivo a lista salva estiver vazia (dados antigos/inválidos), seleciona todos por segurança
      if (_selectedDepartments.isEmpty) {
        _selectedDepartments = Set<String>.from(_availableDepartments);
      }
    } else {
      // Se criando, seleciona todos os departamentos por padrão
      _selectedDepartments = Set<String>.from(_availableDepartments);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pointsController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // --- Validações ---
  String? _validarNome(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'O nome é obrigatório';
    }
    if (value.trim().length < 3) {
      return 'O nome deve ter pelo menos 3 caracteres.';
    }
    if (value.trim().length > 50) {
      return 'O nome deve ter no máximo 50 caracteres';
    }
    return null;
  }

  Future<bool> _isNameDuplicate(String name, String? currentDocId) async {
    if (name.trim().isEmpty) return false;

    // MELHORADO: Usando a referência de classe em vez de chamar FirebaseFirestore.instance novamente
    var query = _firestore
        .collection('incidentTypes')
        .where('name', isEqualTo: name.trim());

    if (currentDocId != null) {
      query = query.where(FieldPath.documentId, isNotEqualTo: currentDocId);
    }
    final querySnapshot = await query.limit(1).get();
    return querySnapshot.docs.isNotEmpty;
  }

  Future<bool> _confirmExtremePoints(int points) async {
    const limite = 100;
    if (points.abs() <= limite) return true;
    if (!mounted) return false;

    // MELHORADO: Adicionada verificação null explícita para evitar o operador de coalescência nula
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(
          points < 0 ? Icons.warning : Icons.info,
          color: points < 0 ? Colors.red : Colors.orange,
        ),
        title: const Text('Pontuação Extrema'),
        content: Text(
            'A pontuação ($points) parece ${points < 0 ? 'baixa' : 'alta'}. Tem certeza?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    return confirm ?? false;
  }

  // --- Funções Auxiliares ---
  void _mostrarMensagem(String mensagem, Color cor) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                cor == Colors.green
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(mensagem)),
            ],
          ),
          backgroundColor: cor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // --- LÓGICA PARA SALVAR ---
  Future<void> _salvarTipoOcorrencia() async {
    setState(() {
      _formSubmitted = true;
    });

    if (!(_formKey.currentState?.validate() ?? false)) {
      _mostrarMensagem("Por favor, corrija os erros no formulário.",
          Colors.orange); // Avisa sobre validação
      return;
    }

    // <<< ADICIONADO: Validação para garantir que pelo menos um departamento foi selecionado >>>
    if (_selectedDepartments.isEmpty) {
      _mostrarMensagem(
          "Selecione pelo menos um departamento aplicável.", Colors.orange);
      return; // Impede o salvamento
    }

    setState(() {
      _isLoading = true;
    });

    final name = _nameController.text.trim();
    final pointsText = _pointsController.text.trim();

    // MELHORADO: Verificação explícita para garantir que o valor é um número válido
    final int? parsedPoints = int.tryParse(pointsText);
    if (parsedPoints == null) {
      _mostrarMensagem('Valor de pontos inválido', Colors.red);
      setState(() {
        _isLoading = false;
      });
      return;
    }
    final points = parsedPoints;
    final description = _descriptionController.text.trim();

    // MELHORADO: Usando a referência de classe em vez de chamar FirebaseAuth.instance novamente
    final user = _auth.currentUser;

    if (user == null) {
      _mostrarMensagem('Erro: Usuário não autenticado.', Colors.red);
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final currentId = widget.incidentType?.id;
      final isDuplicate = await _isNameDuplicate(name, currentId);
      if (isDuplicate) {
        _mostrarMensagem(
            'Erro: Já existe um tipo com o nome "$name".', Colors.orange);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      if (!await _confirmExtremePoints(points)) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // <<< MODIFICADO: Inclui a lista de departamentos selecionados >>>
      final dataToSave = <String, dynamic>{
        'name': name,
        'defaultPoints': points,
        'description': description.isEmpty ? null : description,
        'isActive': _isActive,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': _isEditing
            ? (widget.incidentType?.createdBy ?? user.uid)
            : user.uid,
        // Converte o Set para List antes de salvar
        'applicableDepartments': _selectedDepartments.toList(),
      };

      if (!_isEditing) {
        dataToSave['createdAt'] = FieldValue.serverTimestamp();
      }

      // MELHORADO: Usando a referência de classe em vez de chamar FirebaseFirestore.instance novamente
      final incidentTypesCollection = _firestore.collection('incidentTypes');
      final scaffoldMessenger =
          ScaffoldMessenger.of(context); // Captura antes do await
      final navigator = Navigator.of(context); // Captura antes do await

      if (_isEditing) {
        await incidentTypesCollection
            .doc(widget.incidentType!.id)
            .update(dataToSave);
        if (!mounted) return; // Verifica se ainda está montado após await
        scaffoldMessenger.showSnackBar(const SnackBar(
            content: Text('Tipo de ocorrência atualizado com sucesso!'),
            backgroundColor: Colors.green));
      } else {
        await incidentTypesCollection.add(dataToSave);
        if (!mounted) return; // Verifica se ainda está montado após await
        scaffoldMessenger.showSnackBar(const SnackBar(
            content: Text('Tipo de ocorrência criado com sucesso!'),
            backgroundColor: Colors.green));
      }

      if (mounted) {
        // Verifica novamente antes de navegar
        navigator.pop();
      }
    } on FirebaseException catch (e) {
      debugPrint("Erro Firebase: ${e.code} - ${e.message}");
      _mostrarMensagem('Erro ao salvar: ${e.message}', Colors.red);
    } catch (e) {
      debugPrint("Erro inesperado: $e");
      _mostrarMensagem('Ocorreu um erro inesperado: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isEditing ? 'Editar Tipo de Ocorrência' : 'Criar Novo Tipo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt_outlined),
            onPressed: _isLoading ? null : _salvarTipoOcorrencia,
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(_paddingTela),
        child: Form(
          key: _formKey,
          autovalidateMode: _formSubmitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: _espacamentoVertical),
            physics: const BouncingScrollPhysics(),
            children: [
              // --- Campo Nome ---
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nome do Tipo*',
                  hintText: 'Ex: Atraso Leve, Bônus por Meta',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0)),
                  prefixIcon: const Icon(Icons.label_outline),
                  // Removido prefixText e suffixText para simplificar
                ),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
                validator: _validarNome,
              ),
              const SizedBox(height: _espacamentoVertical),

              // --- Campo Pontos ---
              TextFormField(
                controller: _pointsController,
                decoration: InputDecoration(
                  labelText: 'Pontos Padrão*',
                  hintText: 'Ex: -5 ou 10',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0)),
                  prefixIcon: const Icon(Icons.star_half_outlined),
                  // Removido suffixText
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(signed: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                ],
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
                validator: (value) {
                  if (value == null || value.trim().isEmpty)
                    return 'Os pontos são obrigatórios';
                  if (value.trim() == '-')
                    return 'Digite um número após o sinal';
                  final number = int.tryParse(value.trim());
                  if (number == null)
                    return 'Valor inválido (deve ser um número inteiro)';
                  return null;
                },
              ),
              const SizedBox(height: _espacamentoVertical),

              // --- Campo Descrição ---
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Descrição (Opcional)',
                  hintText: 'Detalhes sobre quando aplicar este tipo...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0)),
                  prefixIcon: const Icon(Icons.description_outlined),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.newline,
                enabled: !_isLoading,
                maxLength: 200,
              ),
              const SizedBox(height: _espacamentoVertical),

              // <<< ADICIONADO: Seção de Seleção de Departamentos >>>
              Text(
                'Aplicável aos Departamentos*', // Asterisco indica obrigatoriedade
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: _espacamentoVertical / 2), // Espaço menor

              // MELHORADO: Extraída a lógica de construção dos chips para um método separado
              _buildDepartmentChips(colorScheme, theme),

              // Exibe um aviso se nenhum departamento estiver selecionado após a tentativa de salvar
              if (_formSubmitted && _selectedDepartments.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    'Selecione pelo menos um departamento.',
                    style:
                        TextStyle(color: theme.colorScheme.error, fontSize: 12),
                  ),
                ),
              const SizedBox(
                  height: _espacamentoVertical), // Espaço antes do switch

              // --- Switch Ativo/Inativo ---
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ativo',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_isActive
                    ? 'Visível para novas ocorrências.'
                    : 'Oculto para novas ocorrências.'),
                value: _isActive,
                onChanged: _isLoading
                    ? null
                    : (bool value) {
                        setState(() {
                          _isActive = value;
                        });
                      },
                activeColor: Colors.green,
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.grey.shade300,
                secondary: Icon(
                  _isActive
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  color: _isActive ? Colors.green : Colors.grey,
                ),
              ),
              const SizedBox(height: _espacamentoVerticalMaior),

              // --- Botão Salvar ---
              _isLoading
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ))
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.save_alt_outlined),
                      label:
                          Text(_isEditing ? 'Salvar Alterações' : 'Criar Tipo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        textStyle: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _isLoading ? null : _salvarTipoOcorrencia,
                    ),
              const SizedBox(height: _espacamentoVertical),
            ],
          ),
        ),
      ),
    );
  }

  // MELHORADO: Método para construir os chips de seleção de departamentos
  // Extrai a lógica de dentro do método build para melhorar a legibilidade
  Widget _buildDepartmentChips(ColorScheme colorScheme, ThemeData theme) {
    return Wrap(
      spacing: 8.0, // Espaço horizontal entre os chips
      runSpacing: 4.0, // Espaço vertical entre as linhas de chips
      children: _availableDepartments.map((department) {
        final bool isSelected = _selectedDepartments.contains(department);
        return ChoiceChip(
          label: Text(department),
          selected: isSelected,
          onSelected: _isLoading
              ? null
              : (selected) {
                  // Desabilita se estiver carregando
                  setState(() {
                    if (selected) {
                      _selectedDepartments.add(department);
                    } else {
                      // Não permite desmarcar o último chip selecionado
                      if (_selectedDepartments.length > 1) {
                        _selectedDepartments.remove(department);
                      } else {
                        // Opcional: mostrar mensagem que pelo menos 1 deve ser selecionado
                        _mostrarMensagem(
                            "Pelo menos um departamento deve ser selecionado.",
                            Colors.orange);
                      }
                    }
                  });
                },
          selectedColor: colorScheme.primaryContainer, // Cor quando selecionado
          checkmarkColor: colorScheme.onPrimaryContainer, // Cor do checkmark
          labelStyle: TextStyle(
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : theme.textTheme.bodyLarge?.color,
          ),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
              side: BorderSide(
                color: isSelected ? colorScheme.primary : Colors.grey.shade400,
                width: 1,
              )),
          backgroundColor: Colors.grey.shade100, // Cor de fundo padrão
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        );
      }).toList(),
    );
  }
}
