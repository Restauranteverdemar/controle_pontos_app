// lib/features/admin/screens/controllers/registro_ocorrencia_controller.dart

import 'dart:io';
import 'package:flutter/foundation.dart'; // Para debugPrint e ChangeNotifier
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;

// --- ADICIONADAS: Dependências de Compressão ---
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';
// -------------------------------------------

// Importe seus modelos
import '../../../shared/models/employee.dart';
import '../../../shared/models/incident_type.dart';

// --- Classes de Constantes ---
class AppRoles {
  static const String admin = 'Admin';
  static const String funcionario = 'Funcionário';
}

class AppOccurrenceStatus {
  static const String pendente = 'Pendente';
}

class AppDepartments {
  static const String ambos = 'Ambos';
  static const String cozinha = 'Cozinha';
  static const String salao = 'Salão';
}

class AppLocales {
  static const String ptBR = 'pt_BR';
}

class AttachmentType {
  static const String image = 'image';
  static const String video = 'video';
}
// --- Fim das Classes de Constantes ---

class RegistroOcorrenciaController with ChangeNotifier {
  // Serviços Firebase
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  // Estado de seleção do formulário
  Employee? _selectedEmployee;
  IncidentType? _selectedIncidentType;
  String? _selectedEmployeeDepartment;
  String? _currentUserRole;
  String? _currentAdminName;

  // Estado calculado internamente
  bool _isLoading = false; // Loading geral (dados iniciais, tipos)
  bool _isSaving =
      false; // Flag específica para o processo de salvar/upload/compressão
  bool _isFetchingInitialData = false; // Flag para o carregamento inicial geral
  String? _errorMessage;

  // --- ADICIONADO: Estado de Progresso e Compressão ---
  double? _uploadProgress; // Progresso do arquivo atual (0.0 a 1.0)
  String? _uploadFileName; // Nome do arquivo sendo enviado
  bool _isCompressing = false; // Flag para indicar compressão em andamento
  String? _compressingFileName; // Nome do arquivo sendo comprimido
  // ----------------------------------------------

  // NOVO: Flag para ativar/desativar compressão
  bool _compressaoAtivada = false; // Desativada por padrão

  // Dados para os dropdowns
  List<Employee> _allEmployees = [];
  List<IncidentType> _allIncidentTypes = [];
  List<IncidentType> _filteredIncidentTypes = [];

  // Formatador de data
  late final DateFormat _dateFormatter;

  // --- ADICIONADO: Constantes de Limite ---
  static const int _maxImageSizeInBytes = 5 * 1024 * 1024; // 5 MB
  static const int _maxVideoSizeInBytes = 15 * 1024 * 1024; // 15 MB
  // ----------------------------------------

