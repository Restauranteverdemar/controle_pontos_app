/**
 * Firebase Cloud Functions para o App de Gestão de Ocorrências
 *
 * Este arquivo contém:
 * - Gatilhos (Triggers) do Firebase (ex: onCreateUser, onOccurrenceStatusChange)
 * - Funções HTTP Callable para serem chamadas pelo app Flutter (ex: createUser, deleteUser)
 * - Utilitários e constantes para organização e manutenção.
 */

// Importações centralizadas para melhor visibilidade e manutenção
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const automationRules = require('./automationRules');
const monthlyReset = require('./monthlyReset');
const resetDiagnostics = require('./resetDiagnostics');

// Inicializa o Firebase Admin SDK uma vez
// Verifica se já foi inicializado para evitar erros em reloads/testes locais
if (!admin.apps.length) { // Simplificação da verificação para melhor legibilidade
  admin.initializeApp();
}

// Obtém uma referência global ao Firestore para reutilização
const db = admin.firestore();

// Importa constantes e utilitários do arquivo utils.js
const {
  REGION,
  COLLECTIONS,
  USER_ROLES,
  OPERATION_STATUS,
  LOG_LEVELS,
  logOperation,
} = require("./utils");

// Mensagens de erro padronizadas para facilitar manutenção e i18n futura
const ERROR_MESSAGES = {
  NOT_AUTHENTICATED: "Você precisa estar logado para executar esta ação.",
  ADMIN_ONLY: "Somente administradores podem realizar esta ação.",
  MISSING_USER_ID: "ID do usuário é obrigatório.",
  MISSING_EMAIL: "Email é obrigatório.",
  MISSING_PASSWORD: "Senha é obrigatória.",
  MISSING_EMAIL_OR_PASSWORD: "Email e senha são obrigatórios.",
  INVALID_EMAIL_FORMAT: "Formato de email inválido.",
  CANNOT_DELETE_SELF: "Você não pode excluir sua própria conta.",
  CANNOT_PROMOTE_SELF: "Você não pode se auto-promover.",
  DEPARTMENT_REQUIRED: "Campo 'department' é obrigatório para role 'Funcionário'.", // Extraído para constante para consistência
  INVALID_ROLE: (role) => `Role '${role}' inválida. Deve ser '${USER_ROLES.ADMIN}' ou '${USER_ROLES.FUNCIONARIO}'.`, // Nova mensagem parametrizada
  USER_NOT_FOUND: (userId) => `Usuário ${userId} não encontrado.`,
  EMAIL_ALREADY_EXISTS: (email) => `O email ${email} já está em uso.`,
  NO_EMAIL_REGISTERED: (userId) => `Usuário ${userId} não possui email registrado.`,
  INTERNAL_ERROR: (operation) => `Erro interno ao ${operation}. Contate o suporte.`,
};

// Mapeamento de códigos de erro do Auth para mensagens amigáveis
const AUTH_ERROR_MAP = { // Novo objeto para centralizar mapeamento de erros do Auth
  'auth/user-not-found': (data) => ERROR_MESSAGES.USER_NOT_FOUND(data.userId || 'desconhecido'),
  'auth/email-already-exists': (data) => ERROR_MESSAGES.EMAIL_ALREADY_EXISTS(data.email || data.newEmail || 'desconhecido'),
  'auth/email-already-in-use': (data) => ERROR_MESSAGES.EMAIL_ALREADY_EXISTS(data.email || data.newEmail || 'desconhecido'),
  'auth/invalid-email': () => ERROR_MESSAGES.INVALID_EMAIL_FORMAT,
  'auth/invalid-password': () => "Formato de senha inválido (geralmente mínimo 6 caracteres)."
};

// =================================================================
// UTILITÁRIOS
// =================================================================

/**
 * Validadores de dados centralizados para reuso
 */
const validators = {
  /**
   * Valida formato de email usando expressão regular
   * @param {string} email - O email a ser validado
   * @returns {boolean} - Verdadeiro se o email for válido
   */
  isValidEmail: (email) => {
    if (!email || typeof email !== 'string') return false;
    // Expressão regular mais robusta para validação de email
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  },

  /**
   * Verifica campos obrigatórios em um objeto de dados
   * @param {Object} data - Objeto com dados a serem validados
   * @param {Array<string>} requiredFields - Lista de campos obrigatórios
   * @returns {string|null} - Mensagem de erro ou null se tudo estiver ok
   */
  checkRequiredFields: (data, requiredFields) => {
    if (!data) return "Dados não fornecidos.";

    for (const field of requiredFields) {
      // Verifica se o campo existe, não é nulo e não é string vazia
      if (data[field] === undefined || data[field] === null || data[field] === '') {
        return `Campo '${field}' é obrigatório e não pode ser vazio.`;
      }
    }
    return null; // Nenhum erro encontrado
  },

  /**
   * Verifica se o valor da role é válido
   * @param {string} role - A role a ser validada
   * @returns {boolean} - Verdadeiro se a role for válida
   */
  // Nova função para centralizar validação de roles
  isValidRole: (role) => {
    return [USER_ROLES.ADMIN, USER_ROLES.FUNCIONARIO].includes(role);
  }
};

/**
 * Operações comuns do Firebase centralizadas para reuso
 */
