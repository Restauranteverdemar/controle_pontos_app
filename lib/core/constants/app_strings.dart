// lib/core/constants/app_strings.dart

/// Constantes de string para uso em toda a aplicação
class AppStrings {
  // Títulos e rótulos
  static const pageTitle = 'Editar Funcionário';
  static const displayNameLabel = 'Nome de Exibição';
  static const emailLabel = 'Email';
  static const roleLabel = 'Papel';
  static const departmentLabel = 'Departamento';
  static const activeUserLabel = 'Usuário Ativo';

  // Botões e ações
  static const saveChangesButton = 'Salvar Alterações';
  static const resetPasswordButton = 'Enviar Email de Redefinição de Senha';
  static const deleteButton = 'Excluir Funcionário';
  static const cancelButton = 'Cancelar';
  static const deleteConfirmButton = 'Excluir';

  // Valores de papel e departamento
  static const adminRole = 'Admin';
  static const employeeRole = 'Funcionário';
  static const kitchenDepartment = 'Cozinha';
  static const diningRoomDepartment = 'Salão';

  // Mensagens de validação
  static const formErrorMessage = 'Por favor, corrija os erros no formulário.';
  static const nameRequiredError = 'Por favor, insira um nome de exibição.';
  static const emailRequiredError = 'Por favor, insira um email.';
  static const emailInvalidError = 'Por favor, insira um email válido.';
  static const roleRequiredError = 'Por favor, selecione um papel.';
  static const departmentRequiredError =
      'Por favor, selecione um departamento.';
  static const roleOrDepartmentInvalidError =
      'Erro: Papel ou Departamento inválido antes de salvar.';
  static const emailResetNotFoundError =
      'Email do usuário não encontrado para redefinição.';

  // Mensagens de erro
  static const loadingError = 'Erro ao carregar dados. Tente novamente.';
  static const userDataReadError = 'Erro ao ler os dados do funcionário.';
  static const userNotFoundError = 'Funcionário não encontrado.';
  static const userDataMissingError =
      'Dados do funcionário não foram carregados corretamente.';
  static const emailUpdateFailedError =
      'Falha ao atualizar email (resposta inesperada).';
  static const passwordResetFailedError =
      'Falha ao enviar email de redefinição (resposta inesperada).';
  static const unknownEmailUpdateError =
      'Erro desconhecido ao atualizar email.';
  static const unknownPasswordResetError =
      'Erro desconhecido ao enviar redefinição de senha.';
  static const noChangesDetected = 'Nenhuma alteração para salvar.';
  static const savingError = 'Erro ao salvar';
  static const deletingError = 'Erro ao excluir';
  static const passwordResetError = 'Erro ao enviar email';
  static const promoteToAdminError = 'Erro ao promover usuário para Admin';
  static const changeRoleError = 'Erro ao alterar papel/departamento';
  static const updateBasicDataError = 'Erro ao salvar dados básicos';
  static const updateEmailError =
      'Erro inesperado ao tentar atualizar o email.';
  static const sendPasswordResetGenericError =
      'Erro inesperado ao tentar enviar email de redefinição.';

  // Mensagens de sucesso
  static const resetEmailSuccess = 'Email de redefinição enviado para ';
  static const updateSuccess = 'Dados atualizados com sucesso!';
  static const deleteSuccess = 'Funcionário excluído com sucesso!';
  static const emailUpdateSuccess = ' (incluindo email)';
  static const promoteToAdminSuccess =
      'Usuário promovido para Admin com sucesso';
  static const passwordResetSuccess =
      'Email de redefinição de senha enviado com sucesso';

  // Diálogos
  static const deleteConfirmationTitle = 'Confirmar Exclusão';
  static const deleteConfirmationContent =
      'Tem certeza que deseja excluir permanentemente o funcionário "{name}"?\n\nEsta ação não pode ser desfeita.';
}
