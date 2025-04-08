// lib/features/shared/screens/occurrence_detail_modal.dart
// Com modificações para adicionar o ícone de edição para admins

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/models/point_occurrence.dart';
import '../widgets/full_screen_media_viewer.dart';
import 'edit_occurrence_modal.dart'; // Novo import para o modal de edição

/// Mostra um modal com detalhes da ocorrência, incluindo anexos.
///
/// Esta função recebe tanto o modelo PointOccurrence quanto os dados originais
/// do Firestore para permitir acesso aos campos não mapeados no modelo.
/// O parâmetro isAdmin controla a visibilidade do botão de edição.
void showOccurrenceDetailModal(BuildContext context, PointOccurrence occurrence,
    Map<String, dynamic>? originalData,
    {bool isAdmin = false}) {
  // Adicionado parâmetro isAdmin
  showDialog(
    context: context,
    builder: (BuildContext context) => OccurrenceDetailModal(
      occurrence: occurrence,
      originalData: originalData,
      isAdmin: isAdmin, // Passando o parâmetro isAdmin
    ),
  );
}

class OccurrenceDetailModal extends StatefulWidget {
  final PointOccurrence occurrence;
  final Map<String, dynamic>? originalData;
  final bool isAdmin; // Adicionado um novo campo para verificar se é admin

  const OccurrenceDetailModal({
    Key? key,
    required this.occurrence,
    this.originalData,
    this.isAdmin = false, // Com valor padrão false
  }) : super(key: key);

  @override
  State<OccurrenceDetailModal> createState() => _OccurrenceDetailModalState();
}