const firebaseUtils = {
  /**
   * Verifica se um usuário possui role de Admin
   * Otimizado para verificar claims primeiro (mais eficiente)
   * @param {string} uid - ID do usuário
   * @returns {Promise<boolean>} - Verdadeiro se o usuário for admin
   */
  isUserAdmin: async (uid) => {
    if (!uid) return false;
    try {
      // Verifica claims primeiro (mais eficiente)
      const user = await admin.auth().getUser(uid);
      if (user.customClaims && user.customClaims.role === USER_ROLES.ADMIN) {
        return true;
      }

      // Fallback para Firestore se as claims não estiverem configuradas ou divergirem
      // (pode acontecer durante transições ou erros)
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(uid).get();
      return userDoc.exists && userDoc.data()?.role === USER_ROLES.ADMIN;
    } catch (error) {
      // Loga o erro, mas considera não-admin por segurança
      functions.logger.error(`Erro ao verificar status admin para usuário ${uid}:`, error);
      return false;
    }
  },

  /**
   * Cria estrutura padrão de dados para novo usuário no Firestore
   * @param {Object} userData - Dados básicos do usuário (email, displayName)
   * @param {Object} additionalData - Dados adicionais como role, department, isActive
   * @returns {Object} - Objeto formatado para inserção no Firestore
   */
  createUserData: (userData, additionalData = {}) => {
    const timestamp = admin.firestore.FieldValue.serverTimestamp();
    const { email } = userData; // Usando destructuring para melhor legibilidade
    
    // Gera displayName a partir do email se não fornecido explicitamente
    const displayName = userData.displayName || (email ? email.split('@')[0] : "Usuário");
    const role = additionalData.role || USER_ROLES.FUNCIONARIO; // Default: Funcionário
    
    // Objeto base com valores padrão
    const baseData = {
      email,
      displayName,
      role,
      // Departamento só é definido se a role for Funcionário e um valor for passado
      department: (role === USER_ROLES.FUNCIONARIO && additionalData.department) 
                 ? additionalData.department 
                 : null,
      isActive: typeof additionalData.isActive === 'boolean' ? additionalData.isActive : true,
      saldoPontosAprovados: 0, // Inicializa com zero pontos
      createdAt: timestamp, // Timestamp de criação
      lastUpdated: timestamp, // Timestamp da última atualização
    };
    
    // Spread para adicionar propriedades adicionais e não sobrescrever importantes
    return { ...baseData, ...additionalData };
  },

  /**
   * Função unificada para log estruturado com consistência
   * @param {string} level - Nível do log: INFO, WARN, ERROR
   * @param {string} operation - Nome da operação sendo realizada (ex: 'CALLABLE_CREATE_USER')
   * @param {string} status - Status/etapa da operação (ex: 'STARTED', 'SUCCESS', 'FAILED')
   * @param {Object} details - Detalhes adicionais para o log (ex: { userId, email })
   */
  logOperation, // Usa a função importada de utils.js

  /**
   * Utilitário para tratamento padronizado de erros em funções callable
   * Mapeia erros conhecidos para códigos HttpsError apropriados e loga o erro.
   * @param {Error} error - O erro capturado no bloco catch
   * @param {Object} data - Dados da requisição original para contexto no log
   * @param {string} operation - Nome da operação onde o erro ocorreu
   * @param {string} [callerUid] - UID do usuário que chamou a função (se disponível)
   * @throws {functions.https.HttpsError} - Erro formatado para ser retornado ao cliente Flutter
   */
  handleCallableError: (error, data, operation, callerUid) => {
    const errorDetails = {
      callerUid: callerUid || 'N/A', // UID de quem chamou a função
      requestData: data, // Dados recebidos na chamada
      errorMessage: error.message, // Mensagem original do erro
      errorCode: error.code, // Código original do erro (se houver)
      errorStack: error.stack, // Stack trace (útil para depuração)
    };

    // Loga o erro com detalhes para análise posterior
    firebaseUtils.logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.FAILED, errorDetails);

    // Se o erro já for um HttpsError (lançado intencionalmente antes), apenas o propaga
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }

    // Usando o mapeamento centralizado AUTH_ERROR_MAP para códigos de erro do Auth
    if (error.code && AUTH_ERROR_MAP[error.code]) {
      const errorMessage = AUTH_ERROR_MAP[error.code](data);
      const errorType = error.code.includes('not-found') ? "not-found" :
                        error.code.includes('already-exists') ? "already-exists" : 
                        "invalid-argument";
      
      throw new functions.https.HttpsError(errorType, errorMessage);
    }

    // Para erros não mapeados, lança um erro interno genérico
    throw new functions.https.HttpsError(
      "internal",
      ERROR_MESSAGES.INTERNAL_ERROR(operation.toLowerCase().replace('callable_', ''))
    );
  },
  
  /**
   * Função para atualizar claims de usuário no Auth
   * @param {string} userId - ID do usuário
   * @param {string} role - Role a ser definida
   * @param {string} operation - Nome da operação para logging
   * @param {string} callerUid - ID do usuário que fez a chamada
   * @returns {Promise<boolean>} - Verdadeiro se atualização foi bem-sucedida
   */
  // Nova função utilitária para centralizar atualização de claims
  updateUserClaims: async (userId, role, operation, callerUid) => {
    try {
      await admin.auth().setCustomUserClaims(userId, { role });
      firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'AUTH_CLAIMS_SET', { callerUid, userId, role });
      return true;
    } catch (authError) {
      // Se o usuário não for encontrado no Auth, loga aviso mas continua
      if (authError.code === 'auth/user-not-found') {
        firebaseUtils.logOperation(LOG_LEVELS.WARN, operation, 'AUTH_USER_NOT_FOUND_ON_CLAIM_SET', { callerUid, userId });
        return false;
      }
      // Relança outros erros do Auth
      throw authError;
    }
  }
};

/**
 * Verificações de segurança centralizadas para reuso em funções callable
 */
