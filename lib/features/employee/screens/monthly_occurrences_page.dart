// lib/features/employee/screens/monthly_occurrences_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../shared/models/point_occurrence.dart';

/// Tela para exibir ocorrências de um mês específico (período fechado).
/// Recebe o ID do usuário, o ID do período (formato "YYYY-MM") e um título formatado.
class MonthlyOccurrencesPage extends StatefulWidget {
  final String userId;
  final String periodId; // Renomeado de yearMonth para clareza e consistência
  final String monthTitle;

  const MonthlyOccurrencesPage({
    Key? key,
    required this.userId,
    required this.periodId, // Usar periodId
    required this.monthTitle,
  }) : super(key: key);

  @override
  State<MonthlyOccurrencesPage> createState() => _MonthlyOccurrencesPageState();
}

class _MonthlyOccurrencesPageState extends State<MonthlyOccurrencesPage> {
  // Instância do Firestore
  final _firestore = FirebaseFirestore.instance;

  // Formatadores de dados
  late final DateFormat _dateFormat;
  late final NumberFormat _currencyFormat;
  bool _formattersInitialized = false;

  // Mapeamento de status para cores
  final Map<OccurrenceStatus, Color> _statusColors = {
    OccurrenceStatus.Aprovada: Colors.green.shade700,
    OccurrenceStatus.Reprovada: Colors.red.shade700,
    OccurrenceStatus.Pendente: Colors.orange.shade700,
  };

  @override
  void initState() {
    super.initState();
    _initializeFormatters();
    // _calculateMonthRange(); // REMOVIDO - Não precisamos mais calcular range de data
  }

  // Inicializa formatadores dependentes de locale
  Future<void> _initializeFormatters() async {
    try {
      await initializeDateFormatting('pt_BR', null);
      _currencyFormat = NumberFormat('+0;-0', 'pt_BR');
      _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
      _formattersInitialized = true;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Erro ao inicializar formatadores pt_BR: $e. Usando padrões.");
      _currencyFormat = NumberFormat('+0;-0');
      _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
      _formattersInitialized = true;
      if (mounted) setState(() {});
    }
  }

  // REMOVIDO - Não é mais necessário
  // void _calculateMonthRange() { ... }

  /// Formata um Timestamp em string de data legível
  String _formatTimestamp(Timestamp? timestamp) {
    if (!_formattersInitialized || timestamp == null) return '...';
    try {
      return _dateFormat.format(timestamp.toDate());
    } catch (e) {
      return 'Data inválida';
    }
  }

  /// Formata um número de pontos com sinal (+/-)
  String _formatPoints(int? points) {
    if (!_formattersInitialized) return '...';
    return _currencyFormat.format(points ?? 0);
  }