class _OccurrenceDetailModalState extends State<OccurrenceDetailModal> {
  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy HH:mm');
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _attachments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  void _loadAttachments() {
    setState(() => _isLoading = true);

    try {
      _attachments = [];
      debugPrint(
          'Iniciando carregamento de anexos para ocorrência ${widget.occurrence.id}');

      // Primeiro tentamos obter anexos do formato antigo via modelo
      if (widget.occurrence.attachmentUrl != null &&
          widget.occurrence.attachmentUrl!.isNotEmpty) {
        debugPrint(
            'Encontrado anexo no formato antigo via modelo: ${widget.occurrence.attachmentUrl}');
        _attachments.add({
          'url': widget.occurrence.attachmentUrl!,
          'type': 'image', // Assumimos imagem por padrão
          'name': 'Anexo'
        });
      }

      // Tentamos usar os dados originais do Firestore se disponíveis
      if (widget.originalData != null) {
        debugPrint('Usando dados originais para buscar anexos');

        // Verifica anexo no formato antigo nos dados originais
        if (widget.originalData!.containsKey('attachmentUrl')) {
          final attachmentUrl = widget.originalData!['attachmentUrl'];
          if (attachmentUrl != null &&
              attachmentUrl is String &&
              attachmentUrl.isNotEmpty) {
            debugPrint(
                'Encontrado anexo no formato antigo via dados originais: $attachmentUrl');
            // Só adiciona se já não foi adicionado antes
            if (_attachments.isEmpty ||
                _attachments[0]['url'] != attachmentUrl) {
              _attachments.add(
                  {'url': attachmentUrl, 'type': 'image', 'name': 'Anexo'});
            }
          }
        }

        // Verifica anexos no formato novo (attachments como lista)
        if (widget.originalData!.containsKey('attachments')) {
          final attachmentsData = widget.originalData!['attachments'];

          if (attachmentsData != null &&
              attachmentsData is List &&
              attachmentsData.isNotEmpty) {
            debugPrint(
                'Encontrado ${attachmentsData.length} anexos no formato lista');

            for (int i = 0; i < attachmentsData.length; i++) {
              final attachment = attachmentsData[i];
              debugPrint('Processando anexo $i: $attachment');

              if (attachment is Map) {
                // Extrai informações com verificação de tipo
                final String url = attachment['url']?.toString() ?? '';
                final String type = attachment['type']?.toString() ?? 'image';
                final String name =
                    attachment['name']?.toString() ?? 'Anexo ${i + 1}';

                if (url.isNotEmpty) {
                  debugPrint('Adicionando anexo: $url ($type) - $name');
                  _attachments.add({'url': url, 'type': type, 'name': name});
                }
              }
            }
          }
        }
      } else {
        debugPrint('Dados originais não disponíveis para esta ocorrência');
      }

      debugPrint('Total de anexos carregados: ${_attachments.length}');
    } catch (e) {
      debugPrint('Erro ao carregar anexos: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Método para abrir o modal de edição
  void _openEditModal() {
    // Fechamos o modal atual
    Navigator.of(context).pop();

    // Abrimos o modal de edição
    showEditOccurrenceModal(
      context,
      widget.occurrence,
      widget.originalData,
    );
  }

  @override
  Widget build(BuildContext context) {
    final occurrence = widget.occurrence;

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

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10.0,
              offset: Offset(0.0, 10.0),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      occurrence.incidentName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      // Botão de edição apenas para Admin
                      if (widget.isAdmin)
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          tooltip: 'Editar ocorrência',
                          onPressed: _openEditModal,
                        ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          occurrence.status.displayValue,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // O restante do conteúdo permanece igual
            // Conteúdo com scroll
            Flexible(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Informações do funcionário
                      _buildInfoSection(
                        'Funcionário',
                        [
                          _buildInfoItem('Nome', occurrence.employeeName),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Informações do incidente
                      _buildInfoSection(
                        'Detalhes da Ocorrência',
                        [
                          _buildInfoItem('Tipo', occurrence.incidentName),
                          _buildInfoItem(
                              'Data/Hora',
                              _dateFormatter
                                  .format(occurrence.occurrenceDate.toDate())),
                          _buildInfoItem('Pontos Padrão',
                              occurrence.defaultPoints.toString()),
                          if (occurrence.manualPointsAdjustment != null)
                            _buildInfoItem('Ajuste Manual',
                                occurrence.manualPointsAdjustment.toString()),
                          _buildInfoItem(
                            'Pontos Finais',
                            '${occurrence.finalPoints.toString()} ${occurrence.finalPoints >= 0 ? "(positivo)" : "(negativo)"}',
                            valueColor: occurrence.finalPoints >= 0
                                ? Colors.green[700]
                                : Colors.red[700],
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Informações de registro e aprovação
                      _buildInfoSection(
                        'Registro e Aprovação',
                        [
                          _buildInfoItem(
                              'Registrado por', occurrence.registeredByName),
                          _buildInfoItem(
                              'Data do Registro',
                              _dateFormatter
                                  .format(occurrence.registeredAt.toDate())),
                          if (occurrence.approvedRejectedByName != null)
                            _buildInfoItem(
                                occurrence.status == OccurrenceStatus.Aprovada
                                    ? 'Aprovado por'
                                    : 'Reprovado por',
                                occurrence.approvedRejectedByName ?? ''),
                          if (occurrence.approvedRejectedAt != null)
                            _buildInfoItem(
                                occurrence.status == OccurrenceStatus.Aprovada
                                    ? 'Data de Aprovação'
                                    : 'Data de Reprovação',
                                _dateFormatter.format(
                                    occurrence.approvedRejectedAt!.toDate())),
                        ],
                      ),

                      if (occurrence.notes != null &&
                          occurrence.notes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildInfoSection(
                          'Observações',
                          [
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                occurrence.notes!,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // Seção de anexos
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildAttachmentSection(),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Botão de fechar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Fechar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const Divider(),
        ...children,
      ],
    );
  }

  Widget _buildInfoItem(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label + ':',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentSection() {
    return _buildInfoSection(
      'Anexos',
      [
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_attachments.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text('Nenhum anexo disponível.'),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: _attachments.length,
              itemBuilder: (context, index) {
                final attachment = _attachments[index];
                final String url = attachment['url'] as String;
                final String type = attachment['type'] as String;
                final String name = attachment['name'] as String;

                return _buildAttachmentItem(url, type, name);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildAttachmentItem(String url, String type, String name) {
    debugPrint('Renderizando anexo: $url ($type)');

    return GestureDetector(
      onTap: () => openFullScreenMedia(context, url, type, name),
      child: Container(
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
                              size: 48,
                            ),
                          ),
                        ),
                        // Indicador de vídeo no canto
                        Positioned(
                          bottom: 5,
                          right: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'VÍDEO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : url.isNotEmpty
                      ? Image.network(
                          url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint('Erro ao carregar imagem: $error');
                            return Container(
                              color: Colors.grey[200],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.broken_image,
                                    color: Colors.grey,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Erro ao carregar',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[700],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes !=
                                        null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported,
                              color: Colors.grey,
                              size: 40,
                            ),
                          ),
                        ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              width: double.infinity,
              color: Colors.grey[200],
              child: Text(
                name.length > 15 ? name.substring(0, 12) + '...' : name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
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
  }

  void _openAttachment(String url, String type) {
    openFullScreenMedia(context, url, type, 'Anexo');
  }
}