const securityChecks = {
  /**
   * Garante que o usuário chamador está autenticado e é um Admin.
   * @param {functions.https.CallableContext} context - Contexto da função callable
   * @returns {Promise<string>} - Retorna o UID do admin autenticado
   * @throws {functions.https.HttpsError} - Se não autenticado ('unauthenticated')
   *                                        ou não for admin ('permission-denied')
   */
  ensureIsAdmin: async (context) => {
    // 1. Verifica se o contexto de autenticação existe
    if (!context.auth || !context.auth.uid) {
      firebaseUtils.logOperation(LOG_LEVELS.WARN, 'AUTH_CHECK', OPERATION_STATUS.FAILED, { reason: 'No auth context' });
      throw new functions.https.HttpsError(
        "unauthenticated",
        ERROR_MESSAGES.NOT_AUTHENTICATED
      );
    }

    const callerUid = context.auth.uid;

    // 2. Verifica se o usuário autenticado tem permissão de Admin
    const isAdmin = await firebaseUtils.isUserAdmin(callerUid);
    if (!isAdmin) {
      firebaseUtils.logOperation(LOG_LEVELS.WARN, 'ADMIN_CHECK', OPERATION_STATUS.FAILED, { callerUid });
      throw new functions.https.HttpsError(
        "permission-denied",
        ERROR_MESSAGES.ADMIN_ONLY
      );
    }

    // Se passou nas verificações, loga sucesso e retorna o UID
    firebaseUtils.logOperation(LOG_LEVELS.INFO, 'ADMIN_CHECK', OPERATION_STATUS.SUCCESS, { callerUid });
    return callerUid;
  },
  
  /**
   * Utilitário para validar que o chamador não está manipulando seu próprio usuário
   * @param {string} callerUid - ID do usuário chamador
   * @param {string} targetUid - ID do usuário alvo da operação
   * @param {string} errorMessage - Mensagem de erro a ser lançada
   * @throws {functions.https.HttpsError} - Se caller = target
   */
  // Nova função que centraliza verificação de não auto-manipulação
  ensureNotSelfModification: (callerUid, targetUid, errorMessage) => {
    if (callerUid === targetUid) {
      throw new functions.https.HttpsError("invalid-argument", errorMessage);
    }
  }
};

// =================================================================
// TRIGGERS DO FIREBASE (Executados automaticamente em eventos)
// =================================================================

/**
 * Trigger do Firebase Authentication: onCreateUser
 * Acionado quando um novo usuário é criado no Firebase Authentication.
 * Cria um documento correspondente na coleção 'users' do Firestore.
 */
exports.onCreateUser = functions.region(REGION).auth.user().onCreate(async (user) => {
  const { uid, email, displayName } = user; // Usando destructuring para melhor legibilidade
  const operation = "TRIGGER_ON_CREATE_USER";

  firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { userId: uid, email });

  // Validação básica dos dados recebidos do Auth
  if (!uid || !email) {
    firebaseUtils.logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.ABORTED, {
      reason: 'Dados do usuário do Auth incompletos (uid ou email ausente)',
      authUserData: user // Loga os dados recebidos para depuração
    });
    return null; // Encerra a função sem erro para evitar retentativas desnecessárias
  }

  try {
    const userRef = db.collection(COLLECTIONS.USERS).doc(uid);

    // Verifica se o documento já existe (pode ter sido criado pela função callable 'createUser')
    const doc = await userRef.get();
    if (doc.exists) {
       firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SKIPPED, {
         userId: uid,
         reason: 'Documento Firestore já existe (provavelmente criado via createUser)'
       });
       return null; // Documento já existe, não fazer nada
    }

    // Usa o utilitário para criar a estrutura de dados padrão para o novo usuário
    // Assume role 'Funcionário' por padrão se criado diretamente pelo Auth (ex: signup manual)
    const baseUserData = firebaseUtils.createUserData({ email, displayName }, { role: USER_ROLES.FUNCIONARIO });

    // Cria o documento no Firestore
    await userRef.set(baseUserData);

    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { userId: uid, email });
    return null; // Indica sucesso

  } catch (error) {
    // Loga qualquer erro ocorrido durante a escrita no Firestore
    firebaseUtils.logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.FAILED, {
      userId: uid,
      email,
      errorMessage: error.message,
      errorCode: error.code
    });
    // Retorna null para não fazer o Firebase tentar executar o trigger novamente
    return null;
  }
});


/**
 * Trigger do Firestore: onOccurrenceStatusChange
 * Acionado sempre que um documento na coleção 'pointsOccurrences' é ATUALIZADO.
 * Responsável por ajustar o 'saldoPontosAprovados' do funcionário correspondente
 * quando o status da ocorrência muda para ou de 'Aprovada'.
 */
exports.onOccurrenceStatusChange = functions.region(REGION)
  .firestore.document(`${COLLECTIONS.POINT_OCCURRENCES}/{occurrenceId}`)
  .onUpdate(async (change, context) => {
    const operation = "TRIGGER_ON_OCCURRENCE_UPDATE";
    const occurrenceId = context.params.occurrenceId; // ID da ocorrência modificada

    // Dados do documento ANTES e DEPOIS da atualização
    const beforeData = change.before.data();
    const afterData = change.after.data();

    // Validação: Se não houver dados antes ou depois, algo muito estranho aconteceu.
    if (!beforeData || !afterData) {
      firebaseUtils.logOperation(LOG_LEVELS.WARN, operation, 'ABORTED_NO_DATA', {
        occurrenceId,
        hasBeforeData: !!beforeData,
        hasAfterData: !!afterData,
      });
      return null; // Sair sem erro
    }

    // Extrai o ID do usuário. Tenta pegar do 'afterData' primeiro, fallback para 'beforeData'.
    const userId = afterData.userId || beforeData.userId;
    if (!userId) {
      // Isso não deveria acontecer se a ocorrência foi salva corretamente. Logar como erro.
      firebaseUtils.logOperation(LOG_LEVELS.ERROR, operation, 'ABORTED_NO_USERID', {
        occurrenceId,
        beforeData: JSON.stringify(beforeData), // Log completo para investigar
        afterData: JSON.stringify(afterData),
      });
      return null; // Sair sem erro para evitar retentativas
    }

    // Log inicial com informações chave
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, {
      occurrenceId,
      userId,
      beforeStatus: beforeData.status,
      afterStatus: afterData.status,
      beforePoints: beforeData.finalPoints, // Logar os pontos também ajuda
      afterPoints: afterData.finalPoints,
    });

    const userRef = db.collection(COLLECTIONS.USERS).doc(userId); // Referência ao documento do usuário
    
    // Função auxiliar interna para lidar com a atualização de pontos
    const updateUserPoints = async (pointsChange, action) => {
      // Validação: Pontos deve ser um número
      if (typeof pointsChange !== 'number') {
        firebaseUtils.logOperation(LOG_LEVELS.WARN, operation, `${action}_MISSING_POINTS_DATA`, {
          occurrenceId,
          userId,
          finalPointsValue: pointsChange,
          reason: `finalPoints is not a number or is missing.`,
        });
        return null;
      }
      
      try {
        // ATUALIZAÇÃO ATÔMICA: Incrementa/decrementa o saldo e atualiza timestamp
        await userRef.update({
          saldoPontosAprovados: admin.firestore.FieldValue.increment(
            action === 'APPROVAL' ? pointsChange : -pointsChange
          ),
          lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });
        
        firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 
          action === 'APPROVAL' ? 'APPROVAL_POINTS_ADDED' : 'REVERSAL_POINTS_REMOVED', {
          occurrenceId,
          userId,
          pointsChanged: pointsChange,
        });
        
        return null; // Sucesso
      } catch (error) {
        firebaseUtils.logOperation(LOG_LEVELS.ERROR, operation, 
          `${action}_UPDATE_FAILED`, {
          occurrenceId,
          userId,
          pointsChange,
          errorMessage: error.message,
          errorCode: error.code,
        });
        return null; // Falha, mas retorna null para não retentar
      }
    };

    // --- Cenário 1: Ocorrência foi APROVADA nesta atualização ---
    if (beforeData.status !== 'Aprovada' && afterData.status === 'Aprovada') {
      firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'PROCESSING_APPROVAL', {
        occurrenceId,
        userId,
        pointsToAdd: afterData.finalPoints,
      });
      
      return updateUserPoints(afterData.finalPoints, 'APPROVAL');
    }
    
    // --- Cenário 2: Aprovação foi REVERTIDA nesta atualização ---
    else if (beforeData.status === 'Aprovada' && afterData.status !== 'Aprovada') {
      firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'PROCESSING_REVERSAL', {
        occurrenceId,
        userId,
        pointsToReverse: beforeData.finalPoints,
        newStatus: afterData.status,
      });
      
      return updateUserPoints(beforeData.finalPoints, 'REVERSAL');
    }
    
    // --- Outros Cenários: Nenhuma mudança de/para 'Aprovada' ---
    else {
      firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'NO_POINTS_CHANGE_NEEDED', {
        occurrenceId,
        userId,
        beforeStatus: beforeData.status,
        afterStatus: afterData.status,
        reason: "Status change did not involve transitioning to or from 'Aprovada'."
      });
      return null; // Nenhuma ação de pontos necessária
    }
});

