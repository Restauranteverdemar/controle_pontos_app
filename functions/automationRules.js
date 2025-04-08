// functions/src/automationRules.js

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// --- Importa Utilitários e Constantes Compartilhadas ---
const {
  REGION,
  COLLECTIONS,
  OPERATION_STATUS,
  LOG_LEVELS,
  TRIGGER_FREQUENCY,
  CONDITION_TYPE,
  OCCURRENCE_STATUS,
  logOperation,
  getUserData,
  getIncidentTypeData,
} = require("./utils"); // Ajustado caminho (removido ../)

// Nota: O DB é passado como parâmetro para as funções internas agora

// =================================================================
// FUNÇÕES INTERNAS (Lógica do Motor de Regras)
// =================================================================

/**
 * Processa regras automáticas para uma dada frequência.
 * @param {FirebaseFirestore.Firestore} db Instância do Firestore.
 * @param {string} frequency Frequência a processar ("daily", "weekly", "monthly").
 */
const evaluateRulesForFrequency = async (db, frequency) => {
  const operation = `EVALUATE_RULES_${frequency.toUpperCase()}`;
  logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { frequency });

  try {
    const rulesSnapshot = await db.collection(COLLECTIONS.AUTOMATION_RULES)
      .where('isEnabled', '==', true)
      .where('triggerFrequency', '==', frequency)
      .get();

    if (rulesSnapshot.empty) {
      logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SKIPPED, { reason: `Nenhuma regra ativa para ${frequency}` });
      return;
    }

    logOperation(LOG_LEVELS.INFO, operation, 'RULES_FOUND', { frequency, count: rulesSnapshot.size });

    for (const ruleDoc of rulesSnapshot.docs) {
      const rule = { id: ruleDoc.id, ...ruleDoc.data() };
      // Envolve o processamento da regra em try/catch para não parar tudo se uma falhar
      try {
          await processRule(db, rule);
      } catch (ruleError) {
          logOperation(LOG_LEVELS.ERROR, operation, 'RULE_PROCESSING_FAILED', {
              ruleId: rule.id, ruleName: rule.name, error: ruleError.message, stack: ruleError.stack
          });
      }
    }
    logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { frequency });
  } catch (error) {
    logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.FAILED, { frequency, error: error.message });
  }
};

/**
 * Processa uma regra individual, buscando usuários aplicáveis.
 * @param {FirebaseFirestore.Firestore} db Instância do Firestore.
 * @param {object} rule Objeto da regra.
 */
async function processRule(db, rule) {
  const operation = "PROCESS_RULE";
  // Validação mínima da regra
  if (!rule || !rule.id || !rule.name || !rule.condition || !rule.action || !rule.targetScope) {
      logOperation(LOG_LEVELS.WARN, operation, OPERATION_STATUS.ABORTED, { ruleId: rule?.id, reason: "Regra mal formada ou incompleta"});
      return;
  }
  logOperation(LOG_LEVELS.DEBUG, operation, OPERATION_STATUS.STARTED, { ruleId: rule.id, ruleName: rule.name });

  try {
    let usersQuery = db.collection(COLLECTIONS.USERS).where('isActive', '==', true);

    // Filtro de escopo (usa 'targetScope' do modelo AutomationRule)
    if (rule.targetScope !== 'all') {
      usersQuery = usersQuery.where('department', '==', rule.targetScope);
    }

    const usersSnapshot = await usersQuery.get();

    if (usersSnapshot.empty) {
      logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SKIPPED, { ruleId: rule.id, targetScope: rule.targetScope, reason: 'No active users found in scope' });
      return;
    }

    logOperation(LOG_LEVELS.DEBUG, operation, 'USERS_IN_SCOPE', { ruleId: rule.id, count: usersSnapshot.size });

    // Processa para cada usuário
    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;
      const userData = userDoc.data();
      if (!userData) continue;

      try {
        await processRuleForEmployee(db, rule, userId, userData);
      } catch (employeeError) {
         logOperation(LOG_LEVELS.ERROR, operation, 'EMPLOYEE_PROCESSING_FAILED', {
            ruleId: rule.id, userId, error: employeeError.message
         });
      }
    }
     logOperation(LOG_LEVELS.DEBUG, operation, OPERATION_STATUS.SUCCESS, { ruleId: rule.id });

  } catch (error) {
    logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.FAILED, { ruleId: rule.id, error: error.message });
  }
}

/**
 * Processa uma regra para um funcionário específico.
 * @param {FirebaseFirestore.Firestore} db Instância do Firestore.
 * @param {object} rule Objeto da regra.
 * @param {string} userId ID do funcionário.
 * @param {object} userData Dados do funcionário.
 */
