// lib/features/admin/screens/registro_ocorrencia_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Imports do projeto
import '../../shared/models/employee.dart';
import '../../shared/models/incident_type.dart';
import 'controllers/registro_ocorrencia_controller.dart';

/// Tela para registro de novas ocorrências por administradores
class RegistroOcorrenciaPage extends StatefulWidget {
  const RegistroOcorrenciaPage({Key? key}) : super(key: key);

  @override
  _RegistroOcorrenciaPageState createState() => _RegistroOcorrenciaPageState();
}

class _RegistroOcorrenciaPageState extends State<RegistroOcorrenciaPage> {
  // Constantes
  static const double _defaultPadding = 16.0;
  static const double _fieldSpacing = 16.0;
  static const double _largeSpacing = 20.0;
  static const double _sectionSpacing = 32.0;
  static const int _maxImageSizeInBytes = 5 * 1024 * 1024; // 5 MB
  static const int _maxVideoSizeInBytes = 15 * 1024 * 1024; // 15 MB
  static const Duration _snackBarDuration = Duration(seconds: 3);
  static const Duration _maxFutureDate = Duration(minutes: 5);
  static const int _maxPastYears = 2;

  // Chaves e controladores
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _pointsController = TextEditingController();

  // Serviços
  final _auth = FirebaseAuth.instance;
  final _picker = ImagePicker();
  final _dateFormatter = DateFormat('dd/MM/yyyy HH:mm');

  // Estado do formulário
  Employee? _selectedEmployee;
  IncidentType? _selectedIncidentType;
  DateTime? _selectedOccurrenceDate;
  final List<XFile> _mediaFiles = [];

  // Flags de estado
  bool _isLoading = false;
  bool _isSaving = false;
  bool _hasInitialized = false; // Flag para controlar inicialização