/**
 * Trigger do Firestore: onOccurrenceDelete
 * Acionado sempre que um documento na coleção 'pointsOccurrences' é EXCLUÍDO.
 * Responsável por ajustar o 'saldoPontosAprovados' do funcionário correspondente
 * quando uma ocorrência com status 'Aprovada' é excluída.
 */
exports.onOccurrenceDelete = functions.region(REGION)
  .firestore.document(`${COLLECTIONS.POINT_OCCURRENCES}/{occurrenceId}`)
  .onDelete(async (snapshot, context) => {
    const operation = "TRIGGER_ON_OCCURRENCE_DELETE";
    const occurrenceId = context.params.occurrenceId; // ID da ocorrência excluída

    // Dados do documento excluído
    const deletedData = snapshot.data();

    // Validação: Se não houver dados, algo muito estranho aconteceu.
    if (!deletedData) {
      firebaseUtils.logOperation(LOG_LEVELS.WARN, operation, 'ABORTED_NO_DATA', {
        occurrenceId,
      });
      return null; // Sair sem erro
    }

    // Extrai o ID do usuário e o status da ocorrência excluída
    const userId = deletedData.userId;
    const status = deletedData.status;
    const finalPoints = deletedData.finalPoints;

    if (!userId) {
      // Isso não deveria acontecer se a ocorrência foi salva corretamente. Logar como erro.
      firebaseUtils.logOperation(LOG_LEVELS.ERROR, operation, 'ABORTED_NO_USERID', {
        occurrenceId,
        deletedData: JSON.stringify(deletedData),
      });
      return null; // Sair sem erro para evitar retentativas
    }

    // Log inicial com informações chave
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, {
      occurrenceId,
      userId,
      status,
      finalPoints,
    });

    // Verifica se a ocorrência excluída estava com status "Aprovada"
    // Só é necessário subtrair pontos se era uma ocorrência aprovada
    if (status !== 'Aprovada') {
      firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'NO_POINTS_CHANGE_NEEDED', {
        occurrenceId,
        userId,
        status,
        reason: "A ocorrência excluída não estava com status 'Aprovada'."
      });
      return null; // Nenhuma ação de pontos necessária
    }

    // Validação: Pontos deve ser um número
    if (typeof finalPoints !== 'number') {
      firebaseUtils.logOperation(LOG_LEVELS.WARN, operation, 'MISSING_POINTS_DATA', {
        occurrenceId,
        userId,
        finalPointsValue: finalPoints,
        reason: `finalPoints is not a number or is missing.`,
      });
      return null;
    }

    const userRef = db.collection(COLLECTIONS.USERS).doc(userId); // Referência ao documento do usuário
    
    try {
      // ATUALIZAÇÃO ATÔMICA: Decrementa o saldo de pontos e atualiza timestamp
      await userRef.update({
        saldoPontosAprovados: admin.firestore.FieldValue.increment(-finalPoints),
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });
      
      firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'POINTS_REMOVED_AFTER_DELETE', {
        occurrenceId,
        userId,
        pointsRemoved: finalPoints,
      });
      
      return null; // Sucesso
    } catch (error) {
      firebaseUtils.logOperation(LOG_LEVELS.ERROR, operation, 'UPDATE_FAILED', {
        occurrenceId,
        userId,
        pointsToRemove: finalPoints,
        errorMessage: error.message,
        errorCode: error.code,
      });
      return null; // Falha, mas retorna null para não retentar
    }
});

/**
 * Trigger do Firestore: onOccurrenceCreate
 * Acionado sempre que um novo documento é criado na coleção 'pointsOccurrences'.
 * Este trigger pode ser usado para reagir à criação de uma ocorrência com regras 
 * do tipo 'onOccurrenceCreate', se/quando implementado.
 * 
 * Nota: Essa função está comentada até que o tipo de regra 'onOccurrenceCreate' seja suportado.
 */
