// lib/features/admin/screens/employee_detail_modal.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:controle_pontos_app/features/admin/services/user_service.dart'; // Seu serviço de usuário
import 'package:controle_pontos_app/features/shared/models/employee.dart'; // Modelo Employee
import 'package:controle_pontos_app/features/shared/models/point_occurrence.dart'; // Modelo PointOccurrence
import 'package:controle_pontos_app/features/shared/screens/occurrence_detail_modal.dart'; // Modal de detalhe da ocorrência
import 'package:controle_pontos_app/core/constants/app_strings.dart'; // Constantes de Strings
import 'package:controle_pontos_app/core/constants/app_colors.dart'; // Constantes de Cores
import 'package:controle_pontos_app/core/constants/app_dimensions.dart'; // Constantes de Dimensões
import 'package:controle_pontos_app/features/employee/screens/monthly_occurrences_page.dart'; // ADICIONADO: Página de ocorrências mensais
import 'package:intl/intl.dart'; // Para formatar data
import 'package:flutter/foundation.dart'; // Para debugPrint

// Helpers (Podem ser movidos para arquivos separados depois)
class FeedbackHelper {
  static void showFeedback(BuildContext context, String message,
      {bool isError = false}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? AppColors.errorColor : AppColors.successColor,
        duration: const Duration(seconds: 3),
        behavior:
            SnackBarBehavior.floating, // Para melhor visualização em modais
        margin: EdgeInsets.only(
            // Ajusta margem para não ficar colado embaixo
            bottom: MediaQuery.of(context).size.height - 100,
            right: 20,
            left: 20),
      ),
    );
  }

  static void showSuccessFeedbackAndNavigateBack(
      BuildContext context, String message,
      {Duration delay = const Duration(milliseconds: 700)}) {
    // Aumentei um pouco o delay
    showFeedback(context, message);
    Future.delayed(delay, () {
      if (context.mounted) Navigator.of(context).pop(true); // Indica sucesso
    });
  }
}

// Classe principal do Modal
class EmployeeDetailModal extends StatefulWidget {
  final String userId;

  const EmployeeDetailModal({Key? key, required this.userId}) : super(key: key);

  @override
  _EmployeeDetailModalState createState() => _EmployeeDetailModalState();
}