async function processRuleForEmployee(db, rule, userId, userData) {
  const operation = "PROCESS_RULE_FOR_EMPLOYEE";
  logOperation(LOG_LEVELS.DEBUG, operation, OPERATION_STATUS.STARTED, { ruleId: rule.id, userId });

  const conditionResult = await evaluateCondition(db, rule.condition, userId, userData, rule.triggerFrequency);

  logOperation(LOG_LEVELS.INFO, operation, 'CONDITION_EVALUATED', {
      ruleId: rule.id, userId, conditionMet: conditionResult.isTrue, reason: conditionResult.reason
  });

  if (conditionResult.isTrue) {
    // Passa ruleId e ruleName para rastreabilidade na ação
    await executeRuleAction(db, rule.action, userId, userData, rule.id, rule.name);
    logOperation(LOG_LEVELS.INFO, operation, 'ACTION_EXECUTED', { ruleId: rule.id, userId });
  } else {
     logOperation(LOG_LEVELS.DEBUG, operation, OPERATION_STATUS.SKIPPED, { ruleId: rule.id, userId, reason: 'Condition not met' });
  }
   logOperation(LOG_LEVELS.DEBUG, operation, OPERATION_STATUS.SUCCESS, { ruleId: rule.id, userId });
}

/**
 * Avalia a condição da regra para um funcionário.
 * @param {FirebaseFirestore.Firestore} db Instância do Firestore.
 * @param {object} condition Objeto da condição (rule.condition).
 * @param {string} userId ID do funcionário.
 * @param {object} userData Dados do funcionário.
 * @param {string} frequency Frequência da regra ("daily", "weekly", "monthly").
 * @returns {Promise<{isTrue: boolean, reason: string}>} Resultado.
 */
async function evaluateCondition(db, condition, userId, userData, frequency) {
  const operation = "EVALUATE_CONDITION";

  if (!condition?.type) return { isTrue: false, reason: "Condição inválida ou sem tipo." };
  const conditionType = condition.type;
  logOperation(LOG_LEVELS.DEBUG, operation, OPERATION_STATUS.STARTED, { userId, conditionType, frequency });

  // Define o período de busca
  let daysToLookBack = 0;
  if (frequency === TRIGGER_FREQUENCY.DAILY) daysToLookBack = 1;
  else if (frequency === TRIGGER_FREQUENCY.WEEKLY) daysToLookBack = 7;
  else if (frequency === TRIGGER_FREQUENCY.MONTHLY) daysToLookBack = 30; // Ajuste se precisar de exatidão mensal
  else return { isTrue: false, reason: `Frequência inválida: ${frequency}` }; // Não deveria acontecer

  // Calcula data de início (meia-noite do dia N dias atrás)
  const startDate = new Date();
  startDate.setDate(startDate.getDate() - daysToLookBack);
  startDate.setHours(0, 0, 0, 0);
  const periodStartTimestamp = admin.firestore.Timestamp.fromDate(startDate);

  // --- Lógica OCCURRENCE_COUNT ---
  if (conditionType === CONDITION_TYPE.OCCURRENCE_COUNT) {
    const { incidentTypeIdCondition, threshold, comparisonOperator } = condition;
    if (!incidentTypeIdCondition || typeof threshold !== 'number' || !comparisonOperator) {
      return { isTrue: false, reason: "Dados inválidos para 'occurrenceCount'." };
    }
    try {
      const query = db.collection(COLLECTIONS.POINT_OCCURRENCES)
        .where('userId', '==', userId)
        .where('incidentTypeId', '==', incidentTypeIdCondition)
        .where('status', '==', OCCURRENCE_STATUS.APPROVED) // Geralmente conta aprovadas
        .where('createdAt', '>=', periodStartTimestamp); // Use o campo de data correto

      const snapshot = await query.get();
      const count = snapshot.size;
      logOperation(LOG_LEVELS.DEBUG, operation, 'COUNT_CHECK', { userId, incidentTypeIdCondition, count, threshold, comparisonOperator });

      let met = false;
      switch (comparisonOperator) {
        case 'greaterThan': met = count > threshold; break;
        case 'lessThan': met = count < threshold; break;
        case 'equalTo': met = count === threshold; break;
        case 'greaterThanOrEqualTo': met = count >= threshold; break;
        case 'lessThanOrEqualTo': met = count <= threshold; break;
        default: return { isTrue: false, reason: `Operador inválido: ${comparisonOperator}` };
      }
      return { isTrue: met, reason: `Contagem (${count}) ${comparisonOperator} Limite (${threshold}) = ${met}` };
    } catch(error) { /* log e return false */ logOperation(LOG_LEVELS.ERROR, operation, 'COUNT_QUERY_FAILED', {userId, error: error.message}); return { isTrue: false, reason: "Erro na query de contagem." }; }
  }

  // --- Lógica ABSENCE_OF_OCCURRENCE ---
  else if (conditionType === CONDITION_TYPE.ABSENCE_OF_OCCURRENCE) {
    const { incidentTypeIdCondition } = condition;
    if (!incidentTypeIdCondition) return { isTrue: false, reason: "Dados inválidos para 'absenceOfOccurrence'." };
    try {
      const query = db.collection(COLLECTIONS.POINT_OCCURRENCES)
        .where('userId', '==', userId)
        .where('incidentTypeId', '==', incidentTypeIdCondition)
        // Verifica QUALQUER status no período? Ou só Aprovadas? Ajuste se necessário
        // Ex: .where('status', '==', OCCURRENCE_STATUS.APPROVED)
        .where('createdAt', '>=', periodStartTimestamp) // Use o campo de data correto
        .limit(1); // Otimização: só precisamos saber se existe >= 1

      const snapshot = await query.get();
      const exists = !snapshot.empty;
      logOperation(LOG_LEVELS.DEBUG, operation, 'ABSENCE_CHECK', { userId, incidentTypeIdCondition, exists });
      // Condição é VERDADEIRA se NÃO existe
      return { isTrue: !exists, reason: `Ausência de ${incidentTypeIdCondition} = ${!exists}` };
    } catch(error) { /* log e return false */ logOperation(LOG_LEVELS.ERROR, operation, 'ABSENCE_QUERY_FAILED', {userId, error: error.message}); return { isTrue: false, reason: "Erro na query de ausência." }; }
  }

  // --- Adicione outros tipos de condição aqui ---

  // Tipo não suportado
  else {
    logOperation(LOG_LEVELS.WARN, operation, OPERATION_STATUS.SKIPPED, { userId, reason: `Tipo de condição não suportado: ${conditionType}` });
    return { isTrue: false, reason: `Tipo de condição não suportado: ${conditionType}` };
  }
}

