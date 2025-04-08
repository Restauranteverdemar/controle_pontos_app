// functions/src/resetDiagnostics.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Não inicialize o Firestore no escopo global!
// Em vez disso, obtenha a referência ao Firestore dentro de cada função
const REGION = 'us-central1'; // Use a mesma região que suas outras funções

/**
 * Função para diagnosticar o estado atual do sistema de reset mensal
 * Verifica índices, estrutura de dados, logs e possíveis problemas
 */
exports.diagnoseMonthlyResetSystem = functions.region(REGION).https.onCall(async (data, context) => {
  // Verificar se o usuário é admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Apenas administradores podem executar esta função'
    );
  }
  
  // Obter referência ao Firestore dentro da função
  const db = admin.firestore();
  
  console.log('[Diagnóstico] Iniciando diagnóstico completo do sistema de reset mensal...');
  
  // Resultados do diagnóstico
  const results = {
    indices: {
      status: 'checking'
    },
    users: {
      total: 0,
      withZeroBalance: 0,
      withPositiveBalance: 0
    },
    occurrences: {
      total: 0,
      withPeriodId: 0,
      withoutPeriodId: 0,
      oldOccurrencesWithoutPeriodId: 0,
      periodsFound: {}
    },
    snapshots: {
      total: 0,
      periodsFound: {}
    },
    functionCode: {
      status: 'checking',
      resetMonthlyBalances: 'unknown',
      manualCall: 'unknown',
      scheduledCall: 'unknown'
    },
    recentLogs: [],
    potentialIssues: []
  };
  
  // 1. Verificar se o índice necessário existe
  try {
    console.log('[Diagnóstico] Verificando índices...');
    await db.collection('pointsOccurrences')
      .where('userId', '==', 'test-user')
      .where('periodId', '==', null)
      .limit(1)
      .get();
    
    results.indices.status = 'ok';
    console.log('[Diagnóstico] Índice userId+periodId está funcionando.');
  } catch (error) {
    results.indices.status = 'error';
    results.indices.error = error.message;
    results.potentialIssues.push('Índice (userId, periodId) está ausente ou não funcional');
    console.error('[Diagnóstico] Erro ao verificar índice:', error);
  }
  
  // 2. Analisar usuários
  console.log('[Diagnóstico] Analisando usuários...');
  const usersSnapshot = await db.collection('users').get();
  results.users.total = usersSnapshot.size;
  
  usersSnapshot.forEach(doc => {
    const userData = doc.data();
    const balance = userData.saldoPontosAprovados || 0;
    
    if (balance === 0) {
      results.users.withZeroBalance++;
    } else {
      results.users.withPositiveBalance++;
    }
  });
  
  // 3. Analisar ocorrências
  console.log('[Diagnóstico] Analisando ocorrências...');
  const allOccurrencesSnapshot = await db.collection('pointsOccurrences')
    .limit(10000) // Limite para evitar timeouts
    .get();
  
  results.occurrences.total = allOccurrencesSnapshot.size;
  
  // Pegar o primeiro dia do mês atual para comparar datas
  const now = new Date();
  const firstDayOfCurrentMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  
  allOccurrencesSnapshot.forEach(doc => {
    const data = doc.data();
    
    if (data.periodId) {
      results.occurrences.withPeriodId++;
      
      // Contar ocorrências por período
      if (!results.occurrences.periodsFound[data.periodId]) {
        results.occurrences.periodsFound[data.periodId] = 0;
      }
      results.occurrences.periodsFound[data.periodId]++;
    } else {
      results.occurrences.withoutPeriodId++;
      
      // Verificar se há ocorrências antigas sem periodId
      if (data.registeredAt && data.registeredAt.toDate) {
        const registeredDate = data.registeredAt.toDate();
        
        if (registeredDate < firstDayOfCurrentMonth) {
          results.occurrences.oldOccurrencesWithoutPeriodId++;
          
          if (!results.potentialIssues.includes('Existem ocorrências antigas sem periodId')) {
            results.potentialIssues.push('Existem ocorrências antigas sem periodId');
          }
        }
      }
    }
  });
  
  // 4. Analisar snapshots de saldo
  console.log('[Diagnóstico] Analisando snapshots de saldo...');
  const snapshotsSnapshot = await db.collection('userBalanceSnapshots').get();
  results.snapshots.total = snapshotsSnapshot.size;
  
  snapshotsSnapshot.forEach(doc => {
    const data = doc.data();
    
    if (data.periodId) {
      if (!results.snapshots.periodsFound[data.periodId]) {
        results.snapshots.periodsFound[data.periodId] = 0;
      }
      results.snapshots.periodsFound[data.periodId]++;
    }
  });
  
  // 5. Verificar logs recentes (se possível)
  try {
    console.log('[Diagnóstico] Tentando buscar logs administrativos recentes...');
    const logsSnapshot = await db.collection('adminLogs')
      .orderBy('timestamp', 'desc')
      .limit(5)
      .get();
    
    logsSnapshot.forEach(doc => {
      results.recentLogs.push({
        id: doc.id,
        ...doc.data()
      });
    });
  } catch (error) {
    console.log('[Diagnóstico] Não foi possível buscar logs administrativos:', error.message);
  }
  
  // 6. Identificar inconsistências específicas
  if (results.occurrences.withPeriodId === 0 && results.snapshots.total > 0) {
    results.potentialIssues.push('Existem snapshots, mas nenhuma ocorrência está marcada com periodId');
  }
  
  if (results.occurrences.oldOccurrencesWithoutPeriodId > 0 && results.snapshots.total > 0) {
    results.potentialIssues.push('Há inconsistência: ocorrências antigas não marcadas, mas snapshots existem');
  }
  
  if (results.snapshots.total === 0) {
    results.potentialIssues.push('Nenhum snapshot encontrado - o reset mensal nunca foi executado com sucesso');
  }
  
  console.log('[Diagnóstico] Diagnóstico concluído:', results);
  
  return {
    ...results,
    recommendedActions: [
      'Execute a função fixAllOccurrences para corrigir ocorrências antigas não marcadas',
      'Verifique a implementação do scheduledMonthlyBalanceReset e resetMonthlyBalanceManual no index.js',
      'Atualize o módulo monthlyReset.js se necessário'
    ]
  };
});