  /// Determina o ícone apropriado baseado no status e nos pontos
  IconData _getStatusIcon(OccurrenceStatus status, int points) {
    switch (status) {
      case OccurrenceStatus.Aprovada: return points >= 0 ? Icons.check_circle : Icons.remove_circle;
      case OccurrenceStatus.Reprovada: return Icons.cancel;
      case OccurrenceStatus.Pendente: default: return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_formattersInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Ocorrências de ${widget.monthTitle}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Card com resumo do mês (opcional) - **QUERY CORRIGIDA**
          _buildMonthSummaryCard(),

          // Lista de ocorrências do mês - **QUERY CORRIGIDA**
          Expanded(
            child: _buildMonthlyOccurrencesList(),
          ),
        ],
      ),
    );
  }

  // Card com resumo do mês (opcional) - **QUERY CORRIGIDA**
  Widget _buildMonthSummaryCard() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('userBalanceSnapshots')
          .where('userId', isEqualTo: widget.userId)
          // *** CORREÇÃO: Usar 'periodId' para buscar o snapshot ***
          .where('periodId', isEqualTo: widget.periodId)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
          // Não mostra nada ou um placeholder se não encontrar o snapshot
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
        final int finalBalance = (data['finalBalance'] as num?)?.toInt() ?? 0;
        final Color balanceColor = finalBalance >= 0 ? Colors.green.shade900 : Colors.red.shade900;

        return Card(
          margin: const EdgeInsets.all(16),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Saldo final do mês', style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(finalBalance >= 0 ? Icons.trending_up : Icons.trending_down, color: balanceColor, size: 16),
                        const SizedBox(width: 4),
                        Text('${_formatPoints(finalBalance)} pontos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: balanceColor)),
                      ],
                    ),
                  ],
                ),
                // Contador de ocorrências - **QUERY CORRIGIDA**
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('pointsOccurrences')
                      .where('userId', isEqualTo: widget.userId)
                      // *** CORREÇÃO: Usar 'periodId' para contar ocorrências do período ***
                      .where('periodId', isEqualTo: widget.periodId)
                      // Opcional: contar apenas aprovadas/reprovadas se fizer sentido
                      // .where('status', whereIn: ['Aprovada', 'Reprovada'])
                      .snapshots(),
                  builder: (context, countSnapshot) {
                    // Usar QuerySnapshot.size para contagem eficiente
                    final count = countSnapshot.hasData ? countSnapshot.data!.size : 0;
                    if (countSnapshot.connectionState == ConnectionState.waiting || count == 0) {
                       return const SizedBox.shrink(); // Não mostra se estiver carregando ou for 0
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '$count ocorrência${count > 1 ? 's' : ''}', // Plural correto
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Lista de ocorrências do mês específico - **QUERY CORRIGIDA**
  Widget _buildMonthlyOccurrencesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('pointsOccurrences')
          .where('userId', isEqualTo: widget.userId)
          // *** CORREÇÃO PRINCIPAL: Filtrar por periodId ***
          .where('periodId', isEqualTo: widget.periodId)
          // A ordenação por data de registro ainda faz sentido dentro do período
          .orderBy('registeredAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          debugPrint('Erro no stream de ocorrências mensais: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Erro ao carregar ocorrências de ${widget.monthTitle}.\n(${snapshot.error})', textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.event_busy, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text('Nenhuma ocorrência encontrada em ${widget.monthTitle}.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          );
        }

        // Converter documentos em objetos PointOccurrence (sem alteração aqui)
        final List<PointOccurrence> occurrences = snapshot.data!.docs
            .map((doc) {
              try {
                return PointOccurrence.fromJson(doc.id, doc.data() as Map<String, dynamic>);
              } catch (e, stackTrace) {
                debugPrint('Erro ao converter ocorrência ${doc.id}: $e\n$stackTrace');
                return null;
              }
            })
            .whereType<PointOccurrence>()
            .toList();

        // Construir a lista de ocorrências (sem alteração aqui)
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: occurrences.length,
          itemBuilder: (context, index) {
            final occurrence = occurrences[index];
            final String typeName = occurrence.incidentName;
            final int points = occurrence.finalPoints;
            final status = occurrence.status;
            final timestamp = occurrence.registeredAt;
            final String registeredByName = occurrence.registeredByName;
            final Color statusColor = _statusColors[status] ?? Colors.grey;
            final IconData statusIcon = _getStatusIcon(status, points);

            List<String> subtitleParts = [];
            if (occurrence.notes != null && occurrence.notes!.isNotEmpty) subtitleParts.add('Obs: ${occurrence.notes!}');
            subtitleParts.add('Enviado por: $registeredByName');
            subtitleParts.add('Data: ${_formatTimestamp(timestamp)}'); // Data do registro
            final String subtitleText = subtitleParts.join('\n');

            return Card(
              elevation: 1.5,
              margin: const EdgeInsets.symmetric(vertical: 5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                leading: Tooltip(message: status.displayValue, child: Icon(statusIcon, color: statusColor, size: 28)),
                title: Text(typeName, style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(subtitleText, style: TextStyle(color: Colors.grey.shade700, fontSize: 12, height: 1.3), maxLines: 4, overflow: TextOverflow.ellipsis),
                trailing: Text('${_formatPoints(points)} pts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: points >= 0 ? Colors.green.shade900 : Colors.red.shade900)),
                isThreeLine: subtitleText.contains('\n'),
              ),
            );
          },
        );
      },
    );
  }
}