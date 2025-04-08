// debugMonthlyReset.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Função para executar um teste detalhado do reset
exports.debugMonthlyReset = functions.https.onCall(async (data, context) => {
  // Verificar se o usuário é admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Apenas administradores podem executar esta função'
    );
  }
  
  // Obter referência ao Firestore dentro da função
  const db = admin.firestore();
  
  // Parâmetros da chamada
  const { userId, forceMode = false } = data;
  
  if (!userId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'É necessário fornecer um userId para testar'
    );
  }
  
  // Dados da execução para rastreamento
  const executionId = Date.now().toString();
  console.log(`[DebugReset][${executionId}] Iniciando debug do reset para usuário ${userId}`);
  
  // 1. Verificar o usuário
  const userDoc = await db.collection('users').doc(userId).get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError(
      'not-found',
      `Usuário ${userId} não encontrado`
    );
  }
  
  const userData = userDoc.data();
  const currentBalance = userData.saldoPontosAprovados || 0;
  
  console.log(`[DebugReset][${executionId}] Usuário ${userId} tem saldo ${currentBalance}`);
  
  // 2. Verificar ocorrências do usuário
  const allOccurrencesSnapshot = await db.collection('pointsOccurrences')
    .where('userId', '==', userId)
    .get();
  
  console.log(`[DebugReset][${executionId}] Total de ocorrências do usuário: ${allOccurrencesSnapshot.size}`);
  
  // Contar ocorrências com e sem periodId
  let withPeriodId = 0;
  let withoutPeriodId = 0;
  const periodCounts = {};
  
  allOccurrencesSnapshot.forEach(doc => {
    const data = doc.data();
    if (data.periodId) {
      withPeriodId++;
      periodCounts[data.periodId] = (periodCounts[data.periodId] || 0) + 1;
    } else {
      withoutPeriodId++;
    }
  });
  
  console.log(`[DebugReset][${executionId}] Ocorrências com periodId: ${withPeriodId}`);
  console.log(`[DebugReset][${executionId}] Ocorrências sem periodId: ${withoutPeriodId}`);
  
  if (Object.keys(periodCounts).length > 0) {
    console.log(`[DebugReset][${executionId}] Distribuição por período:`, periodCounts);
  }
  
  // 3. Verificar o funcionamento correto do batch
  if (withoutPeriodId > 0) {
    console.log(`[DebugReset][${executionId}] Testando atualização de ocorrências em lotes`);
    
    // Determinar período de teste
    const testPeriodId = `TEST-${executionId.substring(0, 6)}`;
    
    // Buscar apenas ocorrências sem periodId
    const occurrencesToUpdate = await db.collection('pointsOccurrences')
      .where('userId', '==', userId)
      .where('periodId', '==', null)
      .get();
    
    console.log(`[DebugReset][${executionId}] Encontradas ${occurrencesToUpdate.size} ocorrências para atualizar`);
    
    // Atualizar em lotes
    const batchSize = 450;
    let successCount = 0;
    let errorCount = 0;
    let processedCount = 0;
    
    // Somente executa a atualização se forceMode for true
    if (forceMode) {
      const occurrenceDocs = occurrencesToUpdate.docs;
      
      for (let i = 0; i < occurrenceDocs.length; i += batchSize) {
        try {
          const batch = db.batch();
          const currentBatch = occurrenceDocs.slice(i, i + batchSize);
          
          console.log(`[DebugReset][${executionId}] Processando lote ${Math.floor(i/batchSize) + 1} com ${currentBatch.length} ocorrências`);
          
          // Adicionar cada ocorrência ao batch
          currentBatch.forEach(doc => {
            batch.update(doc.ref, { periodId: testPeriodId });
          });
          
          // Executar o batch
          await batch.commit();
          successCount += currentBatch.length;
          
          console.log(`[DebugReset][${executionId}] Lote processado com sucesso`);
        } catch (error) {
          console.error(`[DebugReset][${executionId}] Erro ao processar lote:`, error);
          errorCount += batchSize;
        }
        
        processedCount += Math.min(batchSize, occurrenceDocs.length - i);
      }
      
      console.log(`[DebugReset][${executionId}] Resumo: ${successCount} atualizadas com sucesso, ${errorCount} com erro`);
      
      // Verificar se as atualizações funcionaram
      const verifySnapshot = await db.collection('pointsOccurrences')
        .where('userId', '==', userId)
        .where('periodId', '==', testPeriodId)
        .get();
      
      console.log(`[DebugReset][${executionId}] Verificação: ${verifySnapshot.size} ocorrências com novo periodId`);
      
      // Se a verificação falhar, algo está muito errado
      if (verifySnapshot.size === 0 && successCount > 0) {
        console.error(`[DebugReset][${executionId}] ERRO CRÍTICO: As ocorrências não foram atualizadas corretamente!`);
      }
    }
  }
  
  // 4. Verificar código do monthlyReset.js
  let resetModuleAnalysis = "Módulo monthlyReset não pôde ser analisado";
  try {
    const monthlyReset = require('./monthlyReset');
    
    if (typeof monthlyReset.resetMonthlyBalances === 'function') {
      const funcCode = monthlyReset.resetMonthlyBalances.toString();
      
      // Analisar o código para identificar potenciais problemas
      const hasBatchProcessing = funcCode.includes('for (let i = 0; i < occurrenceDocs.length; i += batchSize)');
      const hasMultipleBatches = funcCode.includes('currentBatch =') || funcCode.includes('const currentBatch =');
      const hasPeriodIdUpdate = funcCode.includes('update(') && funcCode.includes('periodId:');
      
      resetModuleAnalysis = {
        hasFunction: true,
        hasBatchProcessing,
        hasMultipleBatches,
        hasPeriodIdUpdate
      };
    } else {
      resetModuleAnalysis = "A função resetMonthlyBalances não existe no módulo";
    }
  } catch (error) {
    resetModuleAnalysis = `Erro ao analisar módulo: ${error.message}`;
  }
  
  // 5. Verificar índices do Firestore
  let indexStatus = "Não verificado";
  try {
    await db.collection('pointsOccurrences')
      .where('userId', '==', userId)
      .where('periodId', '==', null)
      .limit(1)
      .get();
    
    indexStatus = "OK - Índice (userId, periodId) funcionando corretamente";
  } catch (error) {
    indexStatus = `ERRO - ${error.message}`;
  }
  
  // Retornar resultados completos
  return {
    executionId,
    user: {
      id: userId,
      currentBalance
    },
    occurrences: {
      total: allOccurrencesSnapshot.size,
      withPeriodId,
      withoutPeriodId,
      periodDistribution: periodCounts
    },
    batchTest: forceMode ? {
      processed: processedCount,
      success: successCount,
      errors: errorCount
    } : "Não executado (defina forceMode=true para testar)",
    firestore: {
      index: indexStatus
    },
    moduleAnalysis: resetModuleAnalysis,
    recommendations: [
      withoutPeriodId > 0 ? "Execute fixAllOccurrences para corrigir as ocorrências antigas" : "Todas as ocorrências já estão marcadas com periodId",
      "Verifique a consulta no dashboard do funcionário para garantir que está filtrando por periodId == null"
    ]
  };
});