/**
 * Função auxiliar para determinar o periodId com base em uma data
 * @param {Date} date - Data da ocorrência
 * @returns {string} - periodId no formato YYYY-MM
 */
function getRelevantPeriodId(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

/**
 * Função para corrigir todas as ocorrências sem periodId
 */
exports.fixAllOccurrences = functions.region(REGION).https.onCall(async (data, context) => {
  // Verificar se o usuário é admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Apenas administradores podem executar esta função'
    );
  }
  
  // Obter referência ao Firestore dentro da função
  const db = admin.firestore();
  
  const { dryRun = true } = data;
  
  console.log(`[Correção] Iniciando correção de ocorrências. Modo simulação: ${dryRun ? 'SIM' : 'NÃO'}`);
  
  // Buscar todas as ocorrências sem periodId
  const occurrencesSnapshot = await db.collection('pointsOccurrences')
    .where('periodId', '==', null)
    .get();
  
  console.log(`[Correção] Encontradas ${occurrencesSnapshot.size} ocorrências sem periodId`);
  
  // Agrupar ocorrências por mês/ano
  const occurrencesByPeriod = {};
  const now = new Date();
  const currentPeriodId = getRelevantPeriodId(now);
  
  let totalToUpdate = 0;
  let totalSkipped = 0;
  
  occurrencesSnapshot.forEach(doc => {
    const data = doc.data();
    
    if (data.registeredAt && data.registeredAt.toDate) {
      const date = data.registeredAt.toDate();
      const periodId = getRelevantPeriodId(date);
      
      // Não atualizar ocorrências do mês atual
      if (periodId === currentPeriodId) {
        totalSkipped++;
        return;
      }
      
      if (!occurrencesByPeriod[periodId]) {
        occurrencesByPeriod[periodId] = [];
      }
      
      occurrencesByPeriod[periodId].push({
        id: doc.id,
        date: date
      });
      
      totalToUpdate++;
    }
  });
  
  console.log(`[Correção] Ocorrências a atualizar: ${totalToUpdate}, a ignorar (mês atual): ${totalSkipped}`);
  console.log(`[Correção] Períodos encontrados: ${Object.keys(occurrencesByPeriod).join(', ')}`);
  
  const results = {
    simulation: dryRun,
    totalToUpdate,
    totalSkipped,
    periodsFound: Object.keys(occurrencesByPeriod),
    updatedByPeriod: {},
    totalUpdated: 0,
    errors: []
  };
  
  // Se não for modo simulação, atualizar as ocorrências
  if (!dryRun) {
    for (const periodId in occurrencesByPeriod) {
      const occurrences = occurrencesByPeriod[periodId];
      console.log(`[Correção] Atualizando ${occurrences.length} ocorrências do período ${periodId}...`);
      
      results.updatedByPeriod[periodId] = 0;
      
      // Processar em lotes de 450 para não estourar limite do Firestore
      const batchSize = 450; // Margem de segurança
      let processedCount = 0;
      
      while (processedCount < occurrences.length) {
        const batch = db.batch();
        const currentBatch = occurrences.slice(processedCount, processedCount + batchSize);
        
        currentBatch.forEach(occurrence => {
          const ref = db.collection('pointsOccurrences').doc(occurrence.id);
          batch.update(ref, { periodId: periodId });
        });
        
        try {
          await batch.commit();
          results.updatedByPeriod[periodId] += currentBatch.length;
          results.totalUpdated += currentBatch.length;
          console.log(`[Correção] Lote de ${currentBatch.length} ocorrências do período ${periodId} atualizado com sucesso.`);
        } catch (error) {
          console.error(`[Correção] Erro ao atualizar lote do período ${periodId}:`, error);
          results.errors.push({
            periodId,
            message: error.message,
            batchStart: processedCount,
            batchSize: currentBatch.length
          });
        }
        
        processedCount += batchSize;
      }
    }
  }
  
  console.log('[Correção] Processo concluído:', results);
  
  return results;
});