  // Referência ao Controller
  late RegistroOcorrenciaController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_initializeAfterFrame);
  }

  void _initializeAfterFrame(_) {
    if (!mounted) return;

    debugPrint("_initializeAfterFrame chamado");

    // Obtém o controller
    _controller =
        Provider.of<RegistroOcorrenciaController>(context, listen: false);
    _selectedOccurrenceDate = DateTime.now();

    // Registra listener para debug
    _controller.addListener(_onControllerChanged);

    // Sempre carregamos os dados iniciais, a menos que já tenhamos inicializado
    if (!_hasInitialized) {
      debugPrint("Iniciando carregamento de dados iniciais...");
      _loadInitialData();
    } else {
      debugPrint("Skip: A página já foi inicializada anteriormente");
    }
  }

  void _onControllerChanged() {
    // Debug para acompanhar mudanças no controller
    if (mounted) {
      debugPrint(
          "Controller mudou - funcionários: ${_controller.employees.length}, tipos: ${_controller.allIncidentTypes.length}, tipos filtrados: ${_controller.incidentTypesFiltered.length}");
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _pointsController.dispose();
    // Remove o listener ao descartar a página
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// Carrega dados iniciais com verificações adicionais
  Future<void> _loadInitialData() async {
    if (!mounted) return;

    debugPrint("_loadInitialData iniciado");
    setState(() => _isLoading = true);

    try {
      // Inicializa o controller
      await _controller.initialize();

      // Verificação adicional: se depois de initialize(), os funcionários ainda estiverem vazios,
      // forçamos o carregamento explícito
      if (_controller.employees.isEmpty) {
        debugPrint(
            "Após initialize(), a lista de funcionários ainda está vazia. Forçando carregamento explícito...");
        await _controller.loadEmployees();
      }

      if (_controller.allIncidentTypes.isEmpty) {
        debugPrint(
            "Após initialize(), a lista de tipos ainda está vazia. Forçando carregamento explícito...");
        await _controller.loadIncidentTypes();
      }

      debugPrint(
          "Dados iniciais carregados com sucesso. Funcionários: ${_controller.employees.length}, Tipos: ${_controller.allIncidentTypes.length}");

      // Marcamos que a inicialização foi bem-sucedida
      _hasInitialized = true;
    } catch (e, stackTrace) {
      debugPrint('Erro ao carregar dados iniciais: $e\n$stackTrace');
      _showSnackBar('Erro ao carregar dados: $e', isError: true);

      // Não marcamos como inicializado se falhou
      _hasInitialized = false;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Recarrega explicitamente os tipos de ocorrência
  Future<void> _reloadIncidentTypes() async {
    if (!mounted || _isSaving) return;

    setState(() => _isLoading = true);
    try {
      debugPrint("Forçando recarregamento de tipos de ocorrência...");
      await _controller.loadIncidentTypes();
      debugPrint(
          "Tipos de ocorrência recarregados. Total: ${_controller.allIncidentTypes.length}");

      // Se um funcionário estiver selecionado, filtra os tipos novamente
      if (_selectedEmployee != null && _selectedEmployee?.department != null) {
        debugPrint(
            "Refiltrando tipos para departamento: ${_selectedEmployee?.department}");
        _controller.filterIncidentTypes(_selectedEmployee!.department);
      }
    } catch (e) {
      debugPrint('Erro ao recarregar tipos de ocorrência: $e');
      _showSnackBar('Erro ao recarregar tipos: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Carrega ou recarrega todos os dados
  Future<void> _reloadAllData() async {
    if (!mounted || _isSaving) return;

    setState(() => _isLoading = true);
    try {
      debugPrint("Recarregando todos os dados...");

      // Reinicializamos o controller completamente
      await _controller.initialize();

      // Verificações adicionais após a inicialização
      if (_controller.employees.isEmpty) {
        debugPrint(
            "Forçando carregamento de funcionários após reinicialização...");
        await _controller.loadEmployees();
      }

      debugPrint(
          "Dados recarregados. Funcionários: ${_controller.employees.length}, Tipos: ${_controller.allIncidentTypes.length}");

      // Reaplica filtro se necessário
      if (_selectedEmployee != null && _selectedEmployee?.department != null) {
        _controller.filterIncidentTypes(_selectedEmployee!.department);
      }
    } catch (e) {
      debugPrint('Erro ao recarregar todos os dados: $e');
      _showSnackBar('Erro ao recarregar dados: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade700 : null,
          duration: _snackBarDuration,
        ),
      );
  }

  Future<void> _selectOccurrenceDate() async {
    if (_isSaving) return;

    final DateTime initialDate = _selectedOccurrenceDate ?? DateTime.now();
    final DateTime now = DateTime.now();

    // Mostra o DatePicker
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - _maxPastYears),
      lastDate: now.add(_maxFutureDate),
      locale: const Locale('pt', 'BR'),
    );

    if (pickedDate == null || !mounted) return;

    // Mostra o TimePicker
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );

    if (pickedTime == null || !mounted) return;

    // Combina data e hora selecionadas
    setState(() {
      _selectedOccurrenceDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  void _showMediaSourceActionSheet() {
    if (_isSaving) return;

    void _handleMediaSelection(ImageSource source, bool isVideo) {
      Navigator.of(context).pop();
      isVideo ? _pickVideo(source) : _pickImage(source);
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            _buildActionSheetItem(
              icon: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher Foto da Galeria'),
              onTap: () => _handleMediaSelection(ImageSource.gallery, false),
            ),
            _buildActionSheetItem(
              icon: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tirar Foto'),
              onTap: () => _handleMediaSelection(ImageSource.camera, false),
            ),
            _buildActionSheetItem(
              icon: const Icon(Icons.video_library_outlined),
              title: const Text('Escolher Vídeo da Galeria'),
              onTap: () => _handleMediaSelection(ImageSource.gallery, true),
            ),
            _buildActionSheetItem(
              icon: const Icon(Icons.videocam_outlined),
              title: const Text('Gravar Vídeo'),
              onTap: () => _handleMediaSelection(ImageSource.camera, true),
            ),

            // Opção de remover só aparece se houver anexos
            if (_mediaFiles.isNotEmpty) const Divider(height: 1),
            if (_mediaFiles.isNotEmpty)
              _buildActionSheetItem(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                title: Text('Remover Todos os Anexos',
                    style: TextStyle(color: Colors.red.shade700)),
                onTap: () {
                  Navigator.of(context).pop();
                  if (mounted) {
                    setState(() => _mediaFiles.clear());
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionSheetItem({
    required Widget icon,
    required Widget title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: icon,
      title: title,
      onTap: onTap,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1080,
      );

      if (pickedFile == null || !mounted) return;

      await _validateAndAddFile(
          pickedFile, _maxImageSizeInBytes, 'imagem', 'MB');
    } catch (e, stackTrace) {
      debugPrint('Erro ao selecionar imagem ($source): $e\n$stackTrace');
      _showSnackBar(
          'Erro ao acessar a ${source == ImageSource.camera ? "câmera" : "galeria"}: $e',
          isError: true);
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 1),
      );

      if (pickedFile == null || !mounted) return;

      await _validateAndAddFile(
          pickedFile, _maxVideoSizeInBytes, 'vídeo', 'MB');
    } catch (e, stackTrace) {
      debugPrint('Erro ao selecionar vídeo ($source): $e\n$stackTrace');
      _showSnackBar(
          'Erro ao acessar a ${source == ImageSource.camera ? "câmera" : "galeria"}: $e',
          isError: true);
    }
  }

  Future<void> _validateAndAddFile(
      XFile file, int maxSizeBytes, String fileType, String sizeUnit) async {
    final fileSize = await file.length();
    final fileSizeFormatted = (fileSize / (1024 * 1024)).toStringAsFixed(2);
    final maxSizeFormatted = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(0);

    debugPrint(
        "$fileType selecionado: ${file.path}, Tamanho: $fileSize bytes ($fileSizeFormatted $sizeUnit)");

    if (fileSize > maxSizeBytes) {
      _showSnackBar(
        'Erro: O $fileType selecionado ($fileSizeFormatted $sizeUnit) excede o limite de $maxSizeFormatted $sizeUnit.',
        isError: true,
      );
      return;
    }

    // Adiciona à lista SE passou na verificação
    setState(() {
      _mediaFiles.add(file);
    });
  }

  bool _validateForm() {
    // Validação do formulário (TextFormField, DropdownButtonFormField)
    if (!(_formKey.currentState?.validate() ?? false)) {
      _showSnackBar('Verifique os campos obrigatórios marcados.',
          isError: true);
      return false;
    }

    if (_selectedEmployee == null) {
      _showSnackBar('Selecione o Funcionário.', isError: true);
      return false;
    }

    if (_selectedIncidentType == null) {
      _showSnackBar('Selecione o Tipo de Ocorrência.', isError: true);
      return false;
    }

    if (_selectedOccurrenceDate == null) {
      _showSnackBar('Selecione a Data e Hora da Ocorrência.', isError: true);
      return false;
    }

    // Validação de pontos (número ou vazio/nulo)
    final pointsText = _pointsController.text.trim();
    if (pointsText.isNotEmpty && int.tryParse(pointsText) == null) {
      _showSnackBar('O valor no campo de pontos não é um número válido.',
          isError: true);
      return false;
    }

    return true;
  }

  // NOVO: Método para resetar o formulário (substitui o Navigator.pop)
  void _resetForm() {
    setState(() {
      _selectedEmployee = null;
      _selectedIncidentType = null;
      _selectedOccurrenceDate = DateTime.now();
      _notesController.clear();
      _pointsController.clear();
      _mediaFiles.clear();
    });

    // Limpa seleções no controller
    _controller.resetFormSelection();

    // Importante: Recarregar os funcionários caso tenha alterações
    if (_controller.employees.isEmpty) {
      _loadInitialData();
    }
  }

  Future<void> _saveOccurrence() async {
    if (!_validateForm()) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _showSnackBar(
          'Erro crítico: Administrador não autenticado. Faça login novamente.',
          isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      final success = await _controller.registerOccurrence(
        employee: _selectedEmployee!,
        incidentType: _selectedIncidentType!,
        occurrenceDate: _selectedOccurrenceDate!,
        notes: _notesController.text.trim(),
        manualPointsAdjustment: int.tryParse(_pointsController.text.trim()),
        adminUser: currentUser,
        mediaFiles: _mediaFiles.isNotEmpty ? _mediaFiles : null,
      );

      if (!mounted) return;

      if (success) {
        _showSnackBar('Ocorrência registrada com sucesso!');
        // MODIFICADO: Em vez de sair da tela, resetar o formulário
        _resetForm(); // Antes era Navigator.of(context).pop();
      } else {
        // Usa a mensagem de erro específica do controller ou uma genérica
        final errorMsg = _controller.errorMessage ??
            'Falha ao registrar ocorrência. Verifique os dados ou tente novamente.';
        _showSnackBar(errorMsg, isError: true);
      }
    } catch (e, stackTrace) {
      debugPrint('Erro ao salvar ocorrência (UI): $e\n$stackTrace');
      _showSnackBar('Erro inesperado ao salvar: ${e.toString()}',
          isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Captura os dados do controller com context.watch
    final employees = context.watch<RegistroOcorrenciaController>().employees;
    final incidentTypes =
        context.watch<RegistroOcorrenciaController>().incidentTypesFiltered;
    final allIncidentTypes =
        context.watch<RegistroOcorrenciaController>().allIncidentTypes;
    final adminName = context.watch<RegistroOcorrenciaController>().adminName;
    final isControllerLoading =
        context.watch<RegistroOcorrenciaController>().isLoading;
    final isFetchingInitial =
        context.watch<RegistroOcorrenciaController>().isFetchingInitialData;
    final errorMessage =
        context.watch<RegistroOcorrenciaController>().errorMessage;

    // Combina os loadings para uma única variável de UI
    final showLoadingIndicator =
        _isLoading || isControllerLoading || isFetchingInitial;

    // Log para debug a cada reconstrução
    debugPrint(
        "Build chamado - Funcionários: ${employees.length}, Tipos filtrados: ${incidentTypes.length}, Todos tipos: ${allIncidentTypes.length}");

    return Scaffold(
      appBar: _buildAppBar(showLoadingIndicator),
      body: _buildBody(
        showLoadingIndicator: showLoadingIndicator,
        isFetchingInitial: isFetchingInitial,
        errorMessage: errorMessage,
        employees: employees,
        incidentTypes: incidentTypes,
        allIncidentTypes: allIncidentTypes,
        adminName: adminName,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool showLoadingIndicator) {
    return AppBar(
      title: const Text('Registrar Ocorrência'),
      actions: [
        // Botão para recarregar todos os dados
        if (!showLoadingIndicator)
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Recarregar todos os dados',
            onPressed: _reloadAllData,
          ),

        // Botão para recarregar só os tipos
        if (!showLoadingIndicator)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar tipos de ocorrência',
            onPressed: _reloadIncidentTypes,
          ),
      ],
    );
  }

  Widget _buildBody({
    required bool showLoadingIndicator,
    required bool isFetchingInitial,
    required String? errorMessage,
    required List<Employee> employees,
    required List<IncidentType> incidentTypes,
    required List<IncidentType> allIncidentTypes,
    required String? adminName,
  }) {
    return Stack(
      children: [
        // Conteúdo principal (formulário ou mensagem de erro)
        if (errorMessage != null && !isFetchingInitial)
          _buildErrorState(errorMessage)
        else if (!isFetchingInitial)
          _buildFormContent(
            employees: employees,
            incidentTypes: incidentTypes,
            allIncidentTypes: allIncidentTypes,
            adminName: adminName,
          )
        else
          const Center(child: CircularProgressIndicator()),

        // Loading Overlay
        if ((_isSaving || _isLoading) && !isFetchingInitial)
          Container(
            color: Colors.black.withOpacity(0.1),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildFormContent({
    required List<Employee> employees,
    required List<IncidentType> incidentTypes,
    required List<IncidentType> allIncidentTypes,
    required String? adminName,
  }) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(_defaultPadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Contador de tipos de ocorrência (para debug)
              if (employees.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'Funcionários: ${employees.length}, Tipos (Total): ${allIncidentTypes.length}, Tipos (Filtrados): ${incidentTypes.length}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              _buildEmployeeDropdown(employees),
              const SizedBox(height: _fieldSpacing),
              _buildIncidentTypeDropdown(incidentTypes),
              const SizedBox(height: _fieldSpacing),
              _buildDateTimePicker(),
              const SizedBox(height: _fieldSpacing),
              _buildNotesField(),
              const SizedBox(height: _fieldSpacing),
              _buildPointsField(),
              const SizedBox(height: _largeSpacing),
              _buildAttachmentSection(),
              const SizedBox(height: _sectionSpacing),
              _buildSaveButton(),
              const SizedBox(height: 12),

              // Exibe nome do admin logado
              if (adminName != null && adminName.isNotEmpty)
                Center(
                  child: Text(
                    'Registrando como: $adminName',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey.shade600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String errorMessage) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      color: Colors.red.shade50,
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  errorMessage,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed:
                _reloadAllData, // Usa o método completo de recarregamento
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeDropdown(List<Employee> employees) {
    debugPrint("Construindo dropdown com ${employees.length} funcionários");

    return DropdownButtonFormField<Employee>(
      value: _selectedEmployee,
      hint: const Text('Selecione o Funcionário'),
      isExpanded: true,
      items: employees.map((employee) {
        final String departmentInfo =
            _formatDepartmentInfo(employee.department);
        final String displayText =
            (employee.displayName ?? 'Funcionário sem nome') + departmentInfo;

        return DropdownMenuItem<Employee>(
          value: employee,
          child: Text(
            displayText,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: _isSaving
          ? null
          : (employee) {
              if (employee == null) return;

              setState(() {
                _selectedEmployee = employee;
                // Limpa tipo e pontos ao mudar funcionário
                _selectedIncidentType = null;
                _pointsController.text = '';
              });

              // Notifica o controller DEPOIS de atualizar o estado local
              _controller.selectEmployee(employee);
            },
      validator: (value) => value == null ? 'Selecione um funcionário' : null,
      decoration: const InputDecoration(
        labelText: 'Funcionário *',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person_search_outlined),
      ),
    );
  }

  String _formatDepartmentInfo(String? department) {
    return department != null && department.isNotEmpty
        ? " (${department})"
        : " (Sem Depto)";
  }

  Widget _buildIncidentTypeDropdown(List<IncidentType> incidentTypes) {
    // Verifica se o dropdown deve estar habilitado
    final bool isEnabled =
        _selectedEmployee != null && incidentTypes.isNotEmpty && !_isSaving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<IncidentType>(
          value: _selectedIncidentType,
          hint: Text(_selectedEmployee == null
              ? 'Selecione um funcionário primeiro'
              : 'Selecione o Tipo'),
          isExpanded: true,
          items: incidentTypes.map((type) {
            return DropdownMenuItem<IncidentType>(
              value: type,
              child: Text(type.name ?? 'Tipo sem nome',
                  overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: isEnabled
              ? (type) {
                  if (type == null) return;
                  setState(() {
                    _selectedIncidentType = type;
                    // MODIFICADO: Inicializar com 0 em vez do valor padrão
                    _pointsController.text =
                        '0'; // Antes era (type.defaultPoints).toString()
                  });
                  // Notifica o controller se necessário
                  _controller.selectIncidentType(type);
                }
              : null,
          validator: (value) => value == null ? 'Selecione um tipo' : null,
          decoration: InputDecoration(
            labelText: 'Tipo de Ocorrência *',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.assignment_late_outlined),
            enabled: isEnabled,
            filled: !isEnabled,
            fillColor: Colors.grey.shade100,
            helperText: _getHelperTextForIncidentType(incidentTypes),
            helperStyle: TextStyle(color: Colors.grey.shade600),
          ),
        ),

        if (_shouldShowNoTypesWarning(incidentTypes))
          _buildNoIncidentTypesWarning(),

        // Mensagem se não houver tipos cadastrados no total
        if (_controller.allIncidentTypes.isEmpty &&
            !_isLoading &&
            !_controller.isFetchingInitialData)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Nenhum tipo de ocorrência cadastrado no sistema.',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ),
      ],
    );
  }

  bool _shouldShowNoTypesWarning(List<IncidentType> incidentTypes) {
    return _selectedEmployee != null &&
        incidentTypes.isEmpty &&
        _controller.allIncidentTypes.isNotEmpty;
  }

  Widget _buildNoIncidentTypesWarning() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nenhum tipo de ocorrência ativo encontrado para o departamento "${_selectedEmployee?.department ?? 'N/A'}".',
            style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: _isSaving ? null : _reloadIncidentTypes,
            child: Text(
              'Verificar tipos novamente ou cadastrar um novo tipo aplicável.',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getHelperTextForIncidentType(List<IncidentType> incidentTypes) {
    if (_selectedEmployee == null) {
      return 'Selecione um funcionário primeiro';
    } else if (incidentTypes.isEmpty &&
        _controller.allIncidentTypes.isNotEmpty) {
      return 'Nenhum tipo ativo para "${_selectedEmployee?.department ?? 'N/A'}"';
    } else if (_controller.allIncidentTypes.isEmpty) {
      return 'Cadastre tipos de ocorrência primeiro';
    }
    return 'Tipos aplicáveis a "${_selectedEmployee?.department ?? 'N/A'}"';
  }

  Widget _buildDateTimePicker() {
    return InkWell(
      onTap: _isSaving ? null : _selectOccurrenceDate,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Data e Hora da Ocorrência *',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.event_available),
          filled: _isSaving,
          fillColor: _isSaving ? Colors.grey.shade100 : null,
        ),
        child: Text(
          _selectedOccurrenceDate != null
              ? _dateFormatter.format(_selectedOccurrenceDate!)
              : 'Selecione a data e hora',
          style: TextStyle(
            color: _selectedOccurrenceDate == null
                ? Theme.of(context).hintColor
                : Theme.of(context).textTheme.titleMedium?.color,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      enabled: !_isSaving,
      decoration: InputDecoration(
        labelText: 'Observações (Opcional)',
        hintText: 'Detalhes adicionais, justificativas...',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.description_outlined),
        filled: _isSaving,
        fillColor: _isSaving ? Colors.grey.shade100 : null,
      ),
      maxLines: 3,
      minLines: 1,
      textCapitalization: TextCapitalization.sentences,
    );
  }

  Widget _buildPointsField() {
    final String defaultPointsText = _selectedIncidentType != null
        ? 'Padrão: ${_selectedIncidentType!.defaultPoints}'
        : 'Padrão: N/A';

    return TextFormField(
      controller: _pointsController,
      enabled: !_isSaving,
      decoration: InputDecoration(
        labelText: 'Pontos Finais ($defaultPointsText)',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.control_point_duplicate_rounded),
        helperText: 'Altere apenas se necessário um valor diferente do padrão.',
        filled: _isSaving,
        fillColor: _isSaving ? Colors.grey.shade100 : null,
      ),
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      validator: (value) {
        // Permite campo vazio (usará o padrão)
        if (value == null || value.trim().isEmpty) {
          if (_selectedIncidentType == null) {
            return 'Selecione um tipo primeiro ou digite os pontos.';
          }
          return null; // Vazio é ok se tipo selecionado
        }
        // Se não está vazio, valida se é um número inteiro
        if (int.tryParse(value.trim()) == null) {
          return 'Digite um número inteiro válido (ex: -5, 0, 10)';
        }
        return null; // Válido se for número
      },
    );
  }

  Widget _buildAttachmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Anexos (Comprovantes Opcionais)',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),

        // NOVO: Opção de compressão
        _buildCompressaoToggle(),
        const SizedBox(height: 12),

        OutlinedButton.icon(
          icon: Icon(
            _mediaFiles.isEmpty
                ? Icons.attach_file_outlined
                : Icons.collections_outlined,
            color: _mediaFiles.isNotEmpty ? Colors.blue.shade700 : null,
          ),
          label: Text(
            _mediaFiles.isEmpty
                ? 'Adicionar Imagem ou Vídeo'
                : 'Gerenciar Anexos (${_mediaFiles.length})',
          ),
          onPressed: _isSaving ? null : _showMediaSourceActionSheet,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(
              color: _isSaving
                  ? Colors.grey.shade400
                  : Theme.of(context).colorScheme.primary.withOpacity(0.8),
            ),
            foregroundColor: _isSaving
                ? Colors.grey.shade600
                : Theme.of(context).colorScheme.primary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        // Lista de pré-visualização dos anexos
        if (_mediaFiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildMediaFilesList(),
        ],

        // NOVO: Informações sobre tamanhos permitidos
        const SizedBox(height: 8),
        _buildLimitesInfo(),
      ],
    );
  }

  // NOVO: Widget para toggle de compressão
  Widget _buildCompressaoToggle() {
    final isCompressaoAtivada =
        context.watch<RegistroOcorrenciaController>().compressaoAtivada;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Compressão de anexos',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                isCompressaoAtivada
                    ? 'Ativada: os arquivos serão comprimidos automaticamente'
                    : 'Desativada: os arquivos originais serão enviados',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: isCompressaoAtivada,
          onChanged: _isSaving
              ? null
              : (value) {
                  _controller.compressaoAtivada = value;
                },
          activeColor: Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }

  // NOVO: Widget para mostrar informações sobre limites
  Widget _buildLimitesInfo() {
    final isCompressaoAtivada =
        context.watch<RegistroOcorrenciaController>().compressaoAtivada;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Limites de tamanho:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '• Imagens: até 5 MB ${isCompressaoAtivada ? "(com compressão)" : "(sem compressão)"}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          Text(
            '• Vídeos: até 15 MB ${isCompressaoAtivada ? "(com compressão)" : "(sem compressão)"}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          if (!isCompressaoAtivada) ...[
            const SizedBox(height: 4),
            Text(
              'Dica: ative a compressão para enviar arquivos maiores.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMediaFilesList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _mediaFiles.length,
      separatorBuilder: (_, __) => const Divider(height: 4, thickness: 0.5),
      itemBuilder: (context, index) {
        final file = _mediaFiles[index];
        final isVideo = _isVideoFile(file.path);
        final fileName = _getFileName(file.path);

        return _buildMediaFileItem(
          isVideo: isVideo,
          fileName: fileName,
          onRemove: () {
            if (!_isSaving && mounted) {
              setState(() => _mediaFiles.removeAt(index));
            }
          },
        );
      },
    );
  }

  Widget _buildMediaFileItem({
    required bool isVideo,
    required String fileName,
    required VoidCallback onRemove,
  }) {
    return ListTile(
      leading: Icon(
        isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        color: isVideo ? Colors.purple.shade700 : Colors.indigo.shade700,
        size: 30,
      ),
      title: Text(
        fileName,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        isVideo ? 'Vídeo' : 'Imagem',
        style: TextStyle(
          fontSize: 12,
          color: isVideo ? Colors.purple.shade700 : Colors.indigo.shade700,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: IconButton(
        icon: Icon(Icons.close, color: Colors.red.shade600, size: 20),
        onPressed: _isSaving ? null : onRemove,
        tooltip: 'Remover anexo',
        visualDensity: VisualDensity.compact,
      ),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8.0),
    );
  }

  bool _isVideoFile(String filePath) {
    if (filePath.isEmpty) return false;

    final ext = filePath.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', 'wmv', 'flv', 'mkv', 'webm', '3gp']
        .contains(ext);
  }

  String _getFileName(String filePath) {
    try {
      return filePath.split(Platform.pathSeparator).last;
    } catch (e) {
      return filePath; // Retorna path completo em caso de erro
    }
  }

  Widget _buildSaveButton() {
    final Widget buttonIcon = _isSaving
        ? Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 8),
            child: const CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : const Icon(Icons.save_alt_outlined);

    return ElevatedButton.icon(
      icon: buttonIcon,
      label: Text(_isSaving ? 'Salvando...' : 'Registrar Ocorrência'),
      onPressed: _isSaving ? null : _saveOccurrence,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        elevation: _isSaving ? 0 : 2,
        disabledBackgroundColor:
            Theme.of(context).primaryColor.withOpacity(0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