/*
exports.onOccurrenceCreate = functions.region(REGION)
  .firestore.document(`${COLLECTIONS.POINT_OCCURRENCES}/{occurrenceId}`)
  .onCreate(async (snapshot, context) => {
    // Verifica se a ocorrência foi criada pelo sistema automático para evitar loops
    const data = snapshot.data();
    if (data && data.registeredBy === 'system/automatic') {
      // Loga mas não processa regras para evitar loops infinitos
      firebaseUtils.logOperation(LOG_LEVELS.INFO, "TRIGGER_ON_OCCURRENCE_CREATE", 'SKIPPED_AUTOMATIC', {
        occurrenceId: context.params.occurrenceId,
        reason: "Ocorrência criada pelo sistema automático, não processando regras"
      });
      return null;
    }
    
    // Passa para o processador de regras reativas
    return automationRules.processOnOccurrenceCreate(snapshot, context);
  });
*/

// =================================================================
// FUNÇÕES HTTP CALLABLE (Chamadas explicitamente pelo App Flutter)
// =================================================================

/**
 * Função HTTP Callable: createUser
 * Permite que um Admin crie um novo usuário (Auth + Firestore + Claims se Admin).
 */
exports.createUser = functions.region(REGION).https.onCall(async (data, context) => {
  const operation = "CALLABLE_CREATE_USER";
  let callerUid;

  try {
    // 1. Verifica se quem chama é Admin
    callerUid = await securityChecks.ensureIsAdmin(context);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { callerUid, requestData: data });

    // 2. Extrai e valida dados da requisição
    const { email, password, displayName, role, department, isActive } = data;

    // Validação de campos obrigatórios usando utilitário
    const missingFieldsError = validators.checkRequiredFields(data, ['email', 'password', 'role']);
    if (missingFieldsError) {
      throw new functions.https.HttpsError("invalid-argument", missingFieldsError);
    }
    
    // Validação específica para Funcionário (department é obrigatório)
    if (role === USER_ROLES.FUNCIONARIO && !department) {
      throw new functions.https.HttpsError("invalid-argument", ERROR_MESSAGES.DEPARTMENT_REQUIRED);
    }
    
    // Validação formato do email
    if (!validators.isValidEmail(email)) {
      throw new functions.https.HttpsError("invalid-argument", ERROR_MESSAGES.INVALID_EMAIL_FORMAT);
    }
    
    // Validação de role usando função centralizada
    if (!validators.isValidRole(role)) {
      throw new functions.https.HttpsError("invalid-argument", ERROR_MESSAGES.INVALID_ROLE(role));
    }

    // 3. Cria usuário no Firebase Authentication
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'CREATING_AUTH_USER', { callerUid, email });
    
    const userRecord = await admin.auth().createUser({
      email,
      password,
      displayName: displayName || email.split('@')[0], // Usa parte do email se displayName não vier
      emailVerified: false, // Usuário começa com email não verificado
      disabled: false, // Usuário começa ativo no Auth
    });
    
    const newUserId = userRecord.uid;
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'AUTH_USER_CREATED', { callerUid, newUserId, email });

    // 4. Define Custom Claims usando função centralizada
    await firebaseUtils.updateUserClaims(newUserId, role, operation, callerUid);

    // 5. Cria documento no Firestore usando o utilitário
    const userDataForFirestore = firebaseUtils.createUserData(
      { email, displayName: userRecord.displayName }, // Usa dados do Auth como base
      { role, department, isActive } // Adiciona dados específicos da requisição
    );
    
    await db.collection(COLLECTIONS.USERS).doc(newUserId).set(userDataForFirestore);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'FIRESTORE_DOC_CREATED', { callerUid, newUserId });

    // 6. Retorna sucesso para o app Flutter
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { callerUid, newUserId, email });
    return {
      success: true,
      userId: newUserId,
      message: `Usuário ${email} criado com sucesso com role ${role}.`
    };

  } catch (error) {
    // Usa o handler centralizado para logar e retornar erro formatado
    return firebaseUtils.handleCallableError(error, data, operation, callerUid);
  }
});


/**
 * Função HTTP Callable: updateUserEmail
 * Permite que um Admin atualize o email de OUTRO usuário (Auth + Firestore).
 */
exports.updateUserEmail = functions.region(REGION).https.onCall(async (data, context) => {
  const operation = "CALLABLE_UPDATE_USER_EMAIL";
  let callerUid;

  try {
    // 1. Verifica permissões de Admin
    callerUid = await securityChecks.ensureIsAdmin(context);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { callerUid, requestData: data });

    // 2. Extrai e valida dados necessários
    const { userId, newEmail } = data;
    const missingFieldsError = validators.checkRequiredFields(data, ['userId', 'newEmail']);
    if (missingFieldsError) {
      throw new functions.https.HttpsError("invalid-argument", missingFieldsError);
    }
    
    if (!validators.isValidEmail(newEmail)) {
      throw new functions.https.HttpsError("invalid-argument", ERROR_MESSAGES.INVALID_EMAIL_FORMAT);
    }
    
    // Não permitir que o Admin altere o próprio email por esta função usando função centralizada
    securityChecks.ensureNotSelfModification(
      callerUid, 
      userId, 
      "Admins não podem alterar o próprio email por esta função."
    );

    // 3. Atualiza email no Firebase Authentication
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'UPDATING_AUTH_EMAIL', { callerUid, userId, newEmail });
    await admin.auth().updateUser(userId, { email: newEmail });
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'AUTH_EMAIL_UPDATED', { callerUid, userId, newEmail });

    // 4. Atualiza email e timestamp 'lastUpdated' no Firestore
    await db.collection(COLLECTIONS.USERS).doc(userId).update({
      email: newEmail,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'FIRESTORE_DOC_UPDATED', { callerUid, userId, newEmail });

    // 5. Retorna sucesso
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { callerUid, userId, newEmail });
    return {
      success: true,
      message: `Email do usuário ${userId} atualizado para ${newEmail}.`
    };

  } catch (error) {
    // Usa handler centralizado
    return firebaseUtils.handleCallableError(error, data, operation, callerUid);
  }
});


/**
 * Função HTTP Callable: sendUserPasswordReset
 * Permite que um Admin dispare o email de redefinição de senha para um usuário específico.
 */