/**
 * Função para testar a implementação atual do monthlyReset
 * Executa um reset em um único usuário para validar a lógica
 */
exports.testSingleUserReset = functions.region(REGION).https.onCall(async (data, context) => {
  // Verificar se o usuário é admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Apenas administradores podem executar esta função'
    );
  }
  
  // Obter referência ao Firestore dentro da função
  const db = admin.firestore();
  
  const { userId, dryRun = true, testPeriodPrefix = 'TEST' } = data;
  
  if (!userId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'É necessário fornecer um userId para testar'
    );
  }
  
  console.log(`[Teste] Testando reset para o usuário ${userId}. Modo simulação: ${dryRun ? 'SIM' : 'NÃO'}`);
  
  // Verificar se o usuário existe
  const userDoc = await db.collection('users').doc(userId).get();
  
  if (!userDoc.exists) {
    throw new functions.https.HttpsError(
      'not-found',
      `Usuário ${userId} não encontrado`
    );
  }
  
  const userData = userDoc.data();
  const currentBalance = userData.saldoPontosAprovados || 0;
  
  // Determinar o período a fechar (mês atual para teste)
  const now = new Date();
  const testPeriodId = `${testPeriodPrefix}-${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  
  console.log(`[Teste] Período de teste: ${testPeriodId}`);
  console.log(`[Teste] Saldo atual do usuário: ${currentBalance}`);
  
  // Buscar ocorrências do usuário sem periodId
  const occurrencesSnapshot = await db.collection('pointsOccurrences')
    .where('userId', '==', userId)
    .where('periodId', '==', null)
    .get();
  
  console.log(`[Teste] Encontradas ${occurrencesSnapshot.size} ocorrências sem periodId para o usuário ${userId}`);
  
  const results = {
    userId,
    testPeriodId,
    currentBalance,
    occurrencesFound: occurrencesSnapshot.size,
    dryRun,
    success: true,
    details: {}
  };
  
  // Se não for modo simulação, executar o reset para o usuário de teste
  if (!dryRun) {
    try {
      // 1. Criar batch para snapshot e reset de saldo
      const firstBatch = db.batch();
      
      // 2. Criar snapshot do saldo
      const snapshotRef = db.collection('userBalanceSnapshots').doc();
      firstBatch.set(snapshotRef, {
        userId,
        periodId: testPeriodId,
        finalBalance: currentBalance,
        resetTimestamp: admin.firestore.FieldValue.serverTimestamp()
      });
      
      // 3. Zerar saldo do usuário
      const userRef = db.collection('users').doc(userId);
      firstBatch.update(userRef, { 
        saldoPontosAprovados: 0,
        lastUpdated: admin.firestore.FieldValue.serverTimestamp()
      });
      
      // Executar primeiro batch
      await firstBatch.commit();
      console.log(`[Teste] Snapshot criado e saldo resetado para o usuário ${userId}`);
      
      // 4. Processar ocorrências em lotes pequenos (max 450 por batch)
      const occurrenceDocs = occurrencesSnapshot.docs;
      const batchSize = 450;
      let markedCount = 0;
      
      for (let i = 0; i < occurrenceDocs.length; i += batchSize) {
        const currentBatch = db.batch();
        const currentOccurrences = occurrenceDocs.slice(i, i + batchSize);
        
        console.log(`[Teste] Processando lote de ${currentOccurrences.length} ocorrências...`);
        
        currentOccurrences.forEach(doc => {
          currentBatch.update(doc.ref, { periodId: testPeriodId });
        });
        
        await currentBatch.commit();
        markedCount += currentOccurrences.length;
      }
      
      results.details = {
        snapshotCreated: true,
        occurrencesMarked: markedCount,
        balanceReset: true
      };
      
      console.log(`[Teste] Reset de teste concluído com sucesso para o usuário ${userId}`);
    } catch (error) {
      results.success = false;
      results.error = error.message;
      console.error(`[Teste] Erro ao executar reset de teste para o usuário ${userId}:`, error);
    }
  }
  
  return results;
});

/**
 * Função para verificar se o módulo monthlyReset.js está corretamente implementado
 * e sendo chamado com os parâmetros corretos
 */
exports.validateMonthlyResetImplementation = functions.region(REGION).https.onCall(async (data, context) => {
  // Verificar se o usuário é admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Apenas administradores podem executar esta função'
    );
  }
  
  const results = {
    moduleCheck: {
      status: 'checking'
    },
    implementation: {
      status: 'checking'
    },
    recommendation: ''
  };
  
  // Verificar se o módulo monthlyReset pode ser importado
  try {
    const monthlyReset = require('./monthlyReset');
    
    results.moduleCheck.status = 'success';
    results.moduleCheck.functions = Object.keys(monthlyReset);
    
    if (typeof monthlyReset.resetMonthlyBalances !== 'function') {
      results.moduleCheck.status = 'error';
      results.moduleCheck.error = 'A função resetMonthlyBalances não existe no módulo';
      results.recommendation = 'Verifique se o arquivo monthlyReset.js está correto e contém a função resetMonthlyBalances';
      return results;
    }
    
    // Analisar o código da função resetMonthlyBalances
    const functionCode = monthlyReset.resetMonthlyBalances.toString();
    
    // Verificar se a função espera admin e db como parâmetros
    if (functionCode.includes('function resetMonthlyBalances(admin, db)') || 
        functionCode.includes('resetMonthlyBalances = async (admin, db)')) {
      results.implementation.status = 'success';
      results.implementation.expectsParams = ['admin', 'db'];
      
      // Verificar parte crítica da implementação - a atualização das ocorrências
      if (functionCode.includes('.update(doc.ref, { periodId:') || 
          functionCode.includes('batch.update(occurrenceRef, { periodId:')) {
        results.implementation.occurrenceUpdateFound = true;
      } else {
        results.implementation.occurrenceUpdateFound = false;
        results.recommendation = 'O código não parece atualizar corretamente o periodId nas ocorrências';
      }
      
    } else {
      results.implementation.status = 'warning';
      results.implementation.paramWarning = 'A função pode não estar esperando admin e db como parâmetros';
      results.recommendation = 'Verifique se a função resetMonthlyBalances recebe e utiliza corretamente os parâmetros admin e db';
    }
    
  } catch (error) {
    results.moduleCheck.status = 'error';
    results.moduleCheck.error = error.message;
    results.recommendation = 'Não foi possível carregar o módulo monthlyReset. Verifique se o arquivo existe e está acessível.';
  }
  
  return results;
});

/**
 * Função para criar snapshots retroativos para períodos marcados
 * mas que não têm snapshots correspondentes
 */
exports.createMissingSnapshots = functions.region(REGION).https.onCall(async (data, context) => {
  // Verificar se o usuário é admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Apenas administradores podem executar esta função'
    );
  }
  
  // Obter referência ao Firestore dentro da função
  const db = admin.firestore();
  
  const { dryRun = true } = data;
  
  console.log(`[Snapshots] Iniciando criação de snapshots retroativos. Modo simulação: ${dryRun ? 'SIM' : 'NÃO'}`);
  
  // Buscar todos os períodos existentes nas ocorrências
  const periodsSnapshot = await db.collection('pointsOccurrences')
    .where('periodId', '!=', null)
    .get();
  
  // Registrar períodos únicos
  const periodsMap = {};
  periodsSnapshot.forEach(doc => {
    const data = doc.data();
    if (data.periodId && !data.periodId.startsWith('TEST')) {
      periodsMap[data.periodId] = true;
    }
  });
  
  const periods = Object.keys(periodsMap).sort();
  
  console.log(`[Snapshots] Períodos encontrados: ${periods.join(', ')}`);
  
  // Buscar snapshots existentes para não duplicar
  const existingSnapshotsSnapshot = await db.collection('userBalanceSnapshots').get();
  const existingSnapshots = {};
  
  existingSnapshotsSnapshot.forEach(doc => {
    const data = doc.data();
    const key = `${data.userId}_${data.periodId}`;
    existingSnapshots[key] = true;
  });
  
  console.log(`[Snapshots] ${Object.keys(existingSnapshots).length} snapshots existentes encontrados`);
  
  // Resultados
  const results = {
    periodsFound: periods,
    dryRun,
    snapshotsToCreate: 0,
    snapshotsCreated: 0,
    errors: []
  };
  
  // Para cada período, criar snapshots para usuários
  if (periods.length > 0 && !dryRun) {
    // Buscar todos os usuários
    const usersSnapshot = await db.collection('users').get();
    const users = usersSnapshot.docs.map(doc => ({ 
      id: doc.id, 
      data: doc.data() 
    }));
    
    console.log(`[Snapshots] Processando snapshots para ${users.length} usuários`);
    
    for (const period of periods) {
      for (const user of users) {
        const key = `${user.id}_${period}`;
        
        // Pular se já existe
        if (existingSnapshots[key]) {
          continue;
        }
        
        results.snapshotsToCreate++;
        
        try {
          // Criar snapshot com saldo igual a 0 (melhor aproximação)
          await db.collection('userBalanceSnapshots').add({
            userId: user.id,
            periodId: period,
            finalBalance: 0, // Não temos como saber o saldo histórico
            resetTimestamp: admin.firestore.Timestamp.fromDate(new Date()),
            isRetroactive: true // Marcar como retroativo para identificação
          });
          
          results.snapshotsCreated++;
        } catch (error) {
          console.error(`[Snapshots] Erro ao criar snapshot para ${user.id} no período ${period}:`, error);
          results.errors.push({
            userId: user.id,
            periodId: period,
            error: error.message
          });
        }
      }
    }
  }
  
  console.log(`[Snapshots] Processo concluído. ${results.snapshotsCreated} snapshots criados.`);
  
  return results;
});

/**
 * Instruções para corrigir o sistema de reset mensal
 */
exports.getFixInstructions = functions.region(REGION).https.onCall(async (data, context) => {
  // Verificar se o usuário é admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Apenas administradores podem executar esta função'
    );
  }
  
  return {
    instructions: `
