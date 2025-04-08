// lib/features/admin/services/user_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

// Importar o modelo centralizado (NÃO definir novamente o modelo Employee)
import '../../shared/models/employee.dart';
// Importar as constantes centralizadas
import '../../../core/constants/app_strings.dart';

/// Serviço para gerenciar operações relacionadas a usuários no Firebase
class UserService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  /// Construtor com injeção de dependências para facilitar testes
  UserService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'southamerica-east1');

  /// Referência para a coleção 'users' no Firestore
  CollectionReference get usersCollection => _firestore.collection('users');

  /// Busca os dados de um funcionário pelo ID
  Future<Employee> getEmployee(String userId) async {
    if (userId.trim().isEmpty) {
      throw ArgumentError('ID do usuário não pode ser vazio');
    }

    try {
      final doc = await usersCollection.doc(userId).get();

      if (!doc.exists || doc.data() == null) {
        _logError('Documento não encontrado ou vazio para userId: $userId');
        throw Exception(AppStrings.userNotFoundError);
      }

      final data = doc.data() as Map<String, dynamic>;
      return Employee.fromFirestore(doc.id, data);
    } catch (e) {
      _logError('Erro ao buscar funcionário $userId: $e');

      if (e is Exception &&
          e.toString().contains(AppStrings.userNotFoundError)) {
        rethrow;
      }

      throw Exception("${AppStrings.userDataReadError}: $e");
    }
  }

  /// Atualiza dados básicos do funcionário diretamente no Firestore
  Future<void> updateEmployeeBasicData(
      String userId, String displayName, bool isActive) async {
    // Validação de entrada
    _validateUserId(userId);

    if (displayName.trim().isEmpty) {
      throw Exception(AppStrings.nameRequiredError);
    }

    try {
      final Map<String, dynamic> updatePayload = {
        'displayName': displayName.trim(),
        'isActive': isActive,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      await usersCollection.doc(userId).update(updatePayload);
      _logInfo('Dados básicos atualizados para $userId: $updatePayload');
    } on FirebaseException catch (e) {
      _logError(
          'FirebaseException ao atualizar dados básicos para $userId: ${e.code} - ${e.message}');
      throw Exception(
          "${AppStrings.updateBasicDataError}: ${e.message ?? e.code}");
    } catch (e) {
      _logError('Erro inesperado ao atualizar dados básicos para $userId: $e');
      throw Exception("${AppStrings.updateBasicDataError}: $e");
    }
  }

  /// Promove um funcionário para Admin usando Cloud Function
  Future<String> promoteToAdmin(String userId) async {
    _validateUserId(userId);
    _logInfo('Chamando promoteUserToAdmin para userId: $userId');

    try {
      final HttpsCallable callable =
          _functions.httpsCallable('promoteUserToAdmin');
      final HttpsCallableResult result =
          await _executeCloudFunction(callable, {'userId': userId});

      _logInfo('Usuário promovido para Admin via CF: $userId');
      return result.data['message'] ?? AppStrings.promoteToAdminSuccess;
    } catch (e) {
      return _handleCloudFunctionError(
          e, 'promoteToAdmin', AppStrings.promoteToAdminError);
    }
  }

  /// Atualiza o email de um usuário chamando a Cloud Function
  Future<String> updateEmployeeEmail(String userId, String newEmail) async {
    _validateUserId(userId);
    _validateEmail(newEmail);

    _logInfo(
        'Chamando updateUserEmail para userId: $userId, newEmail: $newEmail');

    try {
      final HttpsCallable callable =
          _functions.httpsCallable('updateUserEmail');
      final HttpsCallableResult result = await _executeCloudFunction(
          callable, {'userId': userId, 'newEmail': newEmail});

      _logInfo('updateUserEmail sucesso: ${result.data['message']}');
      return result.data['message'] ?? AppStrings.updateSuccess;
    } catch (e) {
      return _handleCloudFunctionError(
          e, 'updateUserEmail', AppStrings.emailUpdateFailedError);
    }
  }

  /// Envia email de redefinição de senha via Cloud Function
  Future<String> sendPasswordResetEmail(
      String userId, String currentEmail) async {
    _validateUserId(userId);

    if (currentEmail.trim().isEmpty) {
      throw Exception(AppStrings.emailResetNotFoundError);
    }

    _logInfo(
        'Chamando sendUserPasswordReset para userId: $userId, email: $currentEmail');

    try {
      final HttpsCallable callable =
          _functions.httpsCallable('sendUserPasswordReset');
      final HttpsCallableResult result =
          await _executeCloudFunction(callable, {'userId': userId});

      _logInfo('sendUserPasswordReset sucesso: ${result.data['message']}');
      return result.data['message'] ?? AppStrings.passwordResetSuccess;
    } catch (e) {
      return _handleCloudFunctionError(
          e, 'sendPasswordReset', AppStrings.sendPasswordResetGenericError);
    }
  }

  /// Altera o papel/departamento de um funcionário
  Future<String> changeUserRole(String userId, String newRole,
      {String? department}) async {
    _validateUserId(userId);

    if (newRole.trim().isEmpty) {
      throw Exception('Novo papel não pode ser vazio');
    }

    if (newRole == 'Funcionário' &&
        (department == null || department.trim().isEmpty)) {
      throw Exception('Departamento é obrigatório para funcionários');
    }

    _logInfo(
        'Chamando changeUserRole para userId: $userId, newRole: $newRole, department: $department');

    try {
      // Parâmetros condicionais para a função cloud
      final Map<String, dynamic> params = {
        'userId': userId,
        'newRole': newRole,
      };

      // Só inclui department se for funcionário
      if (newRole == 'Funcionário') {
        params['department'] = department;
      }

      final HttpsCallable callable = _functions.httpsCallable('changeUserRole');
      final HttpsCallableResult result =
          await _executeCloudFunction(callable, params);

      _logInfo('changeUserRole sucesso: ${result.data['message']}');
      return result.data['message'] ?? 'Papel do usuário alterado com sucesso';
    } catch (e) {
      return _handleCloudFunctionError(
          e, 'changeUserRole', 'Erro ao alterar papel/departamento');
    }
  }

  /// Exclui um usuário permanentemente via Cloud Function
  Future<String> deleteUser(String userId) async {
    _validateUserId(userId);
    _logInfo('Chamando deleteUser para userId: $userId');

    try {
      final HttpsCallable callable = _functions.httpsCallable('deleteUser');
      final HttpsCallableResult result =
          await _executeCloudFunction(callable, {'userId': userId});

      _logInfo('deleteUser sucesso: ${result.data['message']}');
      return result.data['message'] ?? 'Usuário excluído com sucesso';
    } catch (e) {
      return _handleCloudFunctionError(
          e, 'deleteUser', 'Erro ao excluir usuário');
    }
  }

  // ===================== MÉTODOS AUXILIARES PRIVADOS =====================

  /// Executa uma Cloud Function com tratamento de resposta padronizado
  Future<HttpsCallableResult<Map<String, dynamic>>> _executeCloudFunction(
      HttpsCallable callable, Map<String, dynamic> params) async {
    final result = await callable.call<Map<String, dynamic>>(params);

    if (result.data['success'] != true) {
      throw Exception(result.data['message'] ??
          "Falha ao executar operação (resposta inesperada da função).");
    }

    return result;
  }

  /// Trata erros de Cloud Functions de forma padronizada
  String _handleCloudFunctionError(
      Object error, String operation, String defaultErrorMessage) {
    if (error is FirebaseFunctionsException) {
      _logError(
          'FirebaseFunctionsException [$operation]: ${error.code} - ${error.message}');
      throw Exception(
          "Erro da Função (${error.code}): ${error.message ?? defaultErrorMessage}");
    } else {
      _logError('Erro inesperado [$operation]: $error');
      throw Exception("$defaultErrorMessage: $error");
    }
  }

  /// Valida se o ID do usuário é válido
  void _validateUserId(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError('ID do usuário não pode ser vazio');
    }
  }

  /// Valida se o email tem formato básico válido
  void _validateEmail(String email) {
    if (email.trim().isEmpty) {
      throw ArgumentError('Email não pode ser vazio');
    }

    // Validação básica de formato de email
    if (!email.contains('@') || !email.contains('.')) {
      throw ArgumentError('Formato de email inválido');
    }
  }

  /// Centraliza registro de erros com formato padronizado
  void _logError(String message) {
    debugPrint('[UserService ERROR] $message');
  }

  /// Centraliza registro de informações com formato padronizado
  void _logInfo(String message) {
    debugPrint('[UserService INFO] $message');
  }
}
