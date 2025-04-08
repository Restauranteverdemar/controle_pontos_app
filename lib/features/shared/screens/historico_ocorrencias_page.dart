// lib/features/shared/screens/historico_ocorrencias_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../shared/models/point_occurrence.dart';
import 'occurrence_detail_modal.dart';
import 'edit_occurrence_modal.dart'; // Novo import para o modal de edição

class HistoricoOcorrenciasPage extends StatefulWidget {
  const HistoricoOcorrenciasPage({Key? key}) : super(key: key);

  @override
  State<HistoricoOcorrenciasPage> createState() =>
      _HistoricoOcorrenciasPageState();
}

class _HistoricoOcorrenciasPageState extends State<HistoricoOcorrenciasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isAdmin = false;
  String _filterStatus =
      'Todos'; // 'Todos', 'Pendente', 'Aprovada', 'Reprovada'
  bool _isLoading = true;
  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy HH:mm');

  // Mapa para armazenar os dados originais de cada ocorrência
  final Map<String, Map<String, dynamic>> _originalData = {};

  @override
  void initState() {
    super.initState();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    setState(() => _isLoading = true);
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser != null) {
        final userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();
        if (userDoc.exists) {
          setState(() {
            _isAdmin = userDoc.get('role') == 'Admin';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao verificar papel do usuário: $e');
      setState(() => _isLoading = false);
    }
  }

  Stream<QuerySnapshot> _getOccurrencesStream() {
    Query query = _firestore.collection('pointsOccurrences');

    // Se não for admin, filtra por userId do funcionário atual
    if (!_isAdmin) {
      query = query.where('userId', isEqualTo: _auth.currentUser?.uid);
    }

    // Filtra por status se não for 'Todos'
    if (_filterStatus != 'Todos') {
      query = query.where('status', isEqualTo: _filterStatus);
    }

    // Ordena por data decrescente (mais recente primeiro)
    return query.orderBy('occurrenceDate', descending: true).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(_isAdmin ? 'Histórico de Ocorrências' : 'Minhas Ocorrências'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (String value) {
              setState(() {
                _filterStatus = value;
              });
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'Todos',
                child: Text('Todos os Status'),
              ),
              const PopupMenuItem<String>(
                value: 'Pendente',
                child: Text('Pendentes'),
              ),
              const PopupMenuItem<String>(
                value: 'Aprovada',
                child: Text('Aprovadas'),
              ),
              const PopupMenuItem<String>(
                value: 'Reprovada',
                child: Text('Reprovadas'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: _getOccurrencesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                      child: Text(
                          'Erro ao carregar ocorrências: ${snapshot.error}'));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                      child: Text('Nenhuma ocorrência encontrada.'));
                }

                final occurrences = snapshot.data!.docs;
                _originalData.clear(); // Limpa os dados anteriores

                return ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: occurrences.length,
                  itemBuilder: (context, index) {
                    // Primeiro obtemos os dados brutos do Firestore
                    final Map<String, dynamic> occurrenceData =
                        occurrences[index].data() as Map<String, dynamic>;
                    final String occurrenceId = occurrences[index].id;

                    // Armazena os dados originais para uso posterior
                    _originalData[occurrenceId] = occurrenceData;

                    // Criar o objeto PointOccurrence a partir dos dados
                    final occurrence =
                        PointOccurrence.fromJson(occurrenceId, occurrenceData);

                    return _buildOccurrenceCard(occurrence, occurrenceId);
                  },
                );
              },
            ),
    );
  }

  Widget _buildOccurrenceCard(PointOccurrence occurrence, String occurrenceId) {
    // Cor baseada no status
    Color statusColor;
    switch (occurrence.status) {
      case OccurrenceStatus.Aprovada:
        statusColor = Colors.green;
        break;
      case OccurrenceStatus.Pendente:
        statusColor = Colors.orange;
        break;
      case OccurrenceStatus.Reprovada:
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    // Verifica anexos diretamente dos dados originais
    bool hasAttachments = _checkAttachmentsFromOriginalData(occurrenceId);

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: BorderSide(color: statusColor, width: 2.0),
      ),
      elevation: 4.0,
      child: InkWell(
        onTap: () => _showOccurrenceDetails(occurrence, occurrenceId),
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título e descrição (lado esquerdo)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                occurrence.incidentName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: statusColor),
                              ),
                              child: Text(
                                occurrence.status.displayValue,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (occurrence.notes != null &&
                            occurrence.notes!.isNotEmpty)
                          Text(
                            occurrence.notes!,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // Pontos e data (lado direito)
                  Container(
                    margin: const EdgeInsets.only(left: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${occurrence.finalPoints} pts',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: occurrence.finalPoints >= 0
                                ? Colors.green[700]
                                : Colors.red[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'por ${occurrence.registeredByName}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dateFormatter
                              .format(occurrence.occurrenceDate.toDate()),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Indicador de anexo
              if (hasAttachments)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.attach_file,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Contém anexo',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _checkAttachmentsFromOriginalData(String occurrenceId) {
    // Verifica se temos os dados originais desta ocorrência
    if (!_originalData.containsKey(occurrenceId)) {
      return false;
    }

    final data = _originalData[occurrenceId]!;

    // Verifica anexo no formato antigo
    if (data.containsKey('attachmentUrl')) {
      final attachmentUrl = data['attachmentUrl'];
      if (attachmentUrl != null &&
          attachmentUrl is String &&
          attachmentUrl.isNotEmpty) {
        return true;
      }
    }

    // Verifica anexos no formato novo
    if (data.containsKey('attachments')) {
      final attachments = data['attachments'];
      if (attachments != null &&
          attachments is List &&
          attachments.isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  // Método atualizado para passar isAdmin para o modal, permitindo edição apenas no modal
  void _showOccurrenceDetails(PointOccurrence occurrence, String occurrenceId) {
    // Verifica se temos os dados originais desta ocorrência
    if (!_originalData.containsKey(occurrenceId)) {
      debugPrint(
          'ERRO: Dados originais não encontrados para ocorrência $occurrenceId');
      // Passa o parâmetro isAdmin ao abrir o modal de detalhes
      showOccurrenceDetailModal(context, occurrence, null, isAdmin: _isAdmin);
      return;
    }

    // Passa os dados originais e o parâmetro isAdmin para o modal
    final originalData = _originalData[occurrenceId]!;
    showOccurrenceDetailModal(context, occurrence, originalData,
        isAdmin: _isAdmin);
  }
}
