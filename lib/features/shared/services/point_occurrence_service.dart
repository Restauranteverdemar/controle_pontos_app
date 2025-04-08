// lib/features/shared/services/point_occurrence_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// --- !!! ChangeNotifier vem de foundation.dart !!! ---
import 'package:flutter/foundation.dart'; // Para kDebugMode, debugPrint e ChangeNotifier

// --- MODIFICAÇÃO: Adicionada importação do IncidentType ---
import '../models/incident_type.dart'; // Necessário para o novo método

// --- MODIFICAÇÃO: Adicionar importação do PointOccurrence ---
import '../models/point_occurrence.dart'; // Para o novo método de criação

// --- MANTIDO: Importação do enum separado, como estava no seu código ---
import '../enums/occurrence_status.dart' as enums; // Adicionado prefixo 'enums'

/// Serviço responsável por gerenciar operações relacionadas às ocorrências de pontuação.
///
/// Gerencia operações como atualização de status, integrando com Firestore
/// para persistência dos dados e mantendo o registro de quem realizou as ações.
// --- !!! CORREÇÃO APLICADA: Adicionado "with ChangeNotifier" !!! ---
class PointOccurrenceService with ChangeNotifier {
  // Inicialização direta das instâncias Firebase
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Referência para a coleção principal inicializada diretamente
  final CollectionReference _occurrencesCollection =
      FirebaseFirestore.instance.collection('pointsOccurrences');

  /// Nome da coleção no Firestore - útil para testes e referência
  static const String collectionName = 'pointsOccurrences';

  // --- ADICIONADO: Nome da coleção de tipos como constante ---
  static const String incidentTypesCollectionName = 'incidentTypes';

  /// Cria uma nova ocorrência de pontuação com periodId explicitamente definido como null.
  ///
  /// Este método garante que todas as ocorrências criadas tenham periodId=null inicialmente,
  /// o que é essencial para o funcionamento correto do sistema de reset mensal.
  ///
  /// Parâmetros:
  /// - [occurrenceData]: Mapa contendo os dados da ocorrência a ser criada.
  ///
  /// Retorna o ID da ocorrência criada.
  /// Lança exceções em caso de erro na criação.
  Future<String> createOccurrence(Map<String, dynamic> occurrenceData) async {
    try {
      // Garantir que periodId seja null explicitamente
      occurrenceData['periodId'] = null;

      // Adicionar registeredAt como serverTimestamp se não foi fornecido
      if (!occurrenceData.containsKey('registeredAt')) {
        occurrenceData['registeredAt'] = FieldValue.serverTimestamp();
      }

      _logDebug('Criando nova ocorrência com periodId=null');

      // Criar a ocorrência no Firestore
      final docRef = await _occurrencesCollection.add(occurrenceData);
      _logDebug('Nova ocorrência criada com ID: ${docRef.id}');

      return docRef.id;
    } catch (e) {
      _logDebug('Erro ao criar ocorrência: $e');
      throw Exception('Falha ao criar ocorrência: ${e.toString()}');
    }
  }

  /// Cria uma nova ocorrência de pontuação a partir de um objeto PointOccurrence.
  ///
  /// Garante que periodId seja definido como null, mesmo que o objeto
  /// original tenha um valor diferente para este campo.
  ///
  /// Parâmetros:
  /// - [occurrence]: Objeto PointOccurrence com os dados da ocorrência.
  ///
  /// Retorna o ID da ocorrência criada.
  Future<String> createOccurrenceFromModel(PointOccurrence occurrence) async {
    try {
      // Criar um mapa a partir do modelo
      Map<String, dynamic> data = occurrence.toJson();

      // Usar o método base para criar a ocorrência que garante periodId=null
      return createOccurrence(data);
    } catch (e) {
      _logDebug('Erro ao criar ocorrência a partir do modelo: $e');
      throw Exception('Falha ao criar ocorrência: ${e.toString()}');
    }
  }

