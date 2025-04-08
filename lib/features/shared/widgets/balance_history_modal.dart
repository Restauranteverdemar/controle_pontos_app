// lib/features/shared/widgets/balance_history_modal.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // Necessário para formatar meses

// import '../models/point_occurrence.dart'; // Não é estritamente necessário aqui
import '../../employee/screens/monthly_occurrences_page.dart'; // Para navegação

/// Modal reutilizável para exibir o histórico de saldo mensal (períodos fechados).
/// Busca dados da coleção 'userBalanceSnapshots'.
class BalanceHistoryModal extends StatefulWidget {
  final String userId;
  final String
      userName; // Nome do usuário para exibição (principalmente para admin)
  final bool isAdmin; // Flag para futuras funcionalidades específicas de admin

  const BalanceHistoryModal({
    Key? key,
    required this.userId,
    this.userName = '',
    this.isAdmin = false,
  }) : super(key: key);

  /// Método estático para mostrar o modal.
  static Future<void> show(
    BuildContext context, {
    required String userId,
    String userName = '',
    bool isAdmin = false,
  }) {
    // Garante que formatadores pt_BR sejam inicializados antes de mostrar
    // (Pode ser feito no main.dart também)
    initializeDateFormatting('pt_BR', null);

    return showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true, // Permite ocupar mais altura
      builder: (context) {
        // Usamos DraggableScrollableSheet para melhor controle de altura
        return DraggableScrollableSheet(
          initialChildSize: 0.6, // Começa com 60% da altura
          minChildSize: 0.3, // Mínimo 30%
          maxChildSize: 0.9, // Máximo 90%
          expand: false,
          builder: (_, scrollController) {
            // Passa o scrollController para o conteúdo, se necessário
            // No nosso caso, o ListView interno já é scrollable
            return BalanceHistoryModal(
              userId: userId,
              userName: userName,
              isAdmin: isAdmin,
            );
          },
        );
      },
    );
  }

  @override
  State<BalanceHistoryModal> createState() => _BalanceHistoryModalState();
}

class _BalanceHistoryModalState extends State<BalanceHistoryModal> {
  final _firestore = FirebaseFirestore.instance;