/**
 * Executa a ação da regra: Criar uma ocorrência.
 * @param {FirebaseFirestore.Firestore} db Instância do Firestore.
 * @param {object} action Objeto da ação (rule.action).
 * @param {string} userId ID do funcionário.
 * @param {object} userData Dados do funcionário.
 * @param {string} ruleId ID da regra acionadora.
 * @param {string} ruleName Nome da regra acionadora.
 */
async function executeRuleAction(db, action, userId, userData, ruleId, ruleName) {
  const operation = "EXECUTE_RULE_ACTION";

  // Valida a estrutura da ação esperada
  if (action?.type !== 'createOccurrence' || !action.incidentTypeIdAction || !action.defaultStatus) {
     logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.ABORTED, { ruleId, userId, reason: "Ação inválida ou incompleta", actionData: action });
     return;
  }

  const incidentTypeId = action.incidentTypeIdAction;
  // Usa o status da regra, com fallback seguro para Pendente
  const status = Object.values(OCCURRENCE_STATUS).includes(action.defaultStatus) ? action.defaultStatus : OCCURRENCE_STATUS.PENDING;
  const notes = action.defaultNotes || `Gerado automaticamente: ${ruleName}`;

  logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED, { ruleId, userId, incidentTypeId, status });

  try {
    // Busca dados do tipo de incidente
    const incidentTypeData = await getIncidentTypeData(incidentTypeId, db);
    if (!incidentTypeData) {
      logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.FAILED, { ruleId, userId, incidentTypeId, reason: 'IncidentType não encontrado.' });
      return;
    }

    // Monta dados da nova ocorrência (verifique se os nomes dos campos estão corretos!)
    const newOccurrenceData = {
      userId: userId,
      employeeName: userData.displayName ?? null,
      department: userData.department ?? null,
      incidentTypeId: incidentTypeId,
      incidentTypeName: incidentTypeData.name ?? null,
      points: typeof incidentTypeData.points === 'number' ? incidentTypeData.points : 0, // Campo 'points'
      status: status, // Status da ação da regra
      notes: notes,
      createdAt: admin.firestore.FieldValue.serverTimestamp(), // Data de criação
      // Campos de rastreabilidade
      registeredBy: 'system/automatic',
      registeredByName: 'Sistema (Regra Automática)',
      createdByRuleId: ruleId, // ID da regra que gerou
      // Campos de aprovação (preenchidos se status for Approved)
      approvedRejectedBy: status === OCCURRENCE_STATUS.APPROVED ? 'system/automatic' : null,
      approvedRejectedByName: status === OCCURRENCE_STATUS.APPROVED ? 'Sistema (Regra Automática)' : null,
      approvedRejectedAt: status === OCCURRENCE_STATUS.APPROVED ? admin.firestore.FieldValue.serverTimestamp() : null,
      // Outros campos do seu modelo PointOccurrence se houver (ex: attachments)
      // attachments: [],
    };

    // Cria o documento
    const newDocRef = await db.collection(COLLECTIONS.POINT_OCCURRENCES).add(newOccurrenceData);
    logOperation(LOG_LEVELS.INFO, operation, 'OCCURRENCE_CREATED', {
        ruleId, userId, incidentTypeId, status, newOccurrenceId: newDocRef.id
    });

    // *** NENHUMA atualização de saldo aqui. O trigger onOccurrenceStatusChange cuidará disso. ***

    logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SUCCESS, { ruleId, userId, newOccurrenceId: newDocRef.id });

  } catch (error) {
    logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.FAILED, {
      ruleId, userId, incidentTypeId, status, error: error.message, stack: error.stack
    });
  }
}