  RegistroOcorrenciaController({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance {
    _initializeLocaleAndFormatter();
    debugPrint(
        "RegistroOcorrenciaController inicializado. Carregando dados iniciais...");
    initialize();
  }

  // --- Getters ---
  Employee? get selectedEmployee => _selectedEmployee;
  IncidentType? get selectedIncidentType => _selectedIncidentType;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isCompressing => _isCompressing;
  bool get isFetchingInitialData => _isFetchingInitialData;
  String? get errorMessage => _errorMessage;
  String? get adminName => _currentAdminName;
  double? get uploadProgress => _uploadProgress;
  String? get uploadFileName => _uploadFileName;
  String? get compressingFileName => _compressingFileName;
  bool get compressaoAtivada => _compressaoAtivada;

  // NOVO: Setter para compressão
  set compressaoAtivada(bool value) {
    if (_compressaoAtivada != value) {
      _compressaoAtivada = value;
      notifyListeners();
    }
  }

  List<Employee> get employees => _allEmployees;
  List<IncidentType> get incidentTypesFiltered => _filteredIncidentTypes;
  List<IncidentType> get allIncidentTypes => _allIncidentTypes;
  bool get canShowForm => !_isFetchingInitialData && _errorMessage == null;

  // --- Métodos de Inicialização e Carregamento ---
  Future<void> initialize() async {
    if (_isFetchingInitialData || _isLoading) {
      debugPrint(
          "initialize(): Já está em processo de inicialização ou carregamento");
      return;
    }

    debugPrint("Iniciando initialize() no controller");
    _setFetchingState(true);
    _setLoadingState(true, notify: false);

    try {
      await _loadCurrentAdminInfo();
      _validateAdminPermission();

      debugPrint("Carregando funcionários e tipos de ocorrência...");

      // CORREÇÃO: Sequencial em vez de paralelo para garantir que funcionários sejam carregados
      // antes de tipos (devido a possível filtragem por departamento)
      await loadEmployees(notify: false);
      await loadIncidentTypes(notify: false);

      debugPrint(
          "Dados iniciais carregados. Empregados: ${_allEmployees.length}, Tipos: ${_allIncidentTypes.length}");
      _clearErrorMessage();
    } catch (e, stackTrace) {
      debugPrint("Erro durante inicialização do controller: $e\n$stackTrace");
      _setError(
          "Falha ao carregar dados: ${e.toString()}. Verifique conexão/permissões.");
      _resetInternalData();
    } finally {
      _setFetchingState(false);
      _setLoadingState(false, notify: true); // Notifica ao final de tudo
    }
  }

  void _validateAdminPermission() {
    if (_currentUserRole != AppRoles.admin) {
      throw Exception(
          "Acesso negado. Apenas administradores podem registrar ocorrências.");
    }
  }

  void _setFetchingState(bool isFetching) {
    if (_isFetchingInitialData == isFetching) return;
    _isFetchingInitialData = isFetching;
    if (!isFetching) _clearErrorMessage();
    notifyListeners();
  }

  Future<void> _initializeLocaleAndFormatter() async {
    try {
      await initializeDateFormatting(AppLocales.ptBR, null);
      _dateFormatter = DateFormat('dd/MM/yyyy HH:mm', AppLocales.ptBR);
    } catch (e) {
      debugPrint("Erro ao inicializar formatador pt_BR: $e. Usando padrão.");
      _dateFormatter = DateFormat('yyyy-MM-dd HH:mm');
    }
  }

  Future<void> _loadCurrentAdminInfo() async {
    _currentUserRole = null;
    _currentAdminName = null;
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception("Administrador não autenticado.");

    try {
      debugPrint("Buscando informações do admin: ${currentUser.uid}");
      final userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      if (!userDoc.exists || userDoc.data() == null) {
        throw Exception("Perfil do administrador não encontrado ou inválido.");
      }

      final userData = userDoc.data()!;
      _currentUserRole = userData['role'] as String?;
      _currentAdminName = userData['displayName'] as String? ??
          currentUser.displayName ??
          'Admin';
      debugPrint(
          "Info admin carregada: role=$_currentUserRole, name=$_currentAdminName");
    } catch (e) {
      debugPrint("Erro ao carregar info admin (${currentUser.uid}): $e");
      _currentAdminName = currentUser.displayName ?? 'Admin'; // Fallback
      throw Exception(
          "Falha ao carregar dados do administrador: ${e.toString()}");
    }
  }

  // CORREÇÃO: loadEmployees agora verifica se _currentUserRole é nulo
  // e inclui verificação de inicialização
  Future<void> loadEmployees({bool notify = true}) async {
    // CORREÇÃO: Verificar se o controller foi inicializado corretamente
    if (_currentUserRole == null) {
      debugPrint(
          "loadEmployees(): Controller não inicializado completamente. Verificando admin...");

      // Em vez de chamar initialize(), que poderia criar um loop,
      // tentamos apenas carregar as informações do admin
      try {
        await _loadCurrentAdminInfo();
        _validateAdminPermission();
      } catch (e) {
        debugPrint("Erro ao carregar informações do admin: $e");
        _setError(
            "Falha ao carregar informações do administrador. Tente novamente.");
        if (notify) notifyListeners();
        return;
      }
    }

    if (_isLoading) {
      debugPrint(
          "loadEmployees(): Já está carregando dados, solicitação ignorada.");
      return;
    }

    if (_currentUserRole != AppRoles.admin) {
      debugPrint(
          "loadEmployees(): Usuário não é admin (role: $_currentUserRole). Acesso negado.");
      _setError("Apenas administradores podem acessar esta funcionalidade.");
      if (notify) notifyListeners();
      return;
    }

    debugPrint("Iniciando carregamento de funcionários...");
    _setLoadingState(true, notify: notify);

    try {
      debugPrint("Executando query para buscar funcionários...");
      final querySnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: AppRoles.funcionario)
          .where('isActive', isEqualTo: true)
          .orderBy('displayName')
          .get();

      debugPrint("Query retornou ${querySnapshot.docs.length} documentos");
      _allEmployees = _mapSnapshotToEmployees(querySnapshot);
      debugPrint("Mapeados ${_allEmployees.length} funcionários válidos");
      _clearErrorMessage();
    } catch (e, stackTrace) {
      debugPrint("Erro ao buscar funcionários: $e\n$stackTrace");
      _allEmployees = [];
      _setError("Falha ao buscar funcionários: ${e.toString()}");
    } finally {
      _setLoadingState(false, notify: notify);
    }
  }

  List<Employee> _mapSnapshotToEmployees(QuerySnapshot querySnapshot) {
    final employees = querySnapshot.docs
        .map((doc) {
          try {
            final data = doc.data() as Map<String, dynamic>;
            debugPrint(
                "Mapeando funcionário ${doc.id}: ${data['displayName']}");
            return Employee.fromFirestore(doc.id, data);
          } catch (e) {
            debugPrint("Erro ao converter funcionário ${doc.id}: $e");
            return null;
          }
        })
        .whereType<Employee>()
        .toList();

    // Verifica se há funcionários sem departamento e exibe alerta
    final semDepartamento = employees
        .where(
            (emp) => emp.department == null || emp.department!.trim().isEmpty)
        .toList();

    if (semDepartamento.isNotEmpty) {
      debugPrint(
          "ALERTA: ${semDepartamento.length} funcionários sem departamento!");
      for (var emp in semDepartamento) {
        debugPrint("  - ${emp.displayName} (${emp.id})");
      }
    }

    return employees;
  }

  // CORRIGIDO: Adicionada verificação para _currentUserRole nulo
  Future<void> loadIncidentTypes({bool notify = true}) async {
    // CORREÇÃO: Verificar se o controller foi inicializado corretamente
    if (_currentUserRole == null) {
      debugPrint(
          "loadIncidentTypes(): Controller não inicializado completamente.");
      if (notify) notifyListeners();
      return;
    }

    if (_isLoading) {
      debugPrint(
          "loadIncidentTypes(): Já está carregando dados, solicitação ignorada.");
      return;
    }

    debugPrint("Iniciando carregamento de tipos de ocorrência...");
    _setLoadingState(true, notify: notify);

    try {
      debugPrint("Executando query para buscar tipos de ocorrência...");
      final querySnapshot = await _firestore
          .collection('incidentTypes')
          .where('isActive', isEqualTo: true)
          .orderBy('name')
          .get();

      debugPrint("Query retornou ${querySnapshot.docs.length} documentos");
      _allIncidentTypes = _mapSnapshotToIncidentTypes(querySnapshot);
      debugPrint("Mapeados ${_allIncidentTypes.length} tipos válidos");

      // CORREÇÃO: Verifica e aplica filtro de departamento, se houver
      if (_selectedEmployeeDepartment != null &&
          _selectedEmployeeDepartment!.isNotEmpty) {
        filterIncidentTypes(_selectedEmployeeDepartment, notify: false);
        debugPrint(
            "Filtro aplicado para departamento: $_selectedEmployeeDepartment");
      } else {
        _filteredIncidentTypes = [];
      }

      _clearErrorMessage();
    } catch (e, stackTrace) {
      debugPrint("Erro ao buscar tipos: $e\n$stackTrace");
      _resetIncidentTypesLists();
      _setError("Falha ao buscar tipos: ${e.toString()}");
    } finally {
      _setLoadingState(false, notify: notify);
    }
  }

  List<IncidentType> _mapSnapshotToIncidentTypes(QuerySnapshot querySnapshot) {
    final types = querySnapshot.docs
        .map((doc) {
          try {
            debugPrint("Mapeando tipo de ocorrência: ${doc.id}");
            return IncidentType.fromSnapshot(doc);
          } catch (e) {
            debugPrint("Erro ao converter tipo ${doc.id}: $e");
            return null;
          }
        })
        .whereType<IncidentType>()
        .toList();
    return types;
  }

  void _setLoadingState(bool isLoading, {bool notify = true}) {
    if (_isLoading == isLoading) return;
    _isLoading = isLoading;
    if (notify) notifyListeners();
  }

  void _resetIncidentTypesLists() {
    _allIncidentTypes = [];
    _filteredIncidentTypes = [];
  }

  void _resetInternalData() {
    _allEmployees = [];
    _resetIncidentTypesLists();
  }

  // --- Métodos de Atualização de Estado (View -> Controller) ---
  void selectEmployee(Employee? employee) {
    if (_selectedEmployee == employee) return;

    debugPrint(
        "Selecionando funcionário: ${employee?.displayName} (${employee?.id}), depto: ${employee?.department}");

    _selectedEmployee = employee;
    _selectedIncidentType = null;
    _selectedEmployeeDepartment = employee?.department;

    if (_selectedEmployeeDepartment == null ||
        _selectedEmployeeDepartment!.trim().isEmpty) {
      debugPrint("ALERTA: Funcionário sem departamento definido!");
      // Você pode optar por usar um departamento padrão aqui
      // _selectedEmployeeDepartment = AppDepartments.ambos;
      _filteredIncidentTypes = [];
    } else {
      filterIncidentTypes(_selectedEmployeeDepartment);
    }

    _clearErrorMessage();
    notifyListeners();
  }

  void selectIncidentType(IncidentType? incidentType) {
    if (_selectedIncidentType == incidentType) return;
    debugPrint(
        "Selecionando tipo: ${incidentType?.name} (${incidentType?.id})");
    _selectedIncidentType = incidentType;
    _clearErrorMessage();
    notifyListeners();
  }

  // CORREÇÃO: Melhorada a lógica de filtragem
  void filterIncidentTypes(String? department, {bool notify = true}) {
    debugPrint("Filtrando tipos para departamento: $department");
    debugPrint(
        "Total de tipos antes da filtragem: ${_allIncidentTypes.length}");

    if (department == null || department.trim().isEmpty) {
      debugPrint("Departamento nulo/vazio, nenhum tipo será filtrado");
      _filteredIncidentTypes = [];
    } else {
      _filteredIncidentTypes = _allIncidentTypes.where((type) {
        final bool aplicavel =
            type.applicableDepartments.contains(department) ||
                type.applicableDepartments.contains(AppDepartments.ambos);

        debugPrint(
            "Tipo ${type.id} (${type.name}) - departamentos aplicáveis: ${type.applicableDepartments} - aplicável para $department: $aplicavel");

        return aplicavel;
      }).toList();
    }

    debugPrint("Após filtragem: ${_filteredIncidentTypes.length} tipos");

    if (notify) notifyListeners();
  }

  // MODIFICADO: Melhorado o método de compressão de imagem
  Future<File?> _compressImage(XFile originalXFile) async {
    final originalPath = originalXFile.path;
    final originalFile = File(originalPath);
    final originalSize = await originalFile.length();
    final originalSizeMB = (originalSize / (1024 * 1024)).toStringAsFixed(2);

    final targetFileName = 'compressed_${p.basename(originalPath)}';
    final targetPath = p.join(p.dirname(originalPath), targetFileName);
    final originalFileName = p.basename(originalPath);

    _setCompressingState(true, originalFileName);

    try {
      debugPrint(
          "Iniciando compressão da imagem: $originalFileName ($originalSizeMB MB)");

      // Tenta diferentes configurações de compressão, começando com qualidade mais alta
      for (int quality in [85, 70, 55]) {
        final XFile? resultXFile =
            await FlutterImageCompress.compressAndGetFile(
          originalPath,
          targetPath,
          quality: quality,
          minWidth: 1200, // Valores ajustados para melhor equilíbrio
          minHeight: 1200,
          format: CompressFormat.jpeg,
        );

        if (resultXFile == null) continue;

        final compressedFile = File(resultXFile.path);
        final compressedSize = await compressedFile.length();
        final compressedSizeMB =
            (compressedSize / (1024 * 1024)).toStringAsFixed(2);

        // Verifica se a compressão realmente reduziu o tamanho
        if (compressedSize >= originalSize) {
          debugPrint(
              "Compressão com qualidade $quality não reduziu o tamanho ($compressedSizeMB MB >= $originalSizeMB MB)");
          try {
            await compressedFile.delete();
          } catch (_) {}

          // Tenta próximo nível de qualidade
          continue;
        }

        debugPrint(
            "Imagem comprimida com qualidade $quality: $compressedSizeMB MB (original: $originalSizeMB MB)");

        // Verifica se está dentro do limite
        if (compressedSize > _maxImageSizeInBytes) {
          debugPrint("Imagem comprimida ainda excede o limite de 5 MB");

          // Se estamos na última tentativa, reporta erro
          if (quality == 55) {
            _setError(
                "Imagem $originalFileName ($compressedSizeMB MB) excede o limite de 5 MB mesmo após compressão.");
            try {
              await compressedFile.delete();
            } catch (_) {}
            return null;
          }

          // Senão, tenta próximo nível
          try {
            await compressedFile.delete();
          } catch (_) {}
          continue;
        }

        // Se chegamos aqui, compressão foi bem-sucedida
        return compressedFile;
      }

      // Se todas as tentativas falharam
      _setError(
          "Não foi possível comprimir a imagem $originalFileName adequadamente.");
      return null;
    } catch (e, stackTrace) {
      debugPrint("Erro ao comprimir imagem $originalFileName: $e\n$stackTrace");
      _setError(
          "Erro durante compressão da imagem $originalFileName: ${e.toString()}");
      return null;
    } finally {
      _setCompressingState(false, null);
    }
  }

  Future<File?> _compressVideo(XFile originalXFile) async {
    final originalPath = originalXFile.path;
    final originalFileName = p.basename(originalPath);

    _setCompressingState(true, originalFileName);

    try {
      debugPrint("Iniciando compressão do vídeo: $originalFileName");
      if (!await File(originalPath).exists()) {
        throw Exception("Arquivo original não encontrado: $originalPath");
      }

      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        originalPath,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
        frameRate: 30,
      );

      if (mediaInfo == null || mediaInfo.path == null) {
        debugPrint("Compressão do vídeo falhou (resultado nulo)");
        _setError("Não foi possível comprimir o vídeo $originalFileName.");
        return null;
      }

      final compressedFile = File(mediaInfo.path!);
      if (!await compressedFile.exists()) {
        throw Exception(
            "Arquivo comprimido não encontrado: ${mediaInfo.path!}");
      }

      final compressedSize = await compressedFile.length();
      final compressedSizeMB =
          (compressedSize / (1024 * 1024)).toStringAsFixed(2);
      debugPrint(
          "Vídeo comprimido: ${compressedFile.path}, Tamanho: $compressedSize bytes ($compressedSizeMB MB)");

      if (compressedSize > _maxVideoSizeInBytes) {
        debugPrint("Vídeo comprimido ainda excede o limite de 15 MB.");
        _setError(
            "Vídeo $originalFileName ($compressedSizeMB MB) excede o limite de 15 MB (mesmo após compressão).");
        try {
          await compressedFile.delete();
        } catch (_) {}
        try {
          await VideoCompress.deleteAllCache();
        } catch (_) {}
        return null;
      }
      return compressedFile;
    } catch (e, stackTrace) {
      debugPrint("Erro ao comprimir vídeo $originalFileName: $e\n$stackTrace");
      _setError(
          "Erro durante compressão do vídeo $originalFileName: ${e.toString()}");
      try {
        await VideoCompress.deleteAllCache();
      } catch (_) {}
      return null;
    } finally {
      _setCompressingState(false, null);
    }
  }

