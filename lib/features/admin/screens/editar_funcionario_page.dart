// lib/features/admin/screens/editar_funcionario_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

// Importações centralizadas - evitam os conflitos
import '../services/user_service.dart';
import '../../shared/models/employee.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';

//------------------------------------------------------------------------------
// HELPERS E COMPONENTES (Mantidos neste arquivo temporariamente)
//------------------------------------------------------------------------------

/// Helper para exibição de feedback visual ao usuário
class FeedbackHelper {
  /// Mostra uma mensagem de feedback usando SnackBar
  static void showFeedback(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isWarning = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!context.mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.hideCurrentSnackBar();

    Color backgroundColor = AppColors.successColor;
    if (isError) backgroundColor = AppColors.errorColor;
    if (isWarning) backgroundColor = AppColors.warningColor;

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
      ),
    );
  }

  /// Mostra feedback e navega de volta após um delay especificado
  static void showSuccessFeedbackAndNavigateBack(
    BuildContext context,
    String message, {
    Duration delay = const Duration(milliseconds: 600),
  }) {
    showFeedback(context, message);

    Future.delayed(delay, () {
      if (context.mounted) {
        Navigator.of(context).pop(true); // Retorna true para indicar sucesso
      }
    });
  }
}

/// Formatador de mensagens de erro para apresentação consistente
class ErrorFormatter {
  /// Formata mensagens de erro para exibição ao usuário
  static String formatErrorMessage(String prefix, Object error) {
    String errorMessage = error.toString();
    if (errorMessage.startsWith("Exception: ")) {
      errorMessage = errorMessage.substring("Exception: ".length);
    }

    // Prioriza mensagem da Cloud Function se disponível
    if (error is FirebaseFunctionsException) {
      errorMessage =
          error.message ?? "Erro desconhecido da função (${error.code})";
      return errorMessage; // Já é suficientemente descritiva
    }

    if (error is FirebaseException) {
      errorMessage =
          "Erro do Banco (${error.code}): ${error.message ?? 'sem mensagem'}";
    }

    return "$prefix: $errorMessage";
  }
}

/// Botão de ação personalizado com suporte para loading e ícones
class ActionButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color backgroundColor;
  final IconData? icon;

  const ActionButton({
    Key? key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.backgroundColor = Colors.blue,
    this.icon,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        backgroundColor: backgroundColor,
        foregroundColor: AppColors.white,
        minimumSize: Size(double.infinity, AppDimensions.buttonHeight),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
      child: isLoading
          ? SizedBox(
              width: AppDimensions.loadingIndicatorSize,
              height: AppDimensions.loadingIndicatorSize,
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon),
                  SizedBox(width: 8),
                ],
                Text(text, style: const TextStyle(fontSize: 16)),
              ],
            ),
    );
  }
}

//------------------------------------------------------------------------------
// TELA PRINCIPAL - EditarFuncionarioPage
//------------------------------------------------------------------------------
class EditarFuncionarioPage extends StatefulWidget {
  final String userId;

  const EditarFuncionarioPage({Key? key, required this.userId})
      : super(key: key);

  @override
  _EditarFuncionarioPageState createState() => _EditarFuncionarioPageState();
}

class _EditarFuncionarioPageState extends State<EditarFuncionarioPage> {
  // Serviço para comunicação com o Firebase
  final UserService _userService = UserService();

  // Chave para controle e validação do formulário
  final _formKey = GlobalKey<FormState>();

  // Controladores dos campos de texto
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  // Estado do formulário
  String? _selectedRole;
  String? _selectedDepartment;
  bool _isActive = true;
  bool _showDepartmentDropdown = false;

  // Estados de loading para feedback visual
  bool _isLoading = false;
  bool _isSendingResetEmail = false;
  bool _isLoadingData = true;
  bool _isDeletingUser = false;

  // Dados do funcionário e controle de erros
  Employee? _employee;
  String? _errorMessage;

  // Estado inicial para detectar mudanças
  String _initialEmail = '';
  String _initialRole = '';
  String? _initialDepartment;
  String _initialDisplayName = '';
  bool _initialIsActive = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    // Libera recursos dos controladores
    _displayNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Carrega os dados do funcionário a ser editado
  Future<void> _loadUserData() async {
    if (!mounted) return;

    setState(() {
      _isLoadingData = true;
      _errorMessage = null;
    });

    try {
      final Employee employeeData =
          await _userService.getEmployee(widget.userId);

      if (!mounted) return;

      _initializeFormFields(employeeData);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage =
            ErrorFormatter.formatErrorMessage(AppStrings.loadingError, e);
        _isLoadingData = false;
      });