  /// Atualiza o status de uma ocorrência específica para Aprovada ou Reprovada.
  ///
  /// Registra o administrador responsável pela ação, juntamente com a data/hora,
  /// usando os nomes de campo esperados pelo modelo [PointOccurrence].
  ///
  /// Parâmetros:
  /// - [occurrenceId]: ID único do documento de ocorrência a ser atualizado.
  /// - [newStatus]: Novo status a ser definido (deve ser Aprovada ou Reprovada).
  ///
  /// Lança [ArgumentError] se o ID for inválido ou status inapropriado.
  /// Lança [Exception] se o administrador não estiver autenticado ou em caso de erro no Firestore.
  Future<void> updateOccurrenceStatus(
    String occurrenceId,
    enums.OccurrenceStatus
        newStatus, // Usando o enum importado de ../enums/ com prefixo
  ) async {
    // Validação dos parâmetros de entrada
    if (occurrenceId.isEmpty) {
      throw ArgumentError('O ID da ocorrência não pode ser vazio');
    }

    // --- MANTIDO: Validação usando o enum importado ---
    // --- CORRIGIDO: Usando o prefixo 'enums' e corrigindo a capitalização na mensagem ---
    if (newStatus != enums.OccurrenceStatus.aprovada &&
        newStatus != enums.OccurrenceStatus.reprovada) {
      throw ArgumentError(
          'Status inválido. Use apenas enums.OccurrenceStatus.aprovada ou enums.OccurrenceStatus.reprovada');
    }

    // Obtém informações do administrador autenticado
    final adminInfo = await _getAuthenticatedAdminInfo();

    // Prepara os dados para atualização no Firestore
    // *** CORREÇÃO CRÍTICA: Usando nomes de campo do modelo PointOccurrence ***
    final Map<String, dynamic> updateData = {
      'status': newStatus.toJsonString(), // <-- Usa método do enum importado
      'approvedRejectedBy': adminInfo.id, // <-- Nome correto do modelo
      'approvedRejectedByName':
          adminInfo.displayName, // <-- Nome correto do modelo
      'approvedRejectedAt': Timestamp.now(), // <-- Nome correto do modelo
    };

    // Executa a atualização no Firestore com tratamento de erros
    await _updateFirestoreDocument(occurrenceId, updateData, newStatus);

    // Exemplo: Notificar ouvintes, se necessário no futuro
    // notifyListeners();
  }

  /// Obtém informações do administrador autenticado.
  ///
  /// Retorna um objeto com ID e nome do administrador.
  /// Lança Exception se nenhum administrador estiver autenticado.
  Future<_AdminInfo> _getAuthenticatedAdminInfo() async {
    final adminUser = _auth.currentUser;
    if (adminUser == null) {
      throw Exception(
          "Erro de autenticação: Nenhum administrador está autenticado.");
    }

    final String adminId = adminUser.uid;

    // Busca o nome do administrador no Firestore para maior precisão
    String adminName;
    try {
      // Tentativa de buscar o nome atualizado do Firestore
      final adminDoc = await _firestore.collection('users').doc(adminId).get();
      // Verifica se doc existe E TEM DADOS antes de acessar
      if (adminDoc.exists && adminDoc.data() != null) {
        adminName = adminDoc.data()!['displayName'] as String? ??
            adminUser.displayName ??
            "Admin (sem nome)";
      } else {
        adminName = adminUser.displayName ??
            "Admin (sem nome)"; // Fallback se doc não existe
      }
    } catch (e) {
      // Fallback para o displayName do Auth em caso de erro na busca
      adminName = adminUser.displayName ?? "Admin (sem nome)";
      _logDebug(
          'Erro ao buscar nome do admin no Firestore: $e. Usando nome do Auth.');
    }

    return _AdminInfo(adminId, adminName);
  }