exports.sendUserPasswordReset = functions.region(REGION).https.onCall(async (data, context) => {
  const operation = "CALLABLE_SEND_PASSWORD_RESET";
  let callerUid;

  try {
    // 1. Verifica permissões de Admin
    callerUid = await securityChecks.ensureIsAdmin(context);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { callerUid, requestData: data });

    // 2. Valida userId
    const { userId } = data;
    if (!userId) {
      throw new functions.https.HttpsError("invalid-argument", ERROR_MESSAGES.MISSING_USER_ID);
    }

    // 3. Obtém o email do usuário a partir do Auth (necessário para enviar o link)
    let userEmail;
    try {
      const userRecord = await admin.auth().getUser(userId);
      userEmail = userRecord.email;
      
      if (!userEmail) {
        firebaseUtils.logOperation(LOG_LEVELS.WARN, operation, 'FAILED_PRECONDITION_NO_EMAIL', { callerUid, userId });
        throw new functions.https.HttpsError("failed-precondition", ERROR_MESSAGES.NO_EMAIL_REGISTERED(userId));
      }
    } catch(authError) {
      // Se o usuário não for encontrado no Auth, lança erro específico
      if (authError.code === 'auth/user-not-found') {
        throw new functions.https.HttpsError("not-found", ERROR_MESSAGES.USER_NOT_FOUND(userId));
      }
      throw authError; // Relança outros erros do Auth
    }

    // 4. Gera e envia o link de redefinição de senha usando o email obtido
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'SENDING_RESET_EMAIL', { callerUid, userId, userEmail });
    await admin.auth().generatePasswordResetLink(userEmail);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'RESET_EMAIL_SENT', { callerUid, userId, userEmail });

    // 5. Retorna sucesso
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { callerUid, userId, userEmail });
    return {
      success: true,
      message: `Email de redefinição de senha enviado para ${userEmail}.`
    };

  } catch (error) {
    // Usa handler centralizado
    return firebaseUtils.handleCallableError(error, data, operation, callerUid);
  }
});


/**
 * Função HTTP Callable: promoteUserToAdmin
 * Permite que um Admin promova OUTRO usuário para a role de Admin (Firestore + Claims).
 */
exports.promoteUserToAdmin = functions.region(REGION).https.onCall(async (data, context) => {
  const operation = "CALLABLE_PROMOTE_TO_ADMIN";
  let callerUid;

  try {
    // 1. Verifica permissões de Admin
    callerUid = await securityChecks.ensureIsAdmin(context);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { callerUid, requestData: data });

    // 2. Valida userId
    const { userId } = data;
    if (!userId) {
      throw new functions.https.HttpsError("invalid-argument", ERROR_MESSAGES.MISSING_USER_ID);
    }

    // 3. Previne auto-promoção usando função centralizada
    securityChecks.ensureNotSelfModification(callerUid, userId, ERROR_MESSAGES.CANNOT_PROMOTE_SELF);

    // 4. Verifica se o usuário a ser promovido existe no Firestore
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      // Se não existe no Firestore, não pode ser promovido (mesmo que exista no Auth)
      throw new functions.https.HttpsError("not-found", ERROR_MESSAGES.USER_NOT_FOUND(userId));
    }

    // 5. Atualiza o documento no Firestore: define role=Admin e remove 'department'
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'UPDATING_FIRESTORE_ROLE', { callerUid, userId });
    await userRef.update({
      role: USER_ROLES.ADMIN,
      department: admin.firestore.FieldValue.delete(), // Remove campo department
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'FIRESTORE_ROLE_UPDATED', { callerUid, userId });

    // 6. Define Custom Claims no Auth usando a função centralizada
    await firebaseUtils.updateUserClaims(userId, USER_ROLES.ADMIN, operation, callerUid);

    // 7. Retorna sucesso
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { callerUid, userId });
    return {
      success: true,
      message: `Usuário ${userId} promovido para Admin com sucesso.`
    };

  } catch (error) {
    // Usa handler centralizado
    return firebaseUtils.handleCallableError(error, data, operation, callerUid);
  }
});

/**
 * Função HTTP Callable: deleteUser
 * Permite que um Admin exclua permanentemente OUTRO usuário (Auth + Firestore).
 */
exports.deleteUser = functions.region(REGION).https.onCall(async (data, context) => {
  const operation = "CALLABLE_DELETE_USER";
  let callerUid;

  try {
    // 1. Verifica permissões de Admin
    callerUid = await securityChecks.ensureIsAdmin(context);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { callerUid, requestData: data });

    // 2. Valida userId
    const { userId } = data;
    if (!userId) {
      throw new functions.https.HttpsError("invalid-argument", ERROR_MESSAGES.MISSING_USER_ID);
    }

    // 3. Previne auto-exclusão usando função centralizada
    securityChecks.ensureNotSelfModification(callerUid, userId, ERROR_MESSAGES.CANNOT_DELETE_SELF);

    // 4. Tenta excluir do Firebase Authentication
    let authDeleted = false;
    try {
      firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'DELETING_AUTH_USER', { callerUid, userId });
      await admin.auth().deleteUser(userId);
      authDeleted = true;
      firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'AUTH_USER_DELETED', { callerUid, userId });
    } catch (authError) {
      // Se o usuário não existe no Auth, loga um aviso mas continua para excluir do Firestore
      if (authError.code === 'auth/user-not-found') {
        firebaseUtils.logOperation(LOG_LEVELS.WARN, operation, 'AUTH_DELETE_SKIPPED_NOT_FOUND', { callerUid, userId });
      } else {
        // Para outros erros inesperados do Auth, interrompe a operação
        firebaseUtils.logOperation(LOG_LEVELS.ERROR, operation, 'AUTH_DELETE_FAILED', {
          callerUid, userId, errorMessage: authError.message, errorCode: authError.code
        });
        throw authError; // Relança o erro para ser tratado pelo handler
      }
    }

    // 5. Exclui do Firestore (sempre tenta, mesmo se falhou no Auth)
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'DELETING_FIRESTORE_DOC', { callerUid, userId });
    const userDocRef = db.collection(COLLECTIONS.USERS).doc(userId);
    await userDocRef.delete();
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'FIRESTORE_DOC_DELETED', { callerUid, userId });

    // 6. Retorna sucesso
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { callerUid, userId, authDeleted });
    return {
      success: true,
      message: authDeleted
        ? `Usuário ${userId} excluído com sucesso do Auth e Firestore.`
        : `Usuário ${userId} não encontrado no Auth, mas removido do Firestore.`
    };

  } catch (error) {
    // Usa handler centralizado (que já trata o caso 'auth/user-not-found' se relançado)
    return firebaseUtils.handleCallableError(error, data, operation, callerUid);
  }
});