class _EmployeeDetailModalState extends State<EmployeeDetailModal>
    with SingleTickerProviderStateMixin {
  // Necessário para TabController
  // Serviços e Controladores
  final UserService _userService = UserService();
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;
  final TextEditingController _displayNameController = TextEditingController();

  // Estado do Funcionário e UI
  Employee? _employee;
  String? _errorMessage;
  bool _isLoadingData = true;
  bool _isSaving = false;
  bool _isSendingReset = false;
  bool _isDeleting = false;

  // Estado dos campos editáveis
  String? _selectedRole;
  String? _selectedDepartment;
  bool _isActive = true;
  bool _showDepartmentDropdown = false;

  // Valores iniciais para detectar mudanças
  String _initialDisplayName = '';
  String _initialEmail = ''; // Guardar para redefinição de senha
  String _initialRole = '';
  String? _initialDepartment;
  bool _initialIsActive = true;

  // Formatador de Data
  final DateFormat _dateFormatter = DateFormat('dd/MM/yy HH:mm');

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: 3, vsync: this); // Alterado para 3 abas
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingData = true;
      _errorMessage = null;
    });

    try {
      final employeeData = await _userService.getEmployee(widget.userId);
      if (!mounted) return;

      _employee = employeeData;
      // Armazena valores iniciais
      _initialDisplayName = _employee!.displayName;
      _initialEmail = _employee!.email; // Guardar email inicial
      _initialRole = _employee!.role ?? '';
      _initialDepartment = _employee!.department;
      _initialIsActive = _employee!.isActive;

      // Preenche controladores e estado
      _displayNameController.text = _initialDisplayName;
      _selectedRole = _initialRole;
      _selectedDepartment = _initialDepartment;
      _isActive = _initialIsActive;
      _showDepartmentDropdown = (_selectedRole == AppStrings.employeeRole);

      setState(() => _isLoadingData = false);
    } catch (e) {
      if (!mounted) return;
      final errorMsg = "Erro ao carregar dados do funcionário: ${e.toString()}";
      setState(() {
        _errorMessage = errorMsg;
        _isLoadingData = false;
      });
      debugPrint(errorMsg);
    }
  }

  // --- Métodos de Ação ---

  Future<void> _saveChanges() async {
    // 1. Valida o formulário
    if (!_formKey.currentState!.validate()) {
      FeedbackHelper.showFeedback(context, AppStrings.formErrorMessage,
          isError: true);
      return;
    }
    // 2. Garante que os dados do funcionário foram carregados
    if (_employee == null) {
      FeedbackHelper.showFeedback(context, AppStrings.userDataMissingError,
          isError: true);
      return;
    }

    // 3. Inicia estado de loading
    setState(() => _isSaving = true);

    // 4. Pega os valores atuais do formulário
    final newDisplayName = _displayNameController.text.trim();
    final newRole = _selectedRole;
    final newDepartment =
        _selectedDepartment; // Pode ser null se role != Funcionário
    final newIsActive = _isActive;

    // 5. Detecta quais dados realmente mudaram
    bool basicDataChanged = (newDisplayName != _initialDisplayName) ||
        (newIsActive != _initialIsActive);
    bool roleOrDeptChanged = (newRole != _initialRole) ||
        (_showDepartmentDropdown && newDepartment != _initialDepartment);

    // 6. Verifica se houve alguma mudança
    if (!basicDataChanged && !roleOrDeptChanged) {
      FeedbackHelper.showFeedback(context, AppStrings.noChangesDetected);
      if (mounted)
        setState(
            () => _isSaving = false); // Finaliza loading se não houve mudanças
      return;
    }

    // 7. Prepara lista de tarefas e mensagens de sucesso
    List<Future<void>> tasks = [];
    List<String> successMessages = [];

    try {
      // 8. Adiciona tarefa para salvar dados básicos (se mudaram)
      if (basicDataChanged) {
        tasks.add(_userService
            .updateEmployeeBasicData(widget.userId, newDisplayName, newIsActive)
            .then((_) {
          debugPrint("Dados básicos salvos com sucesso.");
          successMessages.add("Dados básicos atualizados");
          // Atualiza estado inicial local APÓS sucesso
          _initialDisplayName = newDisplayName;
          _initialIsActive = newIsActive;
        }));
      }

      // 9. Adiciona tarefa para salvar Role/Department (se mudaram)
      if (roleOrDeptChanged) {
        // Validações específicas
        if (newRole == null || newRole.isEmpty)
          throw Exception(AppStrings.roleRequiredError);
        // Departamento só é obrigatório se o *novo* papel for Funcionário
        if (newRole == AppStrings.employeeRole &&
            (newDepartment == null || newDepartment.isEmpty)) {
          throw Exception(AppStrings.departmentRequiredError);
        }

        // Verifica se é promoção para Admin
        bool promotingToAdmin = (_initialRole != AppStrings.adminRole &&
            newRole == AppStrings.adminRole);

        if (promotingToAdmin) {
          // Chama a função de promover
          tasks.add(_userService.promoteToAdmin(widget.userId).then((msg) {
            debugPrint("Promoção para Admin realizada.");
            successMessages.add(msg);
            // Atualiza estado inicial local APÓS sucesso
            _initialRole = newRole;
            _initialDepartment = null; // Admin não tem departamento
          }));
        } else {
          // Chama a função de alterar role/departamento genérica
          tasks.add(_userService
              .changeUserRole(widget.userId, newRole, department: newDepartment)
              .then((msg) {
            debugPrint("Role/Departamento alterado.");
            successMessages.add(msg);
            // Atualiza estado inicial local APÓS sucesso
            _initialRole = newRole;
            _initialDepartment =
                newDepartment; // Mesmo se for null (mudança para Admin)
          }));
        }
      }

      // 10. Aguarda a conclusão de todas as tarefas
      await Future.wait(tasks);

      // 11. Atualiza o objeto local _employee para refletir as mudanças salvas
      // Isso garante que a UI (ex: AppBar title) atualize se o nome mudou
      if (mounted && _employee != null) {
        setState(() {
          _employee!.displayName = _initialDisplayName;
          _employee!.isActive = _initialIsActive;
          _employee!.role = _initialRole;
          _employee!.department = _initialDepartment;
        });
      }

      // 12. Mostra feedback de sucesso consolidado
      FeedbackHelper.showFeedback(
          context,
          successMessages.isNotEmpty
              ? successMessages.join('. ') + "."
              : AppStrings.updateSuccess);
      // Não fecha o modal automaticamente
    } catch (e) {
      // 13. Trata erros
      final errorMsg = "Erro ao salvar alterações: ${e.toString()}";
      debugPrint(errorMsg);
      FeedbackHelper.showFeedback(context, errorMsg, isError: true);
    } finally {
      // 14. Finaliza estado de loading
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    if (_employee == null) return;
    // Usa o email inicial que foi carregado
    final emailToSendReset = _initialEmail;
    if (emailToSendReset.isEmpty) {
      FeedbackHelper.showFeedback(context, AppStrings.emailResetNotFoundError,
          isError: true);
      return;
    }

    setState(() => _isSendingReset = true);
    try {
      final message = await _userService.sendPasswordResetEmail(
          widget.userId, emailToSendReset);
      FeedbackHelper.showFeedback(context, message);
    } catch (e) {
      final errorMsg = "Erro ao enviar email de redefinição: ${e.toString()}";
      debugPrint(errorMsg);
      FeedbackHelper.showFeedback(context, errorMsg, isError: true);
    } finally {
      if (mounted) setState(() => _isSendingReset = false);
    }
  }

  Future<void> _confirmAndDeleteUser() async {
    if (_employee == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.deleteConfirmationTitle),
        content: Text(AppStrings.deleteConfirmationContent
            .replaceAll('{name}', _employee!.displayName)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancelButton)),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.errorColor),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.deleteConfirmButton),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      final message = await _userService.deleteUser(widget.userId);
      // Navega de volta APÓS sucesso e feedback
      FeedbackHelper.showSuccessFeedbackAndNavigateBack(context, message,
          delay: Duration(seconds: 1));
    } catch (e) {
      final errorMsg = "Erro ao excluir funcionário: ${e.toString()}";
      debugPrint(errorMsg);
      FeedbackHelper.showFeedback(context, errorMsg, isError: true);
      if (mounted)
        setState(() => _isDeleting = false); // Só reabilita botão se falhar
    }
    // Não precisa de finally para _isDeleting = false se navegar no sucesso
  }

  // Método chamado ao mudar o Role no Dropdown
  void _onRoleChanged(String? newRole) {
    setState(() {
      _selectedRole = newRole;
      // Atualiza visibilidade E limpa seleção se mudar para não-funcionário
      final bool shouldShowDept = (newRole == AppStrings.employeeRole);
      if (_showDepartmentDropdown != shouldShowDept) {
        _showDepartmentDropdown = shouldShowDept;
        if (!shouldShowDept) {
          _selectedDepartment = null;
        }
      }
    });
  }

  // ADICIONADO: Função para formatar o período para exibição
  String _formatPeriodForDisplay(String periodId) {
    // Formato esperado: "YYYY-MM"
    try {
      final parts = periodId.split('-');
      if (parts.length == 2) {
        final year = parts[0];
        final month = parts[1];

        // Converter número do mês para nome do mês
        final monthNames = [
          'Jan',
          'Fev',
          'Mar',
          'Abr',
          'Mai',
          'Jun',
          'Jul',
          'Ago',
          'Set',
          'Out',
          'Nov',
          'Dez'
        ];

        final monthIndex = int.tryParse(month);
        final monthName =
            monthIndex != null && monthIndex >= 1 && monthIndex <= 12
                ? monthNames[monthIndex - 1]
                : month;

        return '$monthName/$year';
      }
    } catch (e) {
      debugPrint('Erro ao formatar período: $e');
    }

    // Fallback se o formato não for o esperado
    return periodId;
  }

  // ADICIONADO: Função para navegar para a página de ocorrências mensais
  void _navigateToMonthlyOccurrences(String periodId, String displayPeriod) {
    if (_employee == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MonthlyOccurrencesPage(
          userId: widget.userId,
          periodId: periodId,
          monthTitle: displayPeriod,
        ),
      ),
    );
  }

  // --- Construção da UI ---
  @override
  Widget build(BuildContext context) {
    // Usar um Container com borda arredondada em vez de Dialog diretamente
    // permite controlar melhor o ClipRRect e o Scaffold interno.
    return Container(
        margin:
            const EdgeInsets.all(AppDimensions.smallSpacing), // Margem externa
        decoration: BoxDecoration(
          color: Colors.white, // Fundo do modal
          borderRadius: BorderRadius.circular(AppDimensions.cardBorderRadius),
        ),
        child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.of(context).size.height * 0.9, // Limita altura
              maxWidth: 600, // Limita largura em telas maiores
            ),
            child: ClipRRect(
              // Garante que o conteúdo respeite as bordas arredondadas
              borderRadius:
                  BorderRadius.circular(AppDimensions.cardBorderRadius),
              child: _buildContent(),
            )));
  }

  Widget _buildContent() {
    // Indicador de carregamento inicial
    if (_isLoadingData) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator()));
    }

    // Mensagem de erro no carregamento
    if (_errorMessage != null) {
      return Padding(
        padding: AppDimensions.largePadding,
        child: Column(
            mainAxisSize: MainAxisSize.min, // Para centralizar verticalmente
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: AppColors.errorColor, size: 48),
              SizedBox(height: AppDimensions.formItemSpacing),
              Text(_errorMessage!,
                  style: TextStyle(color: AppColors.errorColor),
                  textAlign: TextAlign.center),
              SizedBox(height: AppDimensions.largeSpacing),
              ElevatedButton(
                  onPressed: _loadUserData, child: Text("Tentar Novamente")),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text("Fechar"))
            ]),
      );
    }

    // Caso funcionário não seja encontrado após tentativa de carregar
    if (_employee == null) {
      return const Center(
          child: Padding(
        padding: AppDimensions.padding,
        child: Text("Funcionário não encontrado ou dados indisponíveis.",
            textAlign: TextAlign.center),
      ));
    }

    // Conteúdo principal com Scaffold e TabBar
    return Scaffold(
      backgroundColor: Colors.white, // Fundo branco para o conteúdo do modal
      appBar: AppBar(
        title: Text(_employee?.displayName ?? 'Detalhes do Funcionário',
            overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        centerTitle: false,
        elevation: 1,
        automaticallyImplyLeading: false,
        shape: const RoundedRectangleBorder(
          // Remove borda inferior padrão da AppBar
          side: BorderSide.none,
        ),
        actions: [
          // Exibe indicador de salvamento/deleção na AppBar
          if (_isSaving || _isDeleting || _isSendingReset)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          if (!(_isSaving || _isDeleting || _isSendingReset))
            IconButton(
              // Só mostra fechar se não estiver em operação
              icon: const Icon(Icons.close),
              tooltip: "Fechar",
              onPressed: () => Navigator.of(context).pop(),
            )
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).primaryColor,
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Theme.of(context).primaryColor,
          indicatorWeight: 3.0, // Indicador mais visível
          tabs: const [
            Tab(icon: Icon(Icons.person_outline), text: 'Detalhes/Editar'),
            Tab(icon: Icon(Icons.history_outlined), text: 'Histórico'),
            Tab(
                icon: Icon(Icons.calendar_month_outlined),
                text: 'Histórico Mensal'),
          ],
        ),
      ),
      // Envolve com AbsorbPointer para desabilitar interações durante o loading principal
      body: AbsorbPointer(
        absorbing:
            _isLoadingData, // Desabilita tudo enquanto carrega dados iniciais
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildEditTab(),
            _buildHistoryTab(),
            _buildMonthlyHistoryTab(), // Nova aba de histórico mensal
          ],
        ),
      ),
    );
  }

  // --- Abas ---
  Widget _buildEditTab() {
    final bool isAnyOperationLoading =
        _isSaving || _isSendingReset || _isDeleting;
    // Apenas desabilita interações se uma operação específica estiver em andamento,
    // não durante o _isLoadingData, pois o AbsorbPointer no body já cuida disso.
    return SingleChildScrollView(
      padding: AppDimensions.padding,
      physics: const BouncingScrollPhysics(), // Efeito de scroll mais suave
      child: Form(
        key: _formKey,
        child: AbsorbPointer(
          // Desabilita interações durante operações
          absorbing: isAnyOperationLoading,
          child: Opacity(
            // Esmaece a UI durante operações
            opacity: isAnyOperationLoading ? 0.6 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildNameField(),
                SizedBox(height: AppDimensions.formItemSpacing),
                _buildEmailDisplay(), // Apenas exibe o email
                SizedBox(height: AppDimensions.formItemSpacing),
                _buildRoleDropdown(),
                _buildDepartmentDropdown(), // Já tem padding interno e visibility
                SizedBox(height: AppDimensions.formItemSpacing),
                _buildActiveSwitch(),
                SizedBox(height: AppDimensions.largeSpacing * 1.5),

                // Botões de Ação
                _buildActionButton(
                  text: AppStrings.saveChangesButton,
                  onPressed:
                      _saveChanges, // Botão é desabilitado pela flag isLoading interna
                  isLoading: _isSaving,
                  icon: Icons.save,
                  backgroundColor: Theme.of(context).primaryColor,
                ),
                SizedBox(height: AppDimensions.buttonSpacing),
                _buildActionButton(
                  text: AppStrings.resetPasswordButton,
                  onPressed: _sendPasswordReset,
                  isLoading: _isSendingReset,
                  icon: Icons.lock_reset,
                  backgroundColor: AppColors.resetPasswordButtonColor,
                ),
                SizedBox(height: AppDimensions.buttonSpacing),
                _buildActionButton(
                  text: AppStrings.deleteButton,
                  onPressed: _confirmAndDeleteUser,
                  isLoading: _isDeleting,
                  icon: Icons.delete_forever,
                  backgroundColor: AppColors.errorColor,
                ),
                SizedBox(
                    height: AppDimensions.bottomSpacing), // Espaço no final
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_isLoadingData) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('pointsOccurrences')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('occurrenceDate', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          // Mostra loading se esperando E sem dados antigos
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child: Padding(
                  padding: AppDimensions.padding,
                  child: Text("Erro ao carregar histórico: ${snapshot.error}",
                      textAlign: TextAlign.center)));
        }
        // Se não tem dados E NÃO está esperando (primeira carga vazia ou stream vazio)
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Padding(
            padding: AppDimensions.padding,
            child: Text("Nenhuma ocorrência registrada para este funcionário.",
                textAlign: TextAlign.center),
          ));
        }

        final occurrencesDocs = snapshot.data!.docs;

        return ListView.builder(
          padding:
              AppDimensions.padding.copyWith(top: AppDimensions.smallSpacing),
          itemCount: occurrencesDocs.length,
          itemBuilder: (context, index) {
            final doc = occurrencesDocs[index];
            try {
              final occurrence = PointOccurrence.fromJson(
                  doc.id, doc.data() as Map<String, dynamic>);
              final originalData = doc.data() as Map<String, dynamic>;

              Color statusColor;
              IconData statusIcon;
              switch (occurrence.status) {
                case OccurrenceStatus.Aprovada:
                  statusColor = AppColors.approvedStatusColor;
                  statusIcon = Icons.check_circle_outline;
                  break;
                case OccurrenceStatus.Reprovada:
                  statusColor = AppColors.rejectedStatusColor;
                  statusIcon = Icons.cancel_outlined;
                  break;
                case OccurrenceStatus.Pendente:
                default:
                  statusColor = AppColors.pendingStatusColor;
                  statusIcon = Icons.hourglass_empty_outlined;
              }

              return Card(
                margin: EdgeInsets.only(bottom: AppDimensions.smallSpacing),
                elevation: 1.5,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.borderRadius)),
                child: ListTile(
                  leading: Tooltip(
                      message: occurrence.status.displayValue,
                      child: Icon(statusIcon,
                          color: statusColor, size: AppDimensions.iconSize)),
                  title: Text(occurrence.incidentName,
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    'Data: ${_dateFormatter.format(occurrence.occurrenceDate.toDate())}\nRegistrado por: ${occurrence.registeredByName}',
                    style: TextStyle(
                        fontSize: AppDimensions.smallFontSize,
                        color: Colors.grey[700]),
                  ),
                  trailing: Text(
                    '${occurrence.finalPoints >= 0 ? "+" : ""}${occurrence.finalPoints} pts',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppDimensions.bodyFontSize,
                        color: occurrence.finalPoints >= 0
                            ? AppColors.successColor
                            : AppColors.errorColor),
                  ),
                  isThreeLine: true,
                  onTap: () {
                    showOccurrenceDetailModal(context, occurrence, originalData,
                        isAdmin: true);
                  },
                ),
              );
            } catch (e) {
              debugPrint(
                  "Erro ao converter ocorrencia ${doc.id} no histórico: $e");
              return Card(
                color: AppColors.errorColor.withOpacity(0.1),
                margin: EdgeInsets.only(bottom: AppDimensions.smallSpacing),
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded,
                      color: AppColors.errorColor),
                  title: Text("Erro ao carregar ocorrência ${doc.id}"),
                  subtitle: Text(e.toString(),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              );
            }
          },
        );
      },
    );
  }

  // ADICIONADO: Implementação da nova aba de Histórico Mensal
  Widget _buildMonthlyHistoryTab() {
    if (_isLoadingData) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('userBalanceSnapshots')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('periodId',
              descending:
                  true) // Ordena por período, do mais recente ao mais antigo
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: AppDimensions.padding,
              child: Text(
                "Erro ao carregar histórico de saldos: ${snapshot.error}",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Nenhum histórico mensal encontrado.\nOs saldos mensais são registrados após cada reset mensal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
              ],
            ),
          );
        }

        // Converter documentos em lista de históricos mensais
        final monthlySnapshots = snapshot.data!.docs;

        return ListView.builder(
          padding: AppDimensions.padding,
          itemCount: monthlySnapshots.length,
          itemBuilder: (context, index) {
            final snapshot =
                monthlySnapshots[index].data() as Map<String, dynamic>;
            final String periodId =
                snapshot['periodId'] as String? ?? 'Desconhecido';
            final int finalBalance =
                (snapshot['finalBalance'] as num?)?.toInt() ?? 0;
            final Timestamp? createdAt = snapshot['createdAt'] as Timestamp?;

            // Formatar o período para exibição amigável (YYYY-MM para Mês/Ano)
            final String displayPeriod = _formatPeriodForDisplay(periodId);

            // Determinar cor com base no valor do saldo
            final Color balanceColor =
                finalBalance >= 0 ? Colors.green.shade700 : Colors.red.shade700;

            // Formatar data de criação do snapshot
            String createdAtFormatted = 'Data desconhecida';
            if (createdAt != null) {
              try {
                createdAtFormatted = _dateFormatter.format(createdAt.toDate());
              } catch (e) {
                createdAtFormatted = 'Data inválida';
              }
            }

            return Card(
              margin: EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
                side: BorderSide(
                  color: finalBalance >= 0
                      ? Colors.green.shade200
                      : Colors.red.shade200,
                  width: 1,
                ),
              ),
              child: InkWell(
                onTap: () =>
                    _navigateToMonthlyOccurrences(periodId, displayPeriod),
                borderRadius: BorderRadius.circular(AppDimensions.borderRadius),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            displayPeriod,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(
                                finalBalance >= 0
                                    ? Icons.trending_up
                                    : Icons.trending_down,
                                color: balanceColor,
                                size: 20,
                              ),
                              SizedBox(width: 6),
                              Text(
                                '${finalBalance >= 0 ? "+" : ""}$finalBalance pts',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: balanceColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Reset realizado em: $createdAtFormatted',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Ver detalhes',
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: Theme.of(context).primaryColor,
                          ),
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
    );
  }

  // --- Widgets dos Campos de Edição (Reutilizados/Adaptados) ---
  Widget _buildNameField() {
    bool canEdit = !_isLoadingData && !_isSaving && !_isDeleting;
    return TextFormField(
      controller: _displayNameController,
      decoration: InputDecoration(
        labelText: AppStrings.displayNameLabel,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius)),
        prefixIcon: Icon(Icons.person),
        filled: !canEdit,
        fillColor: Colors.grey.shade100,
      ),
      validator: (value) => (value == null || value.trim().isEmpty)
          ? AppStrings.nameRequiredError
          : null,
      textInputAction: TextInputAction.next,
      enabled: canEdit,
      textCapitalization: TextCapitalization.words, // Capitaliza nomes
    );
  }

  // Widget para *exibir* o email
  Widget _buildEmailDisplay() {
    return TextFormField(
      initialValue: _initialEmail, // Exibe o email inicial carregado
      readOnly: true,
      decoration: InputDecoration(
        labelText: AppStrings.emailLabel,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius)),
        prefixIcon: Icon(Icons.email),
        filled: true,
        fillColor: Colors.grey.shade100,
        // Removido helperText sobre CF para simplificar a UI
      ),
      style: TextStyle(
          color: Colors.grey.shade700), // Indica visualmente que não é editável
    );
  }

  Widget _buildRoleDropdown() {
    bool canEdit = !_isLoadingData && !_isSaving && !_isDeleting;
    return DropdownButtonFormField<String>(
      value: _selectedRole,
      decoration: InputDecoration(
        labelText: AppStrings.roleLabel,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.borderRadius)),
        prefixIcon: Icon(Icons.security),
        filled: !canEdit,
        fillColor: Colors.grey.shade100,
      ),
      items: const [
        // Garante que os valores correspondam EXATAMENTE aos usados nas Cloud Functions/Regras
        DropdownMenuItem(
            value: AppStrings.adminRole,
            child: Text(AppStrings.adminRole)), // Ex: "Admin"
        DropdownMenuItem(
            value: AppStrings.employeeRole,
            child: Text(AppStrings.employeeRole)), // Ex: "Funcionário"
      ],
      onChanged: canEdit ? _onRoleChanged : null,
      validator: (value) => (value == null || value.isEmpty)
          ? AppStrings.roleRequiredError
          : null,
    );
  }

  Widget _buildDepartmentDropdown() {
    bool canEdit = !_isLoadingData &&
        !_isSaving &&
        !_isDeleting &&
        _showDepartmentDropdown;
    return AnimatedOpacity(
      opacity: _showDepartmentDropdown ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Visibility(
        visible: _showDepartmentDropdown,
        // REMOVIDO: maintainState e maintainAnimation para corrigir o erro de assert
        // maintainState: true,
        // maintainAnimation: true, // Implícito por maintainState
        child: Padding(
          padding: EdgeInsets.only(
              top: _showDepartmentDropdown ? AppDimensions.formItemSpacing : 0),
          child: DropdownButtonFormField<String>(
            value: _selectedDepartment,
            decoration: InputDecoration(
              labelText: AppStrings.departmentLabel,
              border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.borderRadius)),
              prefixIcon: Icon(Icons.work_outline),
              filled: !canEdit,
              fillColor: Colors.grey.shade100,
            ),
            // Garante que os valores correspondam EXATAMENTE aos usados nas Cloud Functions/Regras
            items: const [
              DropdownMenuItem(
                  value: AppStrings.kitchenDepartment,
                  child: Text(AppStrings.kitchenDepartment)), // Ex: "Cozinha"
              DropdownMenuItem(
                  value: AppStrings.diningRoomDepartment,
                  child: Text(AppStrings.diningRoomDepartment)), // Ex: "Salão"
            ],
            onChanged: canEdit
                ? (String? newValue) {
                    setState(() {
                      _selectedDepartment = newValue;
                    });
                  }
                : null,
            validator: (value) => (_showDepartmentDropdown &&
                    (value == null ||
                        value.isEmpty)) // Verifica se é nulo OU vazio
                ? AppStrings.departmentRequiredError
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveSwitch() {
    bool canEdit = !_isLoadingData && !_isSaving && !_isDeleting;
    return SwitchListTile(
      title: const Text(AppStrings.activeUserLabel),
      value: _isActive,
      onChanged: canEdit
          ? (bool newValue) {
              setState(() {
                _isActive = newValue;
              });
            }
          : null,
      secondary: Icon(_isActive ? Icons.check_circle : Icons.cancel,
          color: _isActive
              ? AppColors.activeUserColor
              : AppColors.inactiveUserColor),
      contentPadding: EdgeInsets.zero,
      activeColor: AppColors.activeUserColor,
      inactiveThumbColor: Colors.grey.shade400,
      inactiveTrackColor: Colors.grey.shade200,
      // Adiciona um pouco de padding se necessário
      // visualDensity: VisualDensity.compact,
    );
  }

  // Helper para criar botões de ação padronizados
  Widget _buildActionButton({
    required String text,
    required VoidCallback? onPressed,
    required bool isLoading,
    required IconData icon,
    required Color backgroundColor,
  }) {
    final bool isDisabled = onPressed == null || isLoading;
    return ElevatedButton.icon(
        icon: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 20),
        label: Text(text),
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: backgroundColor.withOpacity(0.5),
                disabledForegroundColor: Colors.white70,
                minimumSize:
                    Size(double.infinity, AppDimensions.buttonHeight * 0.9),
                padding: EdgeInsets.symmetric(vertical: 12),
                textStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.borderRadius)))
            .copyWith(
          // Garante que a elevação seja 0 quando desabilitado
          elevation: MaterialStateProperty.resolveWith<double>(
            (Set<MaterialState> states) {
              if (states.contains(MaterialState.disabled)) {
                return 0;
              }
              return 2.0; // Elevação padrão
            },
          ),
        ));
  }
} // Fim da classe _EmployeeDetailModalState