      _logError("Erro ao carregar dados do funcionário: $e");
    }
  }

  /// Inicializa os campos do formulário com os dados do funcionário
  void _initializeFormFields(Employee employee) {
    // Salva estado inicial para detecção de mudanças
    _initialEmail = employee.email;
    _initialRole = employee.role ?? '';
    _initialDepartment = employee.department;
    _initialDisplayName = employee.displayName;
    _initialIsActive = employee.isActive;

    // Atualiza referência e campos do formulário
    _employee = employee;
    _displayNameController.text = employee.displayName;
    _emailController.text = employee.email;
    _selectedRole = employee.role;
    _selectedDepartment = employee.department;
    _isActive = employee.isActive;

    // Controla visibilidade do dropdown de departamento
    _showDepartmentDropdown = (employee.role == AppStrings.employeeRole);

    // Finaliza loading
    _isLoadingData = false;

    if (mounted) setState(() {});
  }

  /// Atualiza o estado quando a role do funcionário muda
  void _onRoleChanged(String? newRole) {
    setState(() {
      _selectedRole = newRole;
      _showDepartmentDropdown = (newRole == AppStrings.employeeRole);

      // Remove departamento se não for Funcionário
      if (!_showDepartmentDropdown) {
        _selectedDepartment = null;
      }
    });
  }

  /// Salva todas as alterações feitas no formulário
  Future<void> _saveChanges() async {
    // Validação do formulário
    if (!_formKey.currentState!.validate()) {
      _showFeedback(AppStrings.formErrorMessage, isWarning: true);
      return;
    }

    // Verifica se os dados foram carregados
    if (_employee == null || _initialRole.isEmpty) {
      _showFeedback(AppStrings.userDataMissingError, isError: true);
      return;
    }

    // Inicia o estado de loading
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Captura valores atuais do formulário
    final String newDisplayName = _displayNameController.text.trim();
    final String newEmail = _emailController.text.trim();
    final bool newIsActive = _isActive;
    final String? newRole = _selectedRole;
    final String? newDepartment = _selectedDepartment;

    // Detecta quais campos realmente mudaram
    final bool emailChanged = newEmail != _initialEmail;
    final bool roleChanged = newRole != _initialRole;
    final bool basicDataChanged = (newDisplayName != _initialDisplayName) ||
        (newIsActive != _initialIsActive);
    final bool departmentChanged = (newRole == AppStrings.employeeRole) &&
        (newDepartment != _initialDepartment);

    // Detecta casos especiais para tratamento apropriado
    bool promotionToAdmin = (_initialRole != AppStrings.adminRole) &&
        (newRole == AppStrings.adminRole);
    bool otherRoleOrDeptChange =
        (roleChanged || departmentChanged) && !promotionToAdmin;

    // Listas para controle de operações
    List<Future<String>> updateTasks = [];
    List<String> successMessages = [];

    try {
      // A. Promoção para Admin (tratada com prioridade)
      if (promotionToAdmin) {
        updateTasks.add(_userService.promoteToAdmin(widget.userId));
        _logInfo("Tarefa adicionada: promoteToAdmin");
      }
      // B. Outras mudanças de Role/Department
      else if (otherRoleOrDeptChange) {
        // Validações extras
        if (newRole == null) {
          throw Exception(AppStrings.roleRequiredError);
        }
        if (newRole == AppStrings.employeeRole && newDepartment == null) {
          throw Exception(AppStrings.departmentRequiredError);
        }

        // Chama função para alterar role/department
        updateTasks.add(_userService.changeUserRole(widget.userId, newRole,
            department: newDepartment));

        _logInfo("Tarefa adicionada: changeUserRole");
      }

      // C. Atualização de dados básicos
      if (basicDataChanged) {
        await _userService.updateEmployeeBasicData(
            widget.userId, newDisplayName, newIsActive);

        successMessages.add("Dados básicos atualizados");
        _logInfo("Concluído: updateEmployeeBasicData");
      }

      // D. Atualização de email
      if (emailChanged) {
        updateTasks
            .add(_userService.updateEmployeeEmail(widget.userId, newEmail));

        _logInfo("Tarefa adicionada: updateEmployeeEmail");
      }

      // Verifica se há alguma alteração a processar
      if (updateTasks.isEmpty && successMessages.isEmpty) {
        _showFeedback(AppStrings.noChangesDetected, isWarning: true);
        setState(() => _isLoading = false);
        return;
      }

      // Executa as tarefas assíncronas
      if (updateTasks.isNotEmpty) {
        final results = await Future.wait(updateTasks);
        for (final result in results) {
          successMessages.add(result);
        }
      }

      _logInfo("Todas as tarefas concluídas.");

      // Atualiza o estado inicial para refletir as mudanças
      _initialDisplayName = newDisplayName;
      _initialEmail = newEmail;
      _initialIsActive = newIsActive;
      _initialRole = newRole ?? _initialRole;
      _initialDepartment =
          newRole == AppStrings.employeeRole ? newDepartment : null;

      // Atualiza o objeto Employee para manter consistência
      if (_employee != null) {
        _employee!.displayName = _initialDisplayName;
        _employee!.email = _initialEmail;
        _employee!.role = _initialRole;
        _employee!.department = _initialDepartment;
        _employee!.isActive = _initialIsActive;
      }

      // Formata a mensagem de sucesso final
      String finalMessage = successMessages.isNotEmpty
          ? successMessages.join(". ")
          : AppStrings.updateSuccess;

      // Mostra feedback e navega de volta
      _showSuccessFeedbackAndNavigateBack(finalMessage);
    } catch (e) {
      _logError("Erro geral ao salvar: $e");

      if (mounted) {
        _showFeedback(
            ErrorFormatter.formatErrorMessage(AppStrings.savingError, e),
            isError: true);
      }
    } finally {
      // Garante que o estado de loading seja finalizado
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Envia email de redefinição de senha
  Future<void> _sendPasswordReset() async {
    if (_initialEmail.isEmpty) {
      _showFeedback(AppStrings.emailResetNotFoundError, isWarning: true);
      return;
    }

    setState(() {
      _isSendingResetEmail = true;
    });

    try {
      final String successMessage = await _userService.sendPasswordResetEmail(
          widget.userId, _initialEmail);

      _showFeedback(successMessage, isError: false);
    } catch (e) {
      _logError("Erro ao enviar reset de senha: $e");

      if (mounted) {
        _showFeedback(
            ErrorFormatter.formatErrorMessage(AppStrings.passwordResetError, e),
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingResetEmail = false;
        });
      }
    }
  }

  /// Confirma e executa a exclusão do funcionário
  Future<void> _confirmAndDeleteUser() async {
    // Evita ação durante outras operações
    if (_isLoading || _isSendingResetEmail || _isDeletingUser) return;

    // Solicita confirmação do usuário
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.deleteConfirmationTitle),
        content: Text(AppStrings.deleteConfirmationContent.replaceAll(
            '{name}', _employee?.displayName ?? "este funcionário")),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancelButton),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.errorColor),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.deleteConfirmButton),
          ),
        ],
      ),
    );

    // Cancela se não confirmado
    if (confirmed != true) return;

    // Inicia exclusão
    setState(() {
      _isDeletingUser = true;
    });

    try {
      final result = await _userService.deleteUser(widget.userId);
      _showSuccessFeedbackAndNavigateBack(result);
    } catch (e) {
      _logError("Erro ao excluir usuário: $e");

      if (mounted) {
        _showFeedback(
            ErrorFormatter.formatErrorMessage(AppStrings.deletingError, e),
            isError: true);
      }
    } finally {
      // Trata a finalização do estado de loading
      if (mounted && Navigator.canPop(context)) {
        // Navegação será feita pelo showSuccessFeedbackAndNavigateBack
      } else if (mounted) {
        setState(() {
          _isDeletingUser = false;
        });
      }
    }
  }

  // Métodos auxiliares
  void _showFeedback(String message,
      {bool isError = false, bool isWarning = false}) {
    FeedbackHelper.showFeedback(context, message,
        isError: isError, isWarning: isWarning);
  }

  void _showSuccessFeedbackAndNavigateBack(String message) {
    FeedbackHelper.showSuccessFeedbackAndNavigateBack(context, message);
  }

  void _logInfo(String message) {
    debugPrint("[EditarFuncionarioPage] INFO: $message");
  }

  void _logError(String message) {
    debugPrint("[EditarFuncionarioPage] ERROR: $message");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text(AppStrings.pageTitle)),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(), // Esconde teclado
          child: _buildPageContent(),
        ));
  }

  /// Constrói o conteúdo principal da página com base no estado atual
  Widget _buildPageContent() {
    if (_isLoadingData) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _employee == null) {
      return Center(
          child: Padding(
        padding: AppDimensions.padding,
        child: Text(_errorMessage!,
            style: const TextStyle(color: AppColors.errorColor, fontSize: 16),
            textAlign: TextAlign.center),
      ));
    }

    if (_employee == null) {
      return const Center(child: Text(AppStrings.userDataReadError));
    }

    return _buildForm();
  }

  /// Constrói o formulário de edição
  Widget _buildForm() {
    return Padding(
      padding: AppDimensions.padding,
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            _buildNameField(),
            SizedBox(height: AppDimensions.formItemSpacing),
            _buildEmailField(),
            SizedBox(height: AppDimensions.formItemSpacing),
            _buildRoleDropdown(),
            SizedBox(height: AppDimensions.formItemSpacing),
            _buildDepartmentDropdown(),
            SizedBox(height: AppDimensions.formItemSpacing),
            _buildActiveSwitch(),
            SizedBox(height: AppDimensions.largeSpacing),
            _buildActionButtons(),
            SizedBox(height: AppDimensions.bottomSpacing),
          ],
        ),
      ),
    );
  }

  /// Constrói o campo de nome
  Widget _buildNameField() {
    return TextFormField(
      controller: _displayNameController,
      decoration: const InputDecoration(
          labelText: AppStrings.displayNameLabel,
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person)),
      validator: (value) => (value == null || value.trim().isEmpty)
          ? AppStrings.nameRequiredError
          : null,
      textInputAction: TextInputAction.next,
      enabled: !_isLoading && !_isDeletingUser,
    );
  }

  /// Constrói o campo de email
  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
          labelText: AppStrings.emailLabel,
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.email)),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return AppStrings.emailRequiredError;
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
            .hasMatch(value.trim())) {
          return AppStrings.emailInvalidError;
        }
        return null;
      },
      textInputAction: TextInputAction.next,
      enabled: !_isLoading && !_isDeletingUser,
    );
  }

  /// Constrói o dropdown de papel (Role)
  Widget _buildRoleDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedRole,
      decoration: const InputDecoration(
          labelText: AppStrings.roleLabel,
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.security)),
      items: const [
        DropdownMenuItem(
            value: AppStrings.adminRole, child: Text(AppStrings.adminRole)),
        DropdownMenuItem(
            value: AppStrings.employeeRole,
            child: Text(AppStrings.employeeRole)),
      ],
      onChanged: (_isLoading || _isDeletingUser) ? null : _onRoleChanged,
      validator: (value) =>
          (value == null) ? AppStrings.roleRequiredError : null,
    );
  }

  /// Constrói o dropdown de departamento (condicional)
  Widget _buildDepartmentDropdown() {
    return AnimatedOpacity(
      opacity: _showDepartmentDropdown ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Visibility(
        visible: _showDepartmentDropdown,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: DropdownButtonFormField<String>(
          value: _selectedDepartment,
          decoration: const InputDecoration(
              labelText: AppStrings.departmentLabel,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.work_outline)),
          items: const [
            DropdownMenuItem(value: null, child: Text("Nenhum / Selecione...")),
            DropdownMenuItem(
                value: AppStrings.kitchenDepartment,
                child: Text(AppStrings.kitchenDepartment)),
            DropdownMenuItem(
                value: AppStrings.diningRoomDepartment,
                child: Text(AppStrings.diningRoomDepartment)),
          ],
          onChanged:
              (_showDepartmentDropdown && !_isLoading && !_isDeletingUser)
                  ? (String? newValue) {
                      setState(() {
                        _selectedDepartment = newValue;
                      });
                    }
                  : null,
          validator: (value) => (_showDepartmentDropdown && value == null)
              ? AppStrings.departmentRequiredError
              : null,
        ),
      ),
    );
  }

  /// Constrói o switch de ativação do usuário
  Widget _buildActiveSwitch() {
    return SwitchListTile(
      title: const Text(AppStrings.activeUserLabel),
      value: _isActive,
      onChanged: (_isLoading || _isDeletingUser)
          ? null
          : (bool newValue) {
              setState(() {
                _isActive = newValue;
              });
            },
      secondary: Icon(_isActive ? Icons.check_circle : Icons.cancel,
          color: _isActive
              ? AppColors.activeUserColor
              : AppColors.inactiveUserColor),
      contentPadding: EdgeInsets.zero,
      activeColor: AppColors.activeUserColor,
    );
  }

  /// Constrói os botões de ação
  Widget _buildActionButtons() {
    final bool anyOperationInProgress =
        _isLoading || _isSendingResetEmail || _isDeletingUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActionButton(
          text: AppStrings.saveChangesButton,
          onPressed: anyOperationInProgress ? null : _saveChanges,
          isLoading: _isLoading,
          backgroundColor: Theme.of(context).primaryColor,
          icon: Icons.save,
        ),
        const SizedBox(height: AppDimensions.buttonSpacing),
        ActionButton(
          text: AppStrings.resetPasswordButton,
          onPressed: anyOperationInProgress ? null : _sendPasswordReset,
          isLoading: _isSendingResetEmail,
          backgroundColor: AppColors.resetPasswordButtonColor,
          icon: Icons.lock_reset,
        ),
        const SizedBox(height: AppDimensions.buttonSpacing),
        ActionButton(
          text: AppStrings.deleteButton,
          onPressed: anyOperationInProgress ? null : _confirmAndDeleteUser,
          isLoading: _isDeletingUser,
          backgroundColor: AppColors.errorColor,
          icon: Icons.delete_forever,
        ),
      ],
    );
  }
}