  void _setCompressingState(bool isCompressing, String? fileName) {
    if (_isCompressing == isCompressing && _compressingFileName == fileName)
      return;
    _isCompressing = isCompressing;
    _compressingFileName = fileName;
    notifyListeners();
  }

  // MODIFICADO: Método principal de registro com compressão opcional
  Future<bool> registerOccurrence({
    required Employee employee,
    required IncidentType incidentType,
    required DateTime occurrenceDate,
    required String? notes,
    required int? manualPointsAdjustment,
    required User adminUser,
    List<XFile>? mediaFiles,
  }) async {
    if (_isSaving || _isCompressing) return false;
    _setSavingState(true);
    _clearErrorMessage();

    List<Map<String, String>> uploadedAttachmentsInfo = [];

    try {
      debugPrint("Iniciando registro para ${employee.displayName}");

      // 1. Upload Sequencial (com ou sem compressão)
      if (mediaFiles != null && mediaFiles.isNotEmpty) {
        debugPrint("Processando ${mediaFiles.length} anexos...");
        for (int i = 0; i < mediaFiles.length; i++) {
          final xFile = mediaFiles[i];
          final originalFileName = _getFileName(xFile.path);
          debugPrint("Anexo ${i + 1}/${mediaFiles.length}: $originalFileName");

          File fileToUpload;
          final isVideo = _isVideoFile(xFile.path);

          // MODIFICAÇÃO: Verifica se deve comprimir
          if (_compressaoAtivada) {
            // --- Etapa de Compressão (somente se ativada) ---
            File? compressedFile;
            if (isVideo) {
              compressedFile = await _compressVideo(xFile);
            } else {
              compressedFile = await _compressImage(xFile);
            }

            if (compressedFile == null) {
              debugPrint(
                  "Compressão falhou para $originalFileName. Abortando.");
              _setSavingState(false);
              return false;
            }
            fileToUpload = compressedFile;
          } else {
            // Sem compressão, usa o arquivo original
            fileToUpload = File(xFile.path);

            // Verifica tamanho (mesmo sem compressão)
            final fileSize = await fileToUpload.length();
            final maxSize =
                isVideo ? _maxVideoSizeInBytes : _maxImageSizeInBytes;

            if (fileSize > maxSize) {
              final fileSizeFormatted =
                  (fileSize / (1024 * 1024)).toStringAsFixed(2);
              final maxSizeFormatted =
                  (maxSize / (1024 * 1024)).toStringAsFixed(0);
              _setError(
                  '${isVideo ? "Vídeo" : "Imagem"} $originalFileName ($fileSizeFormatted MB) excede o limite de $maxSizeFormatted MB. Ative a compressão ou selecione um arquivo menor.');
              _setSavingState(false);
              return false;
            }
          }

          // --- Etapa de Upload ---
          debugPrint("Iniciando upload de $originalFileName");
          try {
            final uploadInfo =
                await _uploadAttachment(fileToUpload, originalFileName);
            uploadedAttachmentsInfo.add(uploadInfo);
            debugPrint("Upload de $originalFileName concluído.");

            // Limpa arquivo temporário se foi comprimido
            if (_compressaoAtivada && fileToUpload.path != xFile.path) {
              try {
                await fileToUpload.delete();
              } catch (delErr) {
                debugPrint(
                    "Aviso: Falha ao deletar temporário ${fileToUpload.path}: $delErr");
              }
            }
          } catch (uploadError) {
            debugPrint("Erro upload $originalFileName: $uploadError");
            _setError("Falha no upload: ${uploadError.toString()}");

            // Limpa arquivo temporário se foi comprimido
            if (_compressaoAtivada && fileToUpload.path != xFile.path) {
              try {
                await fileToUpload.delete();
              } catch (_) {}
            }

            _setSavingState(false);
            return false;
          }
        }

        // Limpa cache do video_compress se foi usado
        if (_compressaoAtivada && mediaFiles.any((f) => _isVideoFile(f.path))) {
          try {
            await VideoCompress.deleteAllCache();
          } catch (_) {}
        }
      }

      // 2. Prepara Dados
      final occurrenceData = _prepareOccurrenceData(
        employee: employee,
        incidentType: incidentType,
        occurrenceDate: occurrenceDate,
        adminUser: adminUser,
        manualAdjustment: manualPointsAdjustment,
        notes: notes,
        attachments:
            uploadedAttachmentsInfo.isNotEmpty ? uploadedAttachmentsInfo : null,
      );

      // 3. Salva no Firestore
      debugPrint("Salvando ocorrência no Firestore...");
      final docRef =
          await _firestore.collection('pointsOccurrences').add(occurrenceData);
      debugPrint("Ocorrência salva com ID: ${docRef.id}");

      resetFormSelection();
      return true;
    } catch (e, stackTrace) {
      debugPrint("Erro GERAL ao registrar ocorrência: $e\n$stackTrace");
      _setError('Erro ao salvar ocorrência: ${e.toString()}');
      return false;
    } finally {
      _setSavingState(false); // Garante que o estado seja liberado
    }
  }