  /// Atualiza um documento no Firestore com tratamento de erros.
  Future<void> _updateFirestoreDocument(
    String documentId,
    Map<String, dynamic> data,
    enums.OccurrenceStatus newStatus, // Passado para logging claro com prefixo
  ) async {
    try {
      _logDebug(
          'Atualizando ocorrência $documentId para ${newStatus.toJsonString()} ' // <-- Usa método do enum importado
          'por admin ${data['approvedRejectedBy']} (${data['approvedRejectedByName']})' // Log com nomes corretos
          );

      // Verifica primeiro se o documento existe para evitar erros desnecessários
      final docSnapshot = await _occurrencesCollection.doc(documentId).get();
      if (!docSnapshot.exists) {
        _logDebug('Tentativa de atualizar documento inexistente: $documentId');
        throw Exception('Ocorrência com ID $documentId não encontrada.');
      }

      // Realiza a atualização
      await _occurrencesCollection.doc(documentId).update(data);
      _logDebug('Ocorrência $documentId atualizada com sucesso.');
    } on FirebaseException catch (e) {
      // Erro específico do Firestore (ex: permissões)
      _logDebug(
          'Erro Firestore ao atualizar ocorrência $documentId: ${e.code} - ${e.message}');
      throw Exception(
          'Falha ao atualizar status da ocorrência no Firestore: ${e.message}');
    } catch (e) {
      // Outros erros inesperados
      _logDebug('Erro inesperado ao atualizar ocorrência $documentId: $e');
      throw Exception('Ocorreu um erro inesperado durante a atualização: $e');
    }
  }

  /// Obtém uma ocorrência específica pelo ID.
  ///
  /// Retorna `null` se a ocorrência não for encontrada.
  /// Lança [ArgumentError] se o ID for inválido.
  /// Pode lançar [FirebaseException] ou outras exceções em caso de erro.
  Future<Map<String, dynamic>?> getOccurrenceById(String occurrenceId) async {
    if (occurrenceId.isEmpty) {
      throw ArgumentError('O ID da ocorrência não pode ser vazio');
    }

    try {
      final doc = await _occurrencesCollection.doc(occurrenceId).get();
      // Retorna os dados como Map se o documento existir, caso contrário null
      return doc.exists ? doc.data() as Map<String, dynamic> : null;
    } catch (e) {
      _logDebug('Erro ao buscar ocorrência $occurrenceId: $e');
      // Rethrow a exceção para que a camada chamadora possa tratá-la
      rethrow;
    }
  }

  // --- MÉTODO getIncidentTypes ---
  /// Busca todos os tipos de ocorrência ativos no Firestore
  ///
  /// Retorna uma lista de objetos [IncidentType] para uso na configuração
  /// de regras automáticas e outras funcionalidades do sistema.
  Future<List<IncidentType>> getIncidentTypes() async {
    try {
      // Usa a instância _firestore da classe de serviço
      final querySnapshot = await _firestore
          .collection(incidentTypesCollectionName) // Usa a constante
          .where('isActive', isEqualTo: true)
          // --- !!! ADICIONADO: Ordenação por nome !!! ---
          .orderBy('name') // Ordena alfabeticamente para Dropdowns
          .get();

      // Converte os documentos para objetos IncidentType
      final incidentTypes = querySnapshot.docs
          .map((doc) => IncidentType.fromSnapshot(
              doc)) // Usa o método do modelo IncidentType
          .toList();

      _logDebug('Tipos de ocorrência ativos buscados: ${incidentTypes.length}');
      return incidentTypes;
    } catch (e) {
      _logDebug('Erro ao buscar tipos de ocorrência: $e');
      // Lança a exceção para a UI tratar
      throw Exception("Falha ao buscar tipos de ocorrência: ${e.toString()}");
      // return []; // Alternativa comentada: retornar lista vazia
    }
  }
  // --- FIM DO MÉTODO getIncidentTypes ---

  /// Registra mensagens de debug apenas em modo de desenvolvimento.
  void _logDebug(String message) {
    if (kDebugMode) {
      // Adiciona um prefixo para identificar facilmente logs deste serviço
      debugPrint('[PointOccurrenceService] $message');
    }
  }
} // Fim da classe PointOccurrenceService

/// Classe auxiliar privada para agrupar informações do administrador.
class _AdminInfo {
  final String id;
  final String displayName;

  _AdminInfo(this.id, this.displayName);
}
