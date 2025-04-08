// lib/features/shared/screens/edit_occurrence_modal.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/models/point_occurrence.dart';
import '../../shared/services/point_occurrence_service.dart';
import '../widgets/full_screen_media_viewer.dart';

/// Mostra um modal para edição de ocorrências, onde administradores podem
/// editar detalhes, alterar status e excluir ocorrências.
void showEditOccurrenceModal(BuildContext context, PointOccurrence occurrence,
    Map<String, dynamic>? originalData) {
  showDialog(
    context: context,
    builder: (BuildContext context) => EditOccurrenceModal(
      occurrence: occurrence,
      originalData: originalData,
    ),
  );
}

class EditOccurrenceModal extends StatefulWidget {
  final PointOccurrence occurrence;
  final Map<String, dynamic>? originalData;

  const EditOccurrenceModal({
    Key? key,
    required this.occurrence,
    this.originalData,
  }) : super(key: key);

  @override
  State<EditOccurrenceModal> createState() => _EditOccurrenceModalState();
}

class _EditOccurrenceModalState extends State<EditOccurrenceModal> {
  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy HH:mm');
  final PointOccurrenceService _occurrenceService = PointOccurrenceService();

  // Controladores de texto para campos editáveis
  late TextEditingController _notesController;
  late TextEditingController _manualPointsController;

  // Status selecionado
  late OccurrenceStatus _selectedStatus;

