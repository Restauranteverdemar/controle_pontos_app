// lib/features/admin/screens/aprovacao_pendentes_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/point_occurrence.dart' hide OccurrenceStatus;
import '../../shared/enums/occurrence_status.dart';
import '../../shared/services/point_occurrence_service.dart';
import '../../shared/screens/occurrence_detail_modal.dart'; // Importação do modal de detalhes
import '../../shared/screens/edit_occurrence_modal.dart'; // Importação do modal de edição
import '../../shared/widgets/full_screen_media_viewer.dart'; // Importação do visualizador em tela cheia

class AprovacaoPendentesPage extends StatefulWidget {
  const AprovacaoPendentesPage({super.key});

  @override
  State<AprovacaoPendentesPage> createState() => _AprovacaoPendentesPageState();
}

class _AprovacaoPendentesPageState extends State<AprovacaoPendentesPage> {
  // Inicialização do serviço para separar lógica de negócios da UI
  final PointOccurrenceService _occurrenceService = PointOccurrenceService();
  bool _isLoading = false;

  // Formatador de data para reuso
  final DateFormat _dateFormat = DateFormat('dd/MM/yy HH:mm');

  // Mapa para armazenar os dados originais de cada ocorrência
  final Map<String, Map<String, dynamic>> _originalData = {};