/**
 * Função HTTP Callable: changeUserRole
 * Permite que um Admin altere a role e/ou departamento de OUTRO usuário.
 * Trata a lógica de adicionar/remover 'department' e atualizar Claims.
 */
exports.changeUserRole = functions.region(REGION).https.onCall(async (data, context) => {
  const operation = "CALLABLE_CHANGE_USER_ROLE";
  let callerUid;

  try {
    // 1. Verifica permissões de Admin
    callerUid = await securityChecks.ensureIsAdmin(context);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { callerUid, requestData: data });

    // 2. Extrai e valida dados
    const { userId, newRole, department } = data;

    // Validação de campos obrigatórios
    const missingFieldsError = validators.checkRequiredFields(data, ['userId', 'newRole']);
    if (missingFieldsError) {
      throw new functions.https.HttpsError("invalid-argument", missingFieldsError);
    }

    // Validação da Role usando a função centralizada
    if (!validators.isValidRole(newRole)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        ERROR_MESSAGES.INVALID_ROLE(newRole)
      );
    }

    // Validação do Departamento (obrigatório se a nova role for Funcionário)
    if (newRole === USER_ROLES.FUNCIONARIO && !department) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        ERROR_MESSAGES.DEPARTMENT_REQUIRED
      );
    }

    // 3. Verifica se o usuário alvo existe no Firestore
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      throw new functions.https.HttpsError("not-found", ERROR_MESSAGES.USER_NOT_FOUND(userId));
    }

    // 4. Prepara os dados para atualização no Firestore
    const updateData = {
      role: newRole,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    };

    // Adiciona ou remove o campo 'department' conforme a nova role
    if (newRole === USER_ROLES.ADMIN) {
      // Para Admin, remove o campo department (se existir)
      updateData.department = admin.firestore.FieldValue.delete();
    } else { // newRole === USER_ROLES.FUNCIONARIO
      // Para Funcionário, define/atualiza o department
      updateData.department = department;
    }

    // 5. Atualiza o documento no Firestore
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'UPDATING_FIRESTORE_ROLE_DEPT', { 
      callerUid, 
      userId, 
      newRole, 
      department: updateData.department 
    });
    
    await userRef.update(updateData);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, 'FIRESTORE_ROLE_DEPT_UPDATED', { callerUid, userId });

    // 6. Atualiza Custom Claims no Auth usando função centralizada
    await firebaseUtils.updateUserClaims(userId, newRole, operation, callerUid);

    // 7. Retorna sucesso
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { callerUid, userId, newRole });
    
    // Gera mensagem de resposta de forma mais concisa usando template literals
    const successMessage = `Papel/departamento do usuário ${userId} atualizado com sucesso para Role: ${newRole}` + 
                           (newRole === USER_ROLES.FUNCIONARIO ? `, Departamento: ${department}.` : '.');
                           
    return {
      success: true,
      message: successMessage
    };

  } catch (error) {
    // Usa handler centralizado
    return firebaseUtils.handleCallableError(error, data, operation, callerUid);
  }
});

// =================================================================
// FUNÇÕES AGENDADAS (SCHEDULER)
// =================================================================

/**
 * Função agendada para executar diariamente à meia-noite (horário de Brasília).
 * Avalia as regras automáticas configuradas com frequência "daily".
 */
exports.scheduledDailyRules = functions.region(REGION)
  .pubsub.schedule('0 0 * * *')
  .timeZone('America/Sao_Paulo')
  .onRun(automationRules.processDailyRules);

/**
 * Função agendada para executar semanalmente às segundas-feiras à meia-noite (horário de Brasília).
 * Avalia as regras automáticas configuradas com frequência "weekly".
 */
exports.scheduledWeeklyRules = functions.region(REGION)
  .pubsub.schedule('0 0 * * 1')
  .timeZone('America/Sao_Paulo')
  .onRun(automationRules.processWeeklyRules);

/**
 * Função agendada para executar mensalmente no primeiro dia do mês à meia-noite (horário de Brasília).
 * Avalia as regras automáticas configuradas com frequência "monthly".
 */
exports.scheduledMonthlyRules = functions.region(REGION)
  .pubsub.schedule('0 0 1 * *')
  .timeZone('America/Sao_Paulo')
  .onRun(automationRules.processMonthlyRules);

  // Adicione estas linhas ao seu index.js
exports.debugMonthlyReset = require('./debugMonthlyReset').debugMonthlyReset;
exports.checkEmployeeDashboardQuery = require('./debugMonthlyReset').checkEmployeeDashboardQuery;
exports.forceUpdatePeriodIds = require('./forceUpdatePeriodIds').forceUpdatePeriodIds;
exports.forceCreateMissingSnapshots = require('./forceUpdatePeriodIds').forceCreateMissingSnapshots;


// =================================================================
// EXPORTS PARA TESTES (Se necessário)
// =================================================================
exports.processDailyRules = automationRules.processDailyRules;
exports.processWeeklyRules = automationRules.processWeeklyRules;
exports.processMonthlyRules = automationRules.processMonthlyRules;
exports.processOnOccurrenceCreate = automationRules.processOnOccurrenceCreate;

// Exportar as funções de diagnóstico
exports.diagnoseMonthlyResetSystem = resetDiagnostics.diagnoseMonthlyResetSystem;
exports.fixAllOccurrences = resetDiagnostics.fixAllOccurrences;
exports.testSingleUserReset = resetDiagnostics.testSingleUserReset;
exports.validateMonthlyResetImplementation = resetDiagnostics.validateMonthlyResetImplementation;
exports.getFixInstructions = resetDiagnostics.getFixInstructions;
exports.createMissingSnapshots = resetDiagnostics.createMissingSnapshots;