  // Estados
  bool _isLoading = false;
  List<Map<String, dynamic>> _attachments = [];
  bool _loadingAttachments = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Inicializar controladores
    _notesController =
        TextEditingController(text: widget.occurrence.notes ?? '');
    _manualPointsController = TextEditingController(
        text: widget.occurrence.manualPointsAdjustment?.toString() ?? '0');
    _selectedStatus = widget.occurrence.status;
    _selectedDate = widget.occurrence.occurrenceDate.toDate();
    _loadAttachments();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _manualPointsController.dispose();
    super.dispose();
  }

  void _loadAttachments() {
    setState(() => _loadingAttachments = true);

    try {
      _attachments = [];

      // Lógica para carregar anexos (igual à do OccurrenceDetailModal)
      if (widget.occurrence.attachmentUrl != null &&
          widget.occurrence.attachmentUrl!.isNotEmpty) {
        _attachments.add({
          'url': widget.occurrence.attachmentUrl!,
          'type': 'image',
          'name': 'Anexo'
        });
      }

      if (widget.originalData != null) {
        // Verifica anexo no formato antigo nos dados originais
        if (widget.originalData!.containsKey('attachmentUrl')) {
          final attachmentUrl = widget.originalData!['attachmentUrl'];
          if (attachmentUrl != null &&
              attachmentUrl is String &&
              attachmentUrl.isNotEmpty) {
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
            for (int i = 0; i < attachmentsData.length; i++) {
              final attachment = attachmentsData[i];

              if (attachment is Map) {
                final String url = attachment['url']?.toString() ?? '';
                final String type = attachment['type']?.toString() ?? 'image';
                final String name =
                    attachment['name']?.toString() ?? 'Anexo ${i + 1}';

                if (url.isNotEmpty) {
                  _attachments.add({'url': url, 'type': type, 'name': name});
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar anexos: $e');
    } finally {
      setState(() => _loadingAttachments = false);
    }
  }

  // Método para salvar as alterações
  Future<void> _saveChanges() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      // Preparar dados atualizados
      final updatedData = <String, dynamic>{};

      // Atualizar notas se alteradas
      if (_notesController.text != widget.occurrence.notes) {
        updatedData['notes'] = _notesController.text;
      }

      // Atualizar ajuste manual de pontos se alterado
      final manualPoints = int.tryParse(_manualPointsController.text) ?? 0;
      if (manualPoints != (widget.occurrence.manualPointsAdjustment ?? 0)) {
        updatedData['manualPointsAdjustment'] = manualPoints;

        // Recalcular pontos finais
        updatedData['finalPoints'] =
            widget.occurrence.defaultPoints + manualPoints;
      }

      // Atualizar status se alterado
      if (_selectedStatus != widget.occurrence.status) {
        updatedData['status'] = _selectedStatus.toJsonString();

        // Se o status mudou para Aprovado ou Reprovado, adicionar campos relevantes
        if (_selectedStatus == OccurrenceStatus.Aprovada ||
            _selectedStatus == OccurrenceStatus.Reprovada) {
          final currentUser = FirebaseAuth.instance.currentUser;
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser!.uid)
              .get();

          final userName = userDoc.data()?['displayName'] ?? currentUser.email;

          updatedData['approvedRejectedBy'] = currentUser.uid;
          updatedData['approvedRejectedByName'] = userName;
          updatedData['approvedRejectedAt'] = FieldValue.serverTimestamp();
        } else if (_selectedStatus == OccurrenceStatus.Pendente) {
          // Se voltou para pendente, remover campos de aprovação/rejeição
          updatedData['approvedRejectedBy'] = FieldValue.delete();
          updatedData['approvedRejectedByName'] = FieldValue.delete();
          updatedData['approvedRejectedAt'] = FieldValue.delete();
        }
      }

      // Atualizar data da ocorrência se alterada
      if (_selectedDate
              .difference(widget.occurrence.occurrenceDate.toDate())
              .inMinutes !=
          0) {
        updatedData['occurrenceDate'] = Timestamp.fromDate(_selectedDate);
      }

      // Se houve mudanças, atualizar no Firestore
      if (updatedData.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('pointsOccurrences')
            .doc(widget.occurrence.id)
            .update(updatedData);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ocorrência atualizada com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nenhuma alteração detectada.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao salvar alterações: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Método para excluir a ocorrência
  Future<void> _deleteOccurrence() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirmar exclusão'),
            content: const Text(
                'Esta ação não pode ser desfeita. Deseja realmente excluir esta ocorrência?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('pointsOccurrences')
          .doc(widget.occurrence.id)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ocorrência excluída com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Erro ao excluir ocorrência: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  // Método para abrir seletor de data
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      // Após selecionar a data, abre o seletor de hora
      final TimeOfDay? timeOfDay = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
      );

      if (timeOfDay != null) {
        setState(() {
          _selectedDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            timeOfDay.hour,
            timeOfDay.minute,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cabeçalho
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit, color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Editar Ocorrência',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Conteúdo com scroll
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Informações não editáveis
                        _buildInfoSection(
                          'Informações',
                          [
                            _buildInfoItem(
                                'Funcionário', widget.occurrence.employeeName),
                            _buildInfoItem(
                                'Tipo', widget.occurrence.incidentName),
                            _buildInfoItem('Pontos Padrão',
                                widget.occurrence.defaultPoints.toString()),
                            _buildInfoItem('Registrado por',
                                widget.occurrence.registeredByName),
                            _buildInfoItem(
                                'Data do Registro',
                                _dateFormatter.format(
                                    widget.occurrence.registeredAt.toDate())),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Campos editáveis
                        _buildEditableSection(),

                        // Anexos
                        if (_attachments.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildAttachmentsSection(),
                        ],
                      ],
                    ),
                  ),
                ),

                // Botões de ação - CORRIGIDO PARA EVITAR OVERFLOW
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Botão para excluir
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _deleteOccurrence,
                        icon: const Icon(Icons.delete,
                            color: Colors.red, size: 20),
                        label: const Text('Excluir',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Botões para cancelar e salvar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 1,
                            child: OutlinedButton(
                              onPressed: _isLoading
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text('Cancelar',
                                  style: TextStyle(fontSize: 13)),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _saveChanges,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: const Text('Salvar Alterações',
                                  style: TextStyle(fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Overlay de carregamento
            if (_isLoading)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Seção com os campos editáveis
  Widget _buildEditableSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Editar Detalhes',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const Divider(),

        // Campo para alterar status
        const Text(
          'Status:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<OccurrenceStatus>(
              isExpanded: true,
              value: _selectedStatus,
              items: OccurrenceStatus.values.map((status) {
                Color statusColor;
                switch (status) {
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

                return DropdownMenuItem<OccurrenceStatus>(
                  value: status,
                  child: Text(
                    status.displayValue,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedStatus = value;
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Campo para alterar data/hora
        Row(
          children: [
            const Text(
              'Data/Hora:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today),
                label: Text(_dateFormatter.format(_selectedDate)),
                onPressed: _selectDate,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Campo para alterar ajuste manual de pontos
        const Text(
          'Ajuste Manual de Pontos:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _manualPointsController,
          keyboardType:
              TextInputType.numberWithOptions(signed: true, decimal: false),
          decoration: InputDecoration(
            hintText: 'Valor do ajuste (positivo ou negativo)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Campo para alterar observações
        const Text(
          'Observações:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Observações sobre a ocorrência',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
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

  Widget _buildInfoItem(String label, String value) {
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
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Anexos',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const Divider(),
        if (_loadingAttachments)
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
          GridView.builder(
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
      ],
    );
  }

  Widget _buildAttachmentItem(String url, String type, String name) {
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
}