  // MODIFICADO: Upload com progresso otimizado
  Future<Map<String, String>> _uploadAttachment(
      File fileToUpload, String originalFileName) async {
    final fileExtension = p.extension(originalFileName).toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uniqueFileName = '$timestamp-${originalFileName}';
    final filePath = 'attachments/$uniqueFileName';
    final mediaType = _getMediaType(fileExtension);

    debugPrint("Iniciando upload: $filePath (Tipo: $mediaType)");

    // Determinar tamanho para log
    final fileSize = await fileToUpload.length();
    final fileSizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(2);
    debugPrint("Tamanho do arquivo: $fileSizeMB MB");

    _setUploadState(0.0, originalFileName);

    try {
      final storageRef = _storage.ref().child(filePath);
      final metadata = SettableMetadata(
        contentType: mediaType == AttachmentType.video
            ? 'video/${fileExtension.substring(1)}'
            : 'image/${fileExtension.substring(1)}',
        customMetadata: {
          'originalName': originalFileName,
          'userId': _selectedEmployee?.id ?? 'unknown',
          'uploadedBy': _auth.currentUser?.uid ?? 'unknown',
          'fileType': mediaType
        },
      );

      final uploadTask = storageRef.putFile(fileToUpload, metadata);

      // Escuta o progresso com intervalo para reduzir notificações
      double lastNotifiedProgress = 0;
      await for (final snapshot in uploadTask.snapshotEvents) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        // Só notifica se avançou pelo menos 5% desde a última notificação
        if (progress - lastNotifiedProgress >= 0.05 || progress == 1.0) {
          _setUploadState(progress.isNaN ? 0.0 : progress, originalFileName);
          lastNotifiedProgress = progress;
        }
      }

      final finalState = await uploadTask;
      if (finalState.state == TaskState.success) {
        final downloadUrl = await finalState.ref.getDownloadURL();
        debugPrint(
            "Upload de $originalFileName concluído. Tamanho: $fileSizeMB MB");
        _clearUploadState();
        return {
          'url': downloadUrl,
          'type': mediaType,
          'name': originalFileName
        };
      } else {
        throw Exception("Upload falhou (Estado final: ${finalState.state})");
      }
    } catch (e) {
      _clearUploadState();
      rethrow;
    }
  }

  // Helper para atualizar estado de upload
  void _setUploadState(double? progress, String? fileName) {
    if (_uploadProgress == progress && _uploadFileName == fileName) return;
    _uploadProgress = progress;
    _uploadFileName = fileName;
    notifyListeners();
  }

  // Helper para limpar estado de upload
  void _clearUploadState() {
    if (_uploadProgress != null || _uploadFileName != null) {
      _uploadProgress = null;
      _uploadFileName = null;
      notifyListeners();
    }
  }

  // Helper para definir estado de salvamento e notificar
  void _setSavingState(bool isSaving) {
    if (_isSaving == isSaving) return;
    _isSaving = isSaving;
    if (!isSaving) {
      // Se parou de salvar, limpa também o estado de upload/compressão
      _clearUploadState();
      _setCompressingState(false, null);
    }
    notifyListeners();
  }

  Map<String, dynamic> _prepareOccurrenceData({
    required Employee employee,
    required IncidentType incidentType,
    required DateTime occurrenceDate,
    required User adminUser,
    required int? manualAdjustment,
    required String? notes,
    List<Map<String, String>>? attachments,
  }) {
    final adminId = adminUser.uid;
    final adminDisplayName =
        _currentAdminName ?? adminUser.displayName ?? 'Admin';
    final defaultPoints = incidentType.defaultPoints;
    final adjustment = manualAdjustment ?? 0;
    final finalPoints = defaultPoints + adjustment;

    return _buildOccurrenceData(
      employeeId: employee.id,
      employeeName: employee.displayName ?? 'Nome Desconhecido',
      incidentType: incidentType,
      occurrenceDateTime: occurrenceDate,
      registeredById: adminId,
      registeredByName: adminDisplayName,
      defaultPoints: defaultPoints,
      manualAdjustment: adjustment == 0 ? null : adjustment,
      finalPoints: finalPoints,
      notes: notes,
      attachments: attachments,
    );
  }

  Map<String, dynamic> _buildOccurrenceData({
    required String employeeId,
    required String employeeName,
    required IncidentType incidentType,
    required DateTime occurrenceDateTime,
    required String registeredById,
    required String registeredByName,
    required int defaultPoints,
    required int? manualAdjustment,
    required int finalPoints,
    required String? notes,
    List<Map<String, String>>? attachments,
  }) {
    final Map<String, dynamic> data = {
      'userId': employeeId,
      'employeeName': employeeName,
      'incidentTypeId': incidentType.id,
      'incidentName': incidentType.name,
      'occurrenceDate': Timestamp.fromDate(occurrenceDateTime),
      'registeredBy': registeredById,
      'registeredByName': registeredByName,
      'registeredAt': FieldValue.serverTimestamp(),
      'status': AppOccurrenceStatus.pendente,
      'defaultPoints': defaultPoints,
      'finalPoints': finalPoints,
      'approvedRejectedBy': null,
      'approvedRejectedByName': null,
      'approvedRejectedAt': null,
      'attachments': attachments ?? [],
      'periodId': null,
    };
    // Salva ajuste manual apenas se for diferente de 0 (ou nulo)
    if (manualAdjustment != null && manualAdjustment != 0) {
      data['manualPointsAdjustment'] = manualAdjustment;
    }
    if (notes != null && notes.isNotEmpty) data['notes'] = notes;
    return data;
  }

  String _getMediaType(String fileExtension) {
    final videoExtensions = [
      '.mp4',
      '.mov',
      '.avi',
      '.wmv',
      '.flv',
      '.mkv',
      '.webm',
      '.3gp'
    ];
    return videoExtensions.contains(fileExtension.toLowerCase())
        ? AttachmentType.video
        : AttachmentType.image;
  }

  bool _isVideoFile(String filePath) {
    if (filePath.isEmpty) return false;
    final ext = p.extension(filePath).toLowerCase();
    return ['.mp4', '.mov', '.avi', '.wmv', '.flv', '.mkv', '.webm', '.3gp']
        .contains(ext);
  }

  String _getFileName(String filePath) {
    try {
      return p.basename(filePath);
    } catch (_) {
      return filePath.split(Platform.pathSeparator).last;
    }
  }

  // --- Métodos Utilitários ---
  void _clearErrorMessage() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  void _setError(String message) {
    // Evita sobrescrever erro durante operação em andamento
    if (_isSaving || _isCompressing) {
      debugPrint("Erro suprimido durante operação: $message");
      return;
    }
    if (_errorMessage != message) {
      _errorMessage = message;
      notifyListeners();
    }
  }

  void resetFormSelection() {
    _selectedEmployee = null;
    _selectedIncidentType = null;
    _selectedEmployeeDepartment = null;
    _filteredIncidentTypes = [];
    notifyListeners();
  }

  @override
  void dispose() {
    debugPrint("RegistroOcorrenciaController sendo descartado.");
    // Limpa cache do video_compress ao descartar
    VideoCompress.deleteAllCache().catchError((_) =>
        debugPrint("Falha ao limpar cache do VideoCompress no dispose."));
    super.dispose();
  }
}
