// lib/features/employee/screens/employee_dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // Import para inicializar locale
import '../../shared/widgets/balance_history_modal.dart'; // Para acessar histórico passado

// Importa o MODELO PointOccurrence
import '../../shared/models/point_occurrence.dart';

/// Dashboard principal para usuários com a role 'Funcionário'.
/// Exibe saldo atual (do período vigente) e histórico de ocorrências do período vigente.
/// Permite filtrar as ocorrências do período vigente por data.
/// Acesso ao histórico de períodos passados é feito via modal de histórico de saldo.
class EmployeeDashboardPage extends StatefulWidget {
  const EmployeeDashboardPage({Key? key}) : super(key: key);

  @override
  State<EmployeeDashboardPage> createState() => _EmployeeDashboardPageState();
}

class _EmployeeDashboardPageState extends State<EmployeeDashboardPage> {
  // Instâncias do Firebase
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  User? _currentUser;

  // Estado para carregamento e exibição de informações
  bool _isLoadingUserName = true;
  String _userName = 'Funcionário'; // Valor padrão

  // Formatadores de dados
  late final NumberFormat _currencyFormat;
  late final DateFormat _dateFormat;
  late final DateFormat _shortDateFormat; // Para filtro personalizado
  bool _formattersInitialized = false;

  // Estado para filtro de data (aplicado DENTRO do período atual)
  DateTimeRange? _selectedDateRange;
  String _filterLabel = 'Todas'; // Significa "Todas do período atual"

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
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      _loadUserName(_currentUser!.uid);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isLoadingUserName = false);
        }
      });
      debugPrint('EmployeeDashboard: Usuário não autenticado no initState.');
    }
  }

  // Inicializa formatadores dependentes de locale
  Future<void> _initializeFormatters() async {
    try {
      await initializeDateFormatting('pt_BR', null);
      _currencyFormat = NumberFormat('+0;-0', 'pt_BR');
      _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
      _shortDateFormat = DateFormat('dd/MM', 'pt_BR'); // Formato curto
      _formattersInitialized = true;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Erro ao inicializar formatadores pt_BR: $e. Usando padrões.");
      _currencyFormat = NumberFormat('+0;-0');
      _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
      _shortDateFormat = DateFormat('MM/dd'); // Formato curto padrão
      _formattersInitialized = true;
      if (mounted) setState(() {});
    }
  }

  /// Carrega o nome do usuário a partir do Firestore
  Future<void> _loadUserName(String userId) async {
    if (!mounted) return;
    setState(() {
      _isLoadingUserName = true;
      _userName = 'Carregando...';
    });
    try {
      final docSnapshot =
          await _firestore.collection('users').doc(userId).get();
      if (mounted) {
        if (docSnapshot.exists) {
          final userData = docSnapshot.data() as Map<String, dynamic>;
          setState(() => _userName =
              userData['displayName'] as String? ?? 'Nome não encontrado');
        } else {
          setState(() => _userName = 'Usuário (sem dados)');
        }
      }
    } catch (e, stackTrace) {
      debugPrint(
          'EmployeeDashboard: Erro ao carregar nome do usuário: $e\n$stackTrace');
      if (mounted) {
        setState(() => _userName = 'Erro ao carregar');
        _showErrorSnackBar('Erro ao buscar seu nome: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingUserName = false);
      }
    }
  }

  /// Exibe o modal para seleção de período de filtro DE DATA (no período atual)
  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _buildFilterBottomSheet(),
    );
  }

  /// Constrói o conteúdo do modal de filtro de data (para período atual)
  Widget _buildFilterBottomSheet() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filtrar ocorrências do período atual', // Título claro
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          // Opção: Todas (do período atual)
          ListTile(
            leading: const Icon(Icons.all_inclusive),
            title: const Text('Todas (do período atual)'),
            onTap: () {
              _setFilterRange(null, 'Todas');
              Navigator.pop(context);
            },
          ),
          // Opção: Hoje
          ListTile(
            leading: const Icon(Icons.today),
            title: const Text('Hoje'),
            onTap: () {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final tomorrow = today.add(const Duration(days: 1));
              _setFilterRange(
                  DateTimeRange(start: today, end: tomorrow), 'Hoje');
              Navigator.pop(context);
            },
          ),
          // Opção: Esta semana
          ListTile(
            leading: const Icon(Icons.calendar_view_week),
            title: const Text('Esta semana'),
            onTap: () {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              // Início da semana (Domingo)
              final startOfWeek =
                  today.subtract(Duration(days: today.weekday % 7));
              // Fim da semana (próximo Domingo, exclusivo)
              final endOfWeek = startOfWeek.add(const Duration(days: 7));
              _setFilterRange(DateTimeRange(start: startOfWeek, end: endOfWeek),
                  'Esta semana');
              Navigator.pop(context);
            },
          ),
          // Opção: Este mês (calendário atual)
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: const Text(
                'Este mês (calendário)'), // Diferencia do período de pontos
            onTap: () {
              final now = DateTime.now();
              final startOfMonth = DateTime(now.year, now.month, 1);
              // Fim do mês (primeiro dia do próximo, exclusivo)
              final endOfMonth = DateTime(now.year, now.month + 1, 1);
              _setFilterRange(
                  DateTimeRange(start: startOfMonth, end: endOfMonth),
                  'Este mês');
              Navigator.pop(context);
            },
          ),
          // Opção: Mês Anterior (calendário)
          ListTile(
            leading:
                const Icon(Icons.calendar_today_outlined), // Ícone diferente
            title: const Text('Mês Anterior (calendário)'),
            onTap: () {
              final now = DateTime.now();
              final firstDayOfCurrentMonth = DateTime(now.year, now.month, 1);
              final lastDayOfPreviousMonth =
                  firstDayOfCurrentMonth.subtract(const Duration(days: 1));
              final firstDayOfPreviousMonth = DateTime(
                  lastDayOfPreviousMonth.year, lastDayOfPreviousMonth.month, 1);
              // O fim do range é o primeiro dia do mês atual (exclusive)
              final endOfRange = firstDayOfCurrentMonth;

              _setFilterRange(
                DateTimeRange(start: firstDayOfPreviousMonth, end: endOfRange),
                'Mês Anterior',
              );
              Navigator.pop(context);
            },
          ),
          // Opção: Personalizado
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Personalizado...'),
            onTap: () async {
              Navigator.pop(context); // Fecha o modal
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(
                    DateTime.now().year - 1), // Limite inferior razoável
                lastDate: DateTime.now()
                    .add(const Duration(days: 1)), // Limite superior
                initialDateRange: _selectedDateRange ??
                    DateTimeRange(
                        start:
                            DateTime.now().subtract(const Duration(days: 30)),
                        end: DateTime.now().add(const Duration(days: 1))),
                locale:
                    const Locale('pt', 'BR'), // Define o locale para o picker
                builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context)
                            .colorScheme
                            .copyWith(primary: Theme.of(context).primaryColor)),
                    child: child!),
              );
              if (picked != null) {
                // Ajusta a data final para incluir todo o dia
                final adjustedEnd = DateTime(picked.end.year, picked.end.month,
                    picked.end.day, 23, 59, 59);
                // Formata o label para o período personalizado usando _shortDateFormat
                final formattedStart = _shortDateFormat.format(picked.start);
                final formattedEnd = _shortDateFormat.format(picked.end);
                _setFilterRange(
                  DateTimeRange(start: picked.start, end: adjustedEnd),
                  '$formattedStart - $formattedEnd', // Label curto
                );
              }
            },
          ),
        ],
      ),
    );
  }

  /// Atualiza o estado com o novo filtro de data selecionado
  void _setFilterRange(DateTimeRange? range, String label) {
    setState(() {
      _selectedDateRange = range;
      _filterLabel = label;
    });
    // A query em _buildOccurrencesList será automaticamente atualizada pelo StreamBuilder
  }

  /// Realiza o logout do usuário
  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      // Navegação tratada pelo AuthWrapper
    } catch (e, stackTrace) {
      debugPrint('EmployeeDashboard: Erro ao fazer logout: $e\n$stackTrace');
      if (mounted) _showErrorSnackBar('Erro ao sair: ${e.toString()}');
    }
  }

  /// Exibe um SnackBar de erro com a mensagem fornecida
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

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
      case OccurrenceStatus.Aprovada:
        return points >= 0 ? Icons.check_circle : Icons.remove_circle;
      case OccurrenceStatus.Reprovada:
        return Icons.cancel;
      case OccurrenceStatus.Pendente:
      default:
        return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_formattersInitialized)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_currentUser == null) return _buildUnauthenticatedScreen();

    final String userId = _currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meu Painel'),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout_outlined),
              onPressed: _signOut,
              tooltip: 'Sair'),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card do usuário com informações e saldo (sem alterações aqui)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: _isLoadingUserName
                  ? const Center(
                      key: ValueKey('loading-user'),
                      child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: CircularProgressIndicator()))
                  : _buildUserInfoCard(userId),
            ),

            const SizedBox(height: 20),

            // Título da seção de ocorrências com filtro
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Ocorrências do Período Atual', // Título confirma o foco
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Botão de filtro de data
                Tooltip(
                  message: 'Filtrar por data (no período atual)',
                  child: TextButton.icon(
                    icon: const Icon(Icons.filter_list, size: 20),
                    label: Text(_filterLabel,
                        style: const TextStyle(fontSize: 13)),
                    onPressed:
                        _showFilterOptions, // Abre o modal de filtro de data
                  ),
                ),
              ],
            ),

            // Lista de ocorrências (query principal com periodId == null + filtro de data)
            Expanded(
              child: _buildOccurrencesList(userId),
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói a tela quando não há usuário autenticado
  Widget _buildUnauthenticatedScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Painel do Funcionário')),
      body: const Center(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Erro: Usuário não autenticado. Faça login novamente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red, fontSize: 16)))),
    );
  }

  /// Constrói o card de informações do usuário com saldo e link para histórico
  Widget _buildUserInfoCard(String userId) {
    return Card(
      key: ValueKey('userInfoCard-$_userName'), // Chave para AnimatedSwitcher
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nome do usuário
            Text('Bem-vindo(a), $_userName!',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            // Saldo atual e link para histórico
            Row(
              children: [
                Icon(Icons.stars_outlined,
                    color: Colors.amber.shade800, size: 22),
                const SizedBox(width: 8),
                Text('Saldo atual:',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                // Stream para saldo em tempo real
                StreamBuilder<DocumentSnapshot>(
                  stream:
                      _firestore.collection('users').doc(userId).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting)
                      return const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2));
                    if (snapshot.hasError)
                      return Tooltip(
                          message: snapshot.error.toString(),
                          child: const Icon(Icons.error_outline,
                              color: Colors.red, size: 20));
                    if (!snapshot.hasData || !snapshot.data!.exists)
                      return Text('0 pontos',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey));

                    final userData =
                        snapshot.data!.data() as Map<String, dynamic>?;
                    final int saldo =
                        (userData?['saldoPontosAprovados'] as num?)?.toInt() ??
                            0;
                    final Color textColor = saldo >= 0
                        ? Colors.green.shade900
                        : Colors.red.shade900;

                    // Tornar o saldo clicável para abrir o histórico
                    return InkWell(
                      onTap: () {
                        // Chama o modal de histórico para ver períodos passados
                        BalanceHistoryModal.show(context,
                            userId: userId, userName: _userName);
                      },
                      borderRadius:
                          BorderRadius.circular(4), // Área de clique visual
                      child: Padding(
                        // Padding para área de clique
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4.0, vertical: 2.0),
                        child: Row(
                          mainAxisSize:
                              MainAxisSize.min, // Para ajustar ao conteúdo
                          children: [
                            Text('${_formatPoints(saldo)} pontos',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: textColor)),
                            const SizedBox(width: 4),
                            Tooltip(
                                message: 'Ver histórico mensal',
                                child: Icon(Icons.history,
                                    size: 16, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói a lista de ocorrências do usuário **DO PERÍODO ATUAL**,
  /// aplicando o filtro de data selecionado.
  Widget _buildOccurrencesList(String userId) {
    // Query base: sempre filtra por usuário e período atual (periodId == null)
    Query query = _firestore
        .collection('pointsOccurrences')
        .where('userId', isEqualTo: userId)
        .where('periodId', isEqualTo: null); // <-- FILTRO PRINCIPAL

    // Aplicar filtro de data ADICIONAL se _selectedDateRange estiver definido
    if (_selectedDateRange != null) {
      final startTimestamp = Timestamp.fromDate(_selectedDateRange!.start);
      // Ajusta o fim para ser exclusivo no final do dia ou usar isLessThan
      final endTimestamp = Timestamp.fromDate(_selectedDateRange!.end);
      // final endTimestampExclusive = Timestamp.fromDate(_selectedDateRange!.end.add(const Duration(days: 1))); // Alternativa

      query = query
          .where('registeredAt', isGreaterThanOrEqualTo: startTimestamp)
          .where('registeredAt',
              isLessThan:
                  endTimestamp); // Usa < para incluir até 23:59:59 do dia anterior
      // .where('registeredAt', isLessThanOrEqualTo: endTimestamp); // Se endTimestamp já for 23:59:59

      // IMPORTANTE: Certifique-se de que o índice composto
      // (userId ASC, periodId ASC, registeredAt DESC) exista no Firestore
      // ou (userId ASC, periodId ASC) + (userId ASC, registeredAt DESC).
      // O Firestore geralmente consegue combinar índices.
    }

    // Ordenação padrão (mais recentes primeiro)
    query = query.orderBy('registeredAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          debugPrint('Erro no stream de ocorrências: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                  'Erro ao carregar ocorrências atuais.\n(${snapshot.error})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          final message = _filterLabel == 'Todas'
              ? 'Nenhuma ocorrência encontrada neste período.'
              : 'Nenhuma ocorrência encontrada para o filtro de data selecionado neste período.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt_outlined,
                      size: 50, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 16)),
                  if (_selectedDateRange != null)
                    TextButton.icon(
                      icon: const Icon(
                        Icons.refresh,
                        size: 18,
                      ),
                      label: const Text('Mostrar todas do período'),
                      onPressed: () => _setFilterRange(null, 'Todas'),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700),
                    ),
                ],
              ),
            ),
          );
        }

        // Converte documentos para objetos PointOccurrence
        final List<PointOccurrence> occurrences = snapshot.data!.docs
            .map((doc) {
              try {
                return PointOccurrence.fromJson(
                    doc.id, doc.data() as Map<String, dynamic>);
              } catch (e, stackTrace) {
                debugPrint(
                    'Erro ao converter ocorrência ${doc.id}: $e\n$stackTrace');
                return null;
              }
            })
            .whereType<PointOccurrence>() // Filtra nulls
            .toList();

        // Constrói a lista visualmente
        return ListView.builder(
          padding: const EdgeInsets.only(
              top: 8, bottom: 16), // Espaço acima e abaixo
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
            if (occurrence.notes != null && occurrence.notes!.isNotEmpty)
              subtitleParts.add('Obs: ${occurrence.notes!}');
            subtitleParts.add('Por: $registeredByName'); // Mais curto
            subtitleParts
                .add('Em: ${_formatTimestamp(timestamp)}'); // Mais curto
            final String subtitleText =
                subtitleParts.join('  |  '); // Separador

            return Card(
              elevation: 1.5,
              margin: const EdgeInsets.symmetric(
                  vertical: 4, horizontal: 4), // Margem menor
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              child: ListTile(
                leading: Tooltip(
                    message: status.displayValue,
                    child: Icon(statusIcon, color: statusColor, size: 28)),
                title: Text(typeName,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                // Subtítulo em uma linha se possível
                subtitle: Text(
                  subtitleText,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5),
                  maxLines: 2, // Permite quebrar se for muito longo
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text('${_formatPoints(points)} pts',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: points >= 0
                            ? Colors.green.shade900
                            : Colors.red.shade900)),
                dense: true, // Torna o ListTile mais compacto
                // isThreeLine: subtitleText.contains('\n'), // Não mais necessário com maxLines
              ),
            );
          },
        );
      },
    );
  }
} // Fim da classe _EmployeeDashboardPageState