// =================================================================
// FUNÇÕES EXPORTADAS PARA INDEX.JS (Funções Agendadas)
// =================================================================

/**
 * Função Agendada: Processa regras diárias (cron: todos os dias à meia-noite).
 * Esta função é exportada para index.js e chamada pelo Firebase Functions Scheduler.
 */
function processDailyRules(context) {
  const operation = "SCHEDULED_DAILY_RULES";
  logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED);
  
  try {
    // Usa o Firestore global do Admin SDK
    return evaluateRulesForFrequency(admin.firestore(), TRIGGER_FREQUENCY.DAILY);
  } catch (error) {
    logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.FAILED, {
      error: error.message,
      stack: error.stack
    });
    // Retorna Promise rejeitada (ou null) dependendo de como o Scheduler trata erros
    return null;
  }
}

/**
 * Função Agendada: Processa regras semanais (cron: toda segunda-feira à meia-noite).
 * Esta função é exportada para index.js e chamada pelo Firebase Functions Scheduler.
 */
function processWeeklyRules(context) {
  const operation = "SCHEDULED_WEEKLY_RULES";
  logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED);
  
  try {
    // Usa o Firestore global do Admin SDK
    return evaluateRulesForFrequency(admin.firestore(), TRIGGER_FREQUENCY.WEEKLY);
  } catch (error) {
    logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.FAILED, {
      error: error.message,
      stack: error.stack
    });
    return null;
  }
}

/**
 * Função Agendada: Processa regras mensais (cron: primeiro dia do mês à meia-noite).
 * Esta função é exportada para index.js e chamada pelo Firebase Functions Scheduler.
 */
function processMonthlyRules(context) {
  const operation = "SCHEDULED_MONTHLY_RULES";
  logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.STARTED);
  
  try {
    // Usa o Firestore global do Admin SDK
    return evaluateRulesForFrequency(admin.firestore(), TRIGGER_FREQUENCY.MONTHLY);
  } catch (error) {
    logOperation(LOG_LEVELS.ERROR, operation, OPERATION_STATUS.FAILED, {
      error: error.message,
      stack: error.stack
    });
    return null;
  }
}

/**
 * Função Trigger: Processa regras reativas quando uma nova ocorrência é criada.
 * @param {Object} snapshot O snapshot do documento criado em pointsOccurrences
 * @param {Object} context O contexto do trigger
 */
function processOnOccurrenceCreate(snapshot, context) {
  const operation = "TRIGGER_ON_OCCURRENCE_CREATE";
  
  // Essa função será implementada quando suporte ao TRIGGER_FREQUENCY.onOccurrenceCreate for adicionado.
  // Por enquanto, apenas loga que foi chamada para depuração.
  
  logOperation(LOG_LEVELS.INFO, operation, OPERATION_STATUS.SKIPPED, {
    occurrenceId: context.params.occurrenceId,
    reason: "Tipo de trigger não implementado ainda"
  });
  
  return null;
}

// =================================================================
// EXPORTS PARA INDEX.JS (Funções Agendadas)
// =================================================================
module.exports = {
  processDailyRules,
  processWeeklyRules,
  processMonthlyRules,
  processOnOccurrenceCreate,
};