# Instruções para Corrigir o Sistema de Reset Mensal

## 1. Verificação do Problema

O problema identificado é que as ocorrências não estão sendo marcadas com o periodId quando o reset mensal é executado, embora o saldo seja zerado e os snapshots sejam criados.

A causa mais provável é o limite do Firestore de 500 operações por batch, que pode estar sendo excedido quando há muitas ocorrências para marcar.

## 2. Correção do Código em monthlyReset.js

Substitua o arquivo monthlyReset.js pelo novo código que:
- Separa as operações em múltiplos batches
- Processa as ocorrências em lotes menores (450 por batch)
- Adiciona logs detalhados para cada etapa

## 3. Verificando Logs

Após fazer as correções no código:

1. Execute a função \`validateMonthlyResetImplementation\` para verificar se o módulo está correto
2. Execute a função \`testSingleUserReset\` com um usuário específico para testar se a lógica funciona
3. Execute a função \`resetMonthlyBalanceManual\` para executar o reset completo
4. Verifique os logs no Firebase Console para confirmar que tudo está funcionando

## 4. Corrigindo Dados Históricos

Se você já executou resets e as ocorrências não foram marcadas corretamente:

1. Execute a função \`diagnoseMonthlyResetSystem\` para avaliar o estado atual
2. Execute a função \`fixAllOccurrences\` com \`dryRun=true\` para simular a correção
3. Se os resultados parecerem corretos, execute novamente com \`dryRun=false\` para aplicar as correções

## 5. Monitorando o Próximo Reset Automático

Após aplicar as correções:

1. Monitore cuidadosamente os logs da próxima execução automática
2. Verifique se as ocorrências estão sendo marcadas corretamente
3. Confirme que os snapshots de saldo estão sendo criados
4. Verifique se os saldos dos usuários estão sendo zerados
    `
  };
});