  // Formatadores (idealmente inicializados antes do show, mas com fallback)
  late final NumberFormat _currencyFormat;
  late final DateFormat _timestampFormat; // Para a data de registro do snapshot
  late final DateFormat _monthYearFormat; // Para formatar o título do mês
  bool _formattersInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeFormatters();
  }

  void _initializeFormatters() {
    try {
      // Tenta usar pt_BR que deve ter sido inicializado pelo 'show'
      _currencyFormat = NumberFormat('+0;-0', 'pt_BR');
      _timestampFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
      // Formato para exibir "Maio 2025"
      _monthYearFormat = DateFormat('MMMM yyyy', 'pt_BR');
      _formattersInitialized = true;
    } catch (e) {
      debugPrint(
          "Erro ao inicializar formatadores pt_BR no Modal: $e. Usando padrões.");
      // Fallback seguro
      _currencyFormat = NumberFormat('+0;-0');
      _timestampFormat = DateFormat('yyyy-MM-dd HH:mm');
      _monthYearFormat = DateFormat('yyyy-MM'); // Formato simples como fallback
      _formattersInitialized = true;
    }
    //setState só é necessário se o build depender disso antes da inicialização
    // if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Pode mostrar um loading inicial se formatters demorarem
    if (!_formattersInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final String title = widget.isAdmin && widget.userName.isNotEmpty
        ? 'Histórico de Saldo - ${widget.userName}'
        : 'Histórico de Saldo Mensal';

    return Column(
      // Envolve tudo em Column para o header ficar fixo
      children: [
        _buildModalHeader(title), // Cabeçalho fixo
        Expanded(
          // Lista ocupa o espaço restante
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('userBalanceSnapshots')
                .where('userId', isEqualTo: widget.userId)
                // *** CORREÇÃO: Ordenar por 'periodId' ***
                .orderBy('periodId', descending: true) // Mais recente primeiro
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                debugPrint(
                    "Erro no Stream de userBalanceSnapshots: ${snapshot.error}");
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Erro ao carregar histórico.',
                      style: TextStyle(color: Colors.red)),
                ));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_toggle_off_outlined,
                            size: 60, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text('Nenhum histórico de saldo disponível.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text(
                            'Os saldos são registrados durante o reset mensal.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 14)),
                      ],
                    ),
                  ),
                );
              }

              // Mapeia os documentos para a lista
              final List<QueryDocumentSnapshot> historyDocs =
                  snapshot.data!.docs;

              return ListView.builder(
                // controller: scrollController, // Passa o controller do DraggableScrollableSheet
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: historyDocs.length,
                itemBuilder: (context, index) {
                  final doc = historyDocs[index];
                  final data = doc.data() as Map<String, dynamic>;

                  // *** CORREÇÃO: Ler 'periodId' ***
                  final String periodId = data['periodId'] as String? ?? '';
                  final int finalBalance =
                      (data['finalBalance'] as num?)?.toInt() ?? 0;
                  // O timestamp do reset pode ser útil
                  final Timestamp? resetTimestamp =
                      data['resetTimestamp'] as Timestamp?;

                  // Formatar o título do mês/ano a partir do periodId
                  final String formattedMonthTitle = _formatPeriodId(periodId);
                  final Color balanceColor = finalBalance >= 0
                      ? Colors.green.shade900
                      : Colors.red.shade900;

                  return InkWell(
                    onTap: () {
                      if (periodId.isNotEmpty) {
                        // Fecha o modal ANTES de navegar
                        Navigator.pop(context);
                        // *** CORREÇÃO: Passar periodId para a página ***
                        _navigateToMonthlyOccurrences(
                            periodId, formattedMonthTitle);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("ID do período inválido."),
                                backgroundColor: Colors.orange));
                      }
                    },
                    child: Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      elevation: 1.5,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              // Para evitar overflow do título
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    formattedMonthTitle, // Ex: "Maio 2025"
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (resetTimestamp != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Reset em: ${_formatTimestamp(resetTimestamp)}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600),
                                    ),
                                  ]
                                ],
                              ),
                            ),
                            const SizedBox(width: 16), // Espaço antes do saldo
                            Row(
                              // Saldo e seta
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_formatPoints(finalBalance)} pts',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: balanceColor),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.arrow_forward_ios,
                                    size: 14, color: Colors.grey.shade500),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // Cabeçalho do modal (com drag handle)
  Widget _buildModalHeader(String title) {
    return Container(
      padding: const EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 12),
      decoration: BoxDecoration(
        color:
            Theme.of(context).scaffoldBackgroundColor, // Cor de fundo do modal
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 5,
              offset: const Offset(0, -2)),
        ], // Sombra sutil
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            // Drag handle
            width: 40, height: 5,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.history_edu_outlined,
                  size: 24, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 18),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Formata o periodId ("YYYY-MM") para um formato legível ("Mês YYYY").
  String _formatPeriodId(String periodId) {
    if (!_formattersInitialized || !periodId.contains('-'))
      return periodId; // Fallback

    try {
      final parts = periodId.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      // Cria um DateTime para usar o DateFormat
      final date = DateTime(year, month);
      return _monthYearFormat.format(date); // Ex: "Maio 2025"
    } catch (e) {
      debugPrint('Erro ao formatar periodId "$periodId": $e');
      return periodId; // Retorna o original em caso de erro
    }
  }

  /// Formata um Timestamp (data/hora).
  String _formatTimestamp(Timestamp? timestamp) {
    if (!_formattersInitialized || timestamp == null) return 'N/A';
    try {
      return _timestampFormat.format(timestamp.toDate());
    } catch (e) {
      return 'Inválido';
    }
  }

  /// Formata pontos (saldo).
  String _formatPoints(int? points) {
    if (!_formattersInitialized) return '...';
    return _currencyFormat.format(points ?? 0);
  }

  /// Navega para a tela de detalhes das ocorrências do mês.
  void _navigateToMonthlyOccurrences(
      String periodId, String formattedMonthTitle) {
    // A navegação ocorre após o pop no onTap
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MonthlyOccurrencesPage(
          userId: widget.userId,
          // *** CORREÇÃO: Passar o 'periodId' correto ***
          periodId: periodId,
          // Passa o título já formatado para a AppBar da próxima tela
          monthTitle: formattedMonthTitle,
        ),
      ),
    );
  }
}
