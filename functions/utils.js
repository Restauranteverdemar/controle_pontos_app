// functions/src/utils.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");

// =================================================================
// CONSTANTES COMPARTILHADAS
// =================================================================

// Configuração regional compartilhada para todas as funções
const REGION = "southamerica-east1"; // São Paulo

// Constantes para coleções - facilita manutenção e previne erros de digitação
const COLLECTIONS = {
  USERS: "users",
  INCIDENT_TYPES: "incidentTypes",
  POINT_OCCURRENCES: "pointsOccurrences",
  AUTOMATION_RULES: "automationRules" // Adicionado para suportar o motor de regras
};

// Constantes para papéis de usuário
const USER_ROLES = {
  ADMIN: "Admin",
  FUNCIONARIO: "Funcionário"
};

// Constantes para status de operação - melhora a consistência dos logs
const OPERATION_STATUS = {
  STARTED: 'STARTED',
  SUCCESS: 'SUCCESS',
  FAILED: 'FAILED',
  SKIPPED: 'SKIPPED',
  ABORTED: 'ABORTED'
};

// Constantes para níveis de log - melhora a consistência dos logs
const LOG_LEVELS = {
  INFO: 'INFO',
  WARN: 'WARN',
  ERROR: 'ERROR',
  DEBUG: 'DEBUG'
};

// Constantes para frequências de gatilho (Motor de Regras)
const TRIGGER_FREQUENCY = {
  DAILY: 'daily',
  WEEKLY: 'weekly',
  MONTHLY: 'monthly',
  // ON_OCCURRENCE_CREATE: 'onOccurrenceCreate', // Comentado até ser suportado
};

// Constantes para tipos de condição (Motor de Regras)
const CONDITION_TYPE = {
  OCCURRENCE_COUNT: 'occurrenceCount',
  ABSENCE_OF_OCCURRENCE: 'absenceOfOccurrence',
  // Futuros tipos podem ser adicionados aqui
};

// Constantes para status de ocorrência
const OCCURRENCE_STATUS = {
  PENDING: 'Pendente',
  APPROVED: 'Aprovada',
  REPROVED: 'Reprovada'
};

// =================================================================
// FUNÇÕES UTILITÁRIAS
// =================================================================

/**
 * Função unificada para log estruturado com consistência
 * @param {string} level - Nível do log: INFO, WARN, ERROR, DEBUG
 * @param {string} operation - Nome da operação sendo realizada
 * @param {string} status - Status/etapa da operação
 * @param {Object} details - Detalhes adicionais para o log (opcional)
 */
function logOperation(level, operation, status, details = {}) {
  // Remove potenciais dados sensíveis do log antes de registrar
  const safeDetails = { ...details };
  // Usando Array para centralizar os campos sensíveis que devem ser redatados
  const sensitiveFields = ['password', 'senha', 'accessToken', 'refreshToken'];
  
  sensitiveFields.forEach(field => {
    if (field in safeDetails) {
      safeDetails[field] = '[REDACTED]';
    }
  });

  const logData = {
    operation,
    status,
    timestamp: new Date().toISOString(), // Timestamp em formato ISO
    ...safeDetails,
  };

  // Formata mensagem com prefixo consistente para fácil leitura
  const message = `[${operation}] ${status}`;

  // Usando constantes LOG_LEVELS para maior consistência
  switch (level) {
    case LOG_LEVELS.INFO:
      functions.logger.info(message, logData);
      break;
    case LOG_LEVELS.WARN:
      functions.logger.warn(message, logData);
      break;
    case LOG_LEVELS.ERROR:
      functions.logger.error(message, logData);
      break;
    case LOG_LEVELS.DEBUG:
      functions.logger.debug(message, logData);
      break;
    default:
      // Fallback para log padrão se nível for inválido
      functions.logger.log(message, logData);
  }
}

/**
 * Busca dados do usuário no Firestore pelo ID.
 * @param {string} userId - ID do usuário.
 * @param {FirebaseFirestore.Firestore} db - Instância opcional do Firestore.
 * @returns {Promise<Object|null>} - Dados do usuário ou null se não encontrado.
 */
async function getUserData(userId, db = admin.firestore()) {
  if (!userId) return null;
  
  try {
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) return null;
    return userDoc.data();
  } catch (error) {
    logOperation(LOG_LEVELS.ERROR, 'GET_USER_DATA', OPERATION_STATUS.FAILED, {
      userId,
      error: error.message
    });
    return null;
  }
}

/**
 * Busca dados do tipo de incidente no Firestore pelo ID.
 * @param {string} incidentTypeId - ID do tipo de incidente.
 * @param {FirebaseFirestore.Firestore} db - Instância opcional do Firestore.
 * @returns {Promise<Object|null>} - Dados do tipo de incidente ou null se não encontrado.
 */
async function getIncidentTypeData(incidentTypeId, db = admin.firestore()) {
  if (!incidentTypeId) return null;
  
  try {
    const incidentTypeDoc = await db.collection(COLLECTIONS.INCIDENT_TYPES).doc(incidentTypeId).get();
    if (!incidentTypeDoc.exists) return null;
    return incidentTypeDoc.data();
  } catch (error) {
    logOperation(LOG_LEVELS.ERROR, 'GET_INCIDENT_TYPE_DATA', OPERATION_STATUS.FAILED, {
      incidentTypeId,
      error: error.message
    });
    return null;
  }
}

// =================================================================
// EXPORTS
// =================================================================
module.exports = {
  REGION,
  COLLECTIONS,
  USER_ROLES,
  OPERATION_STATUS,
  LOG_LEVELS,
  TRIGGER_FREQUENCY,
  CONDITION_TYPE,
  OCCURRENCE_STATUS,
  logOperation,
  getUserData,
  getIncidentTypeData,
};