/**
 * Função callable para resetar saldos mensais manualmente (para admin)
 * Útil para testes e situações excepcionais
 */
exports.resetMonthlyBalanceManual = functions.region(REGION).https.onCall(async (data, context) => {
  const operation = "CALLABLE_RESET_MONTHLY_BALANCE";
  let callerUid;

  try {
    // 1. Verifica permissões de Admin
    callerUid = await securityChecks.ensureIsAdmin(context);
    console.log(`[${operation}] Admin ${callerUid} iniciou reset manual`);
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { callerUid });

    // 2. Executa o reset mensal, passando admin e db explicitamente
    console.log(`[${operation}] Chamando função resetMonthlyBalances...`);
    const result = await monthlyReset.resetMonthlyBalances(admin, db);
    
    if (!result) {
      throw new Error("A função resetMonthlyBalances retornou um resultado vazio ou indefinido");
    }
    
    console.log(`[${operation}] Reset completado com sucesso:`, JSON.stringify(result));
    
    // 3. Registra a operação em logs administrativos
    try {
      const logRef = db.collection('adminLogs').doc();
      await logRef.set({
        action: 'manualMonthlyReset',
        executedBy: callerUid,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        result: {
          processedUsers: result.processedUsers || 0,
          yearMonth: result.yearMonth || 'N/A',
          success: result.success || false,
          batches: result.batches || 0
        }
      });
      console.log(`[${operation}] Log administrativo registrado com sucesso`);
    } catch (logError) {
      // Se falhar ao registrar log, apenas registramos o erro mas continuamos
      console.error(`[${operation}] Erro ao registrar log administrativo:`, logError);
    }
    
    // 4. Retorna sucesso
    firebaseUtils.logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { 
      callerUid,
      processedUsers: result.processedUsers || 0,
      yearMonth: result.yearMonth || 'N/A'
    });
    
    return {
      success: true,
      message: `Reset mensal executado com sucesso. ${result.processedUsers || 0} usuários processados.`,
      details: {
        processedUsers: result.processedUsers || 0,
        yearMonth: result.yearMonth || 'N/A',
        batches: result.batches || 0
      }
    };

  } catch (error) {
    console.error(`[${operation}] Erro ao executar reset mensal:`, error);
    
    // Registrar stack trace para diagnóstico
    if (error.stack) {
      console.error(`[${operation}] Stack trace:`, error.stack);
    }
    
    // Usar handler centralizado para formatar resposta de erro
    return firebaseUtils.handleCallableError(error, data, operation, callerUid);
  }
});
// --- Constantes de Configuração (Recomendado) ---
const SCHEDULE_TIMEZONE = "America/Sao_Paulo"; // <-- CONFIRME SEU FUSO HORÁRIO
// Executa às 5:00 AM do dia 1 de cada mês, no fuso horário definido
const MONTHLY_RESET_SCHEDULE = "0 5 1 * *";
// Para testar, você pode usar um schedule mais frequente como "every 5 minutes"
// Lembre-se de trocar de volta para o mensal antes de ir para produção!
// const MONTHLY_RESET_SCHEDULE_TEST = "every 5 minutes";

// =================================================================
// FUNÇÃO AGENDADA PARA RESET MENSAL
// =================================================================
exports.scheduledMonthlyBalanceReset = functions
    .region(REGION) // Define a região
    .pubsub
    .schedule(MONTHLY_RESET_SCHEDULE) // Define a frequência (CRON Job)
    // .schedule(MONTHLY_RESET_SCHEDULE_TEST) // Use este para testar
    .timeZone(SCHEDULE_TIMEZONE) // Define o fuso horário
    .onRun(async (context) => {
        const logPrefix = "[ScheduledReset]"; // Prefixo para logs
        const executionId = context.eventId || Date.now(); // ID para rastrear execução
        console.log(`${logPrefix} [${executionId}] Iniciando execução agendada do reset mensal.`);
        // Logar detalhes do evento pode ser útil para depuração
        // console.log(`${logPrefix} Contexto da execução:`, JSON.stringify(context));

        try {
            // Chama a função de lógica de reset, passando admin e db
            // Esta é a MESMA função que o reset manual chamou com sucesso
            console.log(`${logPrefix} [${executionId}] Chamando monthlyReset.resetMonthlyBalances...`);
            const result = await monthlyReset.resetMonthlyBalances(admin, db);

            // Loga o resultado detalhado para acompanhamento
            console.log(`${logPrefix} [${executionId}] Reset mensal agendado concluído com sucesso. Resultado:`, JSON.stringify(result));

            // (Opcional) Registrar um log no Firestore para auditoria do sistema
            /*
            try {
              await db.collection('systemLogs').add({
                event: 'scheduledMonthlyReset',
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                executionId: executionId,
                success: true,
                details: result,
              });
            } catch (logError) {
              console.error(`${logPrefix} [${executionId}] Falha ao registrar log de sucesso no Firestore:`, logError);
            }
            */

            return null; // Indica sucesso para o Cloud Scheduler
        } catch (error) {
            console.error(`${logPrefix} [${executionId}] ERRO CRÍTICO na execução agendada do reset mensal:`, error);
             // Logar stack trace se disponível
            if (error.stack) {
               console.error(`${logPrefix} [${executionId}] Stack trace:`, error.stack);
            }

            // (Opcional) Registrar um log de ERRO no Firestore
            /*
             try {
              await db.collection('systemLogs').add({
                event: 'scheduledMonthlyReset',
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                executionId: executionId,
                success: false,
                error: error.message || JSON.stringify(error),
              });
            } catch (logError) {
              console.error(`${logPrefix} [${executionId}] Falha ao registrar log de ERRO no Firestore:`, logError);
            }
            */

            // Mesmo em caso de erro, geralmente retornamos null para não tentar reexecutar
            // indefinidamente, a menos que a função seja configurada para retentativas.
            // O erro já foi logado para análise.
            return null;
        }
    });

// =================================================================
// FIM DAS FUNÇÕES
// =================================================================