// Função para verificar se o dashboard está filtrando corretamente
exports.checkEmployeeDashboardQuery = functions.https.onCall(async (data, context) => {
  // Verificar autenticação (pode ser admin ou funcionário)
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Usuário não autenticado'
    );
  }
  
  // Obter referência ao Firestore
  const db = admin.firestore();
  
  // Pegar o userId da chamada ou do contexto de autenticação
  const userId = data.userId || context.auth.uid;
  
  console.log(`[CheckDashboard] Verificando queries para o usuário ${userId}`);
  
  // 1. Verificar total de ocorrências
  const allOccurrencesSnapshot = await db.collection('pointsOccurrences')
    .where('userId', '==', userId)
    .get();
  
  const totalOccurrences = allOccurrencesSnapshot.size;
  
  // 2. Verificar ocorrências atuais (periodId == null)
  const currentOccurrencesSnapshot = await db.collection('pointsOccurrences')
    .where('userId', '==', userId)
    .where('periodId', '==', null)
    .get();
  
  const currentOccurrences = currentOccurrencesSnapshot.size;
  
  // 3. Verificar ocorrências arquivadas (periodId != null)
  const archivedOccurrencesSnapshot = await db.collection('pointsOccurrences')
    .where('userId', '==', userId)
    .where('periodId', '!=', null)
    .get();
  
  const archivedOccurrences = archivedOccurrencesSnapshot.size;
  
  // Verificar se os números batem
  const numbersMatch = totalOccurrences === (currentOccurrences + archivedOccurrences);
  
  // Retornar resultados
  return {
    userId,
    totalOccurrences,
    currentOccurrences,
    archivedOccurrences,
    numbersMatch,
    dashboardShouldShow: currentOccurrences,
    recommendation: currentOccurrences === 0 ? 
      "O dashboard deve mostrar uma mensagem de 'Nenhuma ocorrência no período atual'" :
      `O dashboard deve mostrar ${currentOccurrences} ocorrências`,
    queryExample: `
// Query correta para o dashboard:
FirebaseFirestore.instance
    .collection('pointsOccurrences')
    .where('userId', '==', '$userId')
    .where('periodId', '==', null)
    .orderBy('registeredAt', descending: true)
    .get()
    `
  };
});

// Adicione esta função ao seu index.js:
// exports.debugMonthlyReset = require('./debugMonthlyReset').debugMonthlyReset;
// exports.checkEmployeeDashboardQuery = require('./debugMonthlyReset').checkEmployeeDashboardQuery;