  // Stream otimizado com tipagem adequada
  Stream<List<DocumentSnapshot>> _getPendingOccurrencesStream() {
    return FirebaseFirestore.instance
        .collection('pointsOccurrences')
        .where('status', isEqualTo: OccurrenceStatus.pendente.toJsonString())
        .orderBy('registeredAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  // Métodos de aprovação/reprovação simplificados
  Future<void> _approveOccurrence(PointOccurrence occurrence) async {
    await _processOccurrence(occurrence, OccurrenceStatus.aprovada);
  }

  Future<void> _rejectOccurrence(PointOccurrence occurrence) async {
    await _processOccurrence(occurrence, OccurrenceStatus.reprovada);
  }

  // Método centralizado para processar ocorrências
  Future<void> _processOccurrence(
      PointOccurrence occurrence, OccurrenceStatus newStatus) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      // Utiliza o serviço para processar a ocorrência
      await _occurrenceService.updateOccurrenceStatus(
        occurrence.id,
        newStatus,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${newStatus == OccurrenceStatus.aprovada ? 'Aprovada' : 'Reprovada'} com sucesso!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      _handleError(e, newStatus);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Método extraído para tratamento de erros
  void _handleError(Object error, OccurrenceStatus actionType) {
    print('Erro ao processar ocorrência: $error');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Erro ao ${actionType == OccurrenceStatus.aprovada ? 'aprovar' : 'reprovar'} ocorrência.'),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprovar Ocorrências Pendentes'),
      ),
      body: Stack(
        children: [
          _buildOccurrencesList(),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  // Widget extraído para a lista de ocorrências
  Widget _buildOccurrencesList() {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: _getPendingOccurrencesStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print('Erro ao buscar ocorrências: ${snapshot.error}');
          return const Center(
            child: Text('Erro ao carregar ocorrências pendentes.'),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final occurrenceDocs = snapshot.data ?? [];

        if (occurrenceDocs.isEmpty) {
          return const Center(
            child: Text('Nenhuma ocorrência pendente encontrada.'),
          );
        }

        // Limpa os dados originais anteriores
        _originalData.clear();

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: occurrenceDocs.length,
          itemBuilder: (context, index) {
            // Primeiro obtemos os dados brutos do Firestore
            final docSnapshot = occurrenceDocs[index];
            final String occurrenceId = docSnapshot.id;
            final Map<String, dynamic> occurrenceData =
                docSnapshot.data() as Map<String, dynamic>;

            // Armazena os dados originais para uso posterior
            _originalData[occurrenceId] = occurrenceData;

            // Criar o objeto PointOccurrence a partir dos dados
            final occurrence =
                PointOccurrence.fromJson(occurrenceId, occurrenceData);

            return _buildOccurrenceCard(context, occurrence, occurrenceId);
          },
        );
      },
    );
  }

  // Widget extraído para o overlay de carregamento
  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  // Widget refatorado para o card de ocorrência
  Widget _buildOccurrenceCard(
      BuildContext context, PointOccurrence occurrence, String occurrenceId) {
    final textTheme = Theme.of(context).textTheme;

    // Obter anexos dos dados originais
    List<Map<String, dynamic>> attachments =
        _getAttachmentsFromOriginalData(occurrenceId);
    bool hasAttachments = attachments.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 2.0,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho do card
            _buildCardHeader(occurrence, textTheme),

            // Descrição opcional
            if (occurrence.notes != null && occurrence.notes!.isNotEmpty)
              _buildCardDescription(occurrence.notes!, textTheme),

            // Anexos (renderizados diretamente)
            if (hasAttachments) _buildAttachmentsPreview(attachments),

            const Divider(height: 16),

            // Informações detalhadas
            _buildDetailRow('Funcionário:', occurrence.employeeName),
            _buildDetailRow('Data Ocorrência:',
                _dateFormat.format(occurrence.occurrenceDate.toDate())),
            _buildDetailRow('Registrado por:', occurrence.registeredByName),

            const Divider(height: 16),

            // Botões de ação
            _buildActionButtons(occurrence, occurrenceId),
          ],
        ),
      ),
    );
  }

  // Componentes extraídos para melhor organização do card
  Widget _buildCardHeader(PointOccurrence occurrence, TextTheme textTheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título
        Expanded(
          child: Text(
            occurrence.incidentName,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${occurrence.finalPoints} pts',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: occurrence.finalPoints >= 0 ? Colors.blue : Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildCardDescription(String description, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
      child: Text(
        description,
        style: textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 5),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  // Widget para botões de ação corrigido para evitar overflow
  Widget _buildActionButtons(PointOccurrence occurrence, String occurrenceId) {
    // Reorganizar os botões para evitar overflow
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primeira linha com botões de detalhes e edição
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Botão para ver detalhes
            Expanded(
              child: TextButton.icon(
                icon:
                    const Icon(Icons.visibility, color: Colors.blue, size: 20),
                label: const Text('Detalhes',
                    style: TextStyle(color: Colors.blue, fontSize: 13)),
                onPressed: _isLoading
                    ? null
                    : () => _showOccurrenceDetails(occurrence, occurrenceId),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ),
            // Botão para editar (novo)
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                label: const Text('Editar',
                    style: TextStyle(color: Colors.blue, fontSize: 13)),
                onPressed: _isLoading
                    ? null
                    : () => _editOccurrence(occurrence, occurrenceId),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8), // Espaçamento entre as linhas

        // Segunda linha com botões de aprovação/reprovação
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Botão de reprovação
            TextButton.icon(
              icon: const Icon(Icons.close, color: Colors.red, size: 20),
              label: const Text('Reprovar',
                  style: TextStyle(color: Colors.red, fontSize: 13)),
              onPressed:
                  _isLoading ? null : () => _rejectOccurrence(occurrence),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
            const SizedBox(width: 8),
            // Botão de aprovação
            ElevatedButton.icon(
              icon: const Icon(Icons.check, color: Colors.white, size: 20),
              label: const Text('Aprovar', style: TextStyle(fontSize: 13)),
              onPressed:
                  _isLoading ? null : () => _approveOccurrence(occurrence),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Verifica se a ocorrência tem anexos (usando dados originais)
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

  // Método para abrir o modal de edição (novo)
  void _editOccurrence(PointOccurrence occurrence, String occurrenceId) {
    // Verifica se temos os dados originais desta ocorrência
    if (!_originalData.containsKey(occurrenceId)) {
      debugPrint(
          'ERRO: Dados originais não encontrados para ocorrência $occurrenceId');
      showEditOccurrenceModal(context, occurrence, null);
      return;
    }

    // Passa os dados originais para o modal
    final originalData = _originalData[occurrenceId]!;
    showEditOccurrenceModal(context, occurrence, originalData);
  }

  // Abre o modal de detalhes da ocorrência com parâmetro isAdmin=true
  void _showOccurrenceDetails(PointOccurrence occurrence, String occurrenceId) {
    // Verifica se temos os dados originais desta ocorrência
    if (!_originalData.containsKey(occurrenceId)) {
      debugPrint(
          'ERRO: Dados originais não encontrados para ocorrência $occurrenceId');
      showOccurrenceDetailModal(context, occurrence, null, isAdmin: true);
      return;
    }

    // Passa os dados originais para o modal
    final originalData = _originalData[occurrenceId]!;
    showOccurrenceDetailModal(context, occurrence, originalData, isAdmin: true);
  }

  // Método para extrair os anexos dos dados originais
  List<Map<String, dynamic>> _getAttachmentsFromOriginalData(
      String occurrenceId) {
    List<Map<String, dynamic>> result = [];

    // Verifica se temos os dados originais desta ocorrência
    if (!_originalData.containsKey(occurrenceId)) {
      return result;
    }

    final data = _originalData[occurrenceId]!;

    // Verifica anexo no formato antigo
    if (data.containsKey('attachmentUrl')) {
      final attachmentUrl = data['attachmentUrl'];
      if (attachmentUrl != null &&
          attachmentUrl is String &&
          attachmentUrl.isNotEmpty) {
        result.add({
          'url': attachmentUrl,
          'type': 'image', // Assumimos imagem por padrão
          'name': 'Anexo'
        });
      }
    }

    // Verifica anexos no formato novo
    if (data.containsKey('attachments')) {
      final attachments = data['attachments'];
      if (attachments != null &&
          attachments is List &&
          attachments.isNotEmpty) {
        for (final attachment in attachments) {
          if (attachment is Map) {
            final url = attachment['url']?.toString() ?? '';
            final type = attachment['type']?.toString() ?? 'image';
            final name = attachment['name']?.toString() ?? 'Anexo';

            if (url.isNotEmpty) {
              result.add({'url': url, 'type': type, 'name': name});
            }
          }
        }
      }
    }

    return result;
  }
}

// Widget para exibir os anexos no card
Widget _buildAttachmentsPreview(List<Map<String, dynamic>> attachments) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attachments.isNotEmpty)
          Container(
            height: 120, // Altura fixa para a galeria
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: attachments.length,
              itemBuilder: (context, index) {
                final attachment = attachments[index];
                final String url = attachment['url'] as String? ?? '';
                final String type = attachment['type'] as String? ?? 'image';
                final String name = attachment['name'] as String? ?? 'Anexo';

                return GestureDetector(
                  onTap: () => openFullScreenMedia(context, url, type, name),
                  child: Container(
                    width: 120, // Largura fixa para cada item
                    margin: const EdgeInsets.only(right: 8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Expanded(
                          child: type == 'video'
                              ? Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      color: Colors.black,
                                      child: const Center(
                                        child: Icon(
                                          Icons.play_circle_fill,
                                          color: Colors.white,
                                          size: 36,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 5,
                                      right: 5,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'VÍDEO',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[200],
                                      child: const Center(
                                        child: Icon(
                                          Icons.broken_image,
                                          color: Colors.grey,
                                          size: 36,
                                        ),
                                      ),
                                    );
                                  },
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                            : null,
                                      ),
                                    );
                                  },
                                ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 4),
                          width: double.infinity,
                          color: Colors.grey[200],
                          child: Text(
                            name.length > 10
                                ? name.substring(0, 8) + '...'
                                : name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    ),
  );
}
