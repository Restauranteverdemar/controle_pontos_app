// forceUpdatePeriodIds.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

/**
 * Função para forçar a atualização de periodId em todas as ocorrências
 * Esta é uma função "de emergência" para corrigir ocorrências que não
 * foram marcadas corretamente durante o reset mensal
 */
exports.forceUpdatePeriodIds = functions.https.onCall(async (data, context) => {
  // Verificar se o usuário é admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Apenas administradores podem executar esta função'
    );
  }
  
  // Obter referência ao Firestore
  const db = admin.firestore();
  
  const { specificMonth, dryRun = true } = data;
  
  console.log(`[ForceUpdate] Iniciando atualização forçada de periodIds. Modo simulação: ${dryRun ? 'SIM' : 'NÃO'}`);
  
  // Determinar o mês atual
  const now = new Date();
  const currentYear = now.getFullYear();
  const currentMonth = now.getMonth() + 1;
  const currentPeriodId = `${currentYear}-${String(currentMonth).padStart(2, '0')}`;
  
  // Se specificMonth for fornecido (formato YYYY-MM), usamos ele
  // Caso contrário, todas as ocorrências que não sejam do mês atual serão marcadas com
  // um periodId baseado na sua data de registro
  const targetMonth = specificMonth;
  
  console.log(`[ForceUpdate] Mês atual: ${currentPeriodId}`);
  if (targetMonth) {
    console.log(`[ForceUpdate] Processando apenas ocorrências do mês: ${targetMonth}`);
  } else {
    console.log(`[ForceUpdate] Processando todas as ocorrências que não são do mês atual`);
  }
  
  // Buscar todas as ocorrências sem periodId
  let queryRef = db.collection('pointsOccurrences')
    .where('periodId', '==', null);
  
  // Se um mês específico for fornecido, adicionar filtro de data
  if (targetMonth) {
    const [year, month] = targetMonth.split('-').map(n => parseInt(n));
    
    const startDate = new Date(year, month - 1, 1);
    const endDate = new Date(year, month, 0); // Último dia do mês
    endDate.setHours(23, 59, 59, 999);
    
    console.log(`[ForceUpdate] Filtrando entre ${startDate.toISOString()} e ${endDate.toISOString()}`);
    
    // Adicionar filtro de data
    queryRef = queryRef
      .where('registeredAt', '>=', admin.firestore.Timestamp.fromDate(startDate))
      .where('registeredAt', '<=', admin.firestore.Timestamp.fromDate(endDate));
  }
  
  const occurrencesSnapshot = await queryRef.get();
  
  console.log(`[ForceUpdate] Encontradas ${occurrencesSnapshot.size} ocorrências sem periodId`);
  
  // Agrupar ocorrências por mês
  const occurrencesByMonth = {};
  let totalToUpdate = 0;
  let totalSkipped = 0;
  
  occurrencesSnapshot.forEach(doc => {
    const data = doc.data();
    
    // Se não tiver registeredAt, não podemos processar
    if (!data.registeredAt || !data.registeredAt.toDate) {
      console.log(`[ForceUpdate] Ocorrência ${doc.id} não tem data de registro válida`);
      return;
    }
    
    const registeredDate = data.registeredAt.toDate();
    const year = registeredDate.getFullYear();
    const month = String(registeredDate.getMonth() + 1).padStart(2, '0');
    const periodId = `${year}-${month}`;
    
    // Se for do mês atual, pular
    if (periodId === currentPeriodId) {
      totalSkipped++;
      return;
    }
    
    // Se for de um mês específico e não corresponder, pular
    if (targetMonth && periodId !== targetMonth) {
      totalSkipped++;
      return;
    }
    
    // Adicionar à lista do mês correspondente
    if (!occurrencesByMonth[periodId]) {
      occurrencesByMonth[periodId] = [];
    }
    
    occurrencesByMonth[periodId].push({
      id: doc.id,
      date: registeredDate
    });
    
    totalToUpdate++;
  });
  
  console.log(`[ForceUpdate] Ocorrências a atualizar: ${totalToUpdate}, ignoradas: ${totalSkipped}`);
  console.log(`[ForceUpdate] Períodos encontrados: ${Object.keys(occurrencesByMonth).join(', ')}`);
  
  const results = {
    dryRun,
    periodsFound: Object.keys(occurrencesByMonth),
    totalToUpdate,
    totalSkipped,
    updatedByPeriod: {},
    totalUpdated: 0,
    errors: []
  };
  
  // Se não for simulação, atualizar as ocorrências
  if (!dryRun && totalToUpdate > 0) {
    for (const periodId in occurrencesByMonth) {
      const occurrences = occurrencesByMonth[periodId];
      console.log(`[ForceUpdate] Atualizando ${occurrences.length} ocorrências do período ${periodId}`);
      
      results.updatedByPeriod[periodId] = 0;
      
      // Processar em lotes para evitar limite do Firestore (500 operações por batch)
      const batchSize = 450; // Tamanho seguro
      
      for (let i = 0; i < occurrences.length; i += batchSize) {
        const batch = db.batch();
        const currentBatch = occurrences.slice(i, i + batchSize);
        
        console.log(`[ForceUpdate] Processando lote ${Math.floor(i/batchSize) + 1} com ${currentBatch.length} ocorrências`);
        
        // Adicionar atualizações ao batch
        currentBatch.forEach(occurrence => {
          const ref = db.collection('pointsOccurrences').doc(occurrence.id);
          batch.update(ref, { periodId: periodId });
        });
        
        try {
          // Executar o batch
          await batch.commit();
          results.updatedByPeriod[periodId] += currentBatch.length;
          results.totalUpdated += currentBatch.length;
          console.log(`[ForceUpdate] Lote processado com sucesso`);
        } catch (error) {
          console.error(`[ForceUpdate] Erro ao processar lote:`, error);
          results.errors.push({
            periodId,
            batchIndex: Math.floor(i/batchSize),
            error: error.message
          });
        }
      }
    }
    
    console.log(`[ForceUpdate] Total de ${results.totalUpdated} ocorrências atualizadas com sucesso`);
    
    if (results.errors.length > 0) {
      console.error(`[ForceUpdate] Ocorreram ${results.errors.length} erros durante o processo`);
    }
  }
  
  return results;
});

/**
 * Função para forçar a criação de snapshots faltantes
 * Esta função cria snapshots para usuários se não existirem para um período
 */
exports.forceCreateMissingSnapshots = functions.https.onCall(async (data, context) => {
  // Verificar se o usuário é admin
  if (!context.auth || !context.auth.token.admin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Apenas administradores podem executar esta função'
    );
  }
  
  // Obter referência ao Firestore
  const db = admin.firestore();
  
  const { targetPeriodId, dryRun = true } = data;
  
  if (!targetPeriodId || !targetPeriodId.match(/^\d{4}-\d{2}$/)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'targetPeriodId deve estar no formato YYYY-MM'
    );
  }
  
  console.log(`[ForceSnapshots] Iniciando criação de snapshots para o período ${targetPeriodId}. Modo simulação: ${dryRun ? 'SIM' : 'NÃO'}`);
  
  // 1. Verificar se existem ocorrências para este período
  const occurrencesSnapshot = await db.collection('pointsOccurrences')
    .where('periodId', '==', targetPeriodId)
    .get();
  
  if (occurrencesSnapshot.empty) {
    console.log(`[ForceSnapshots] Nenhuma ocorrência encontrada para o período ${targetPeriodId}`);
    return {
      success: false,
      error: "Não há ocorrências marcadas com este periodId. Não faz sentido criar snapshots."
    };
  }
  
  // Extrair usuários únicos das ocorrências
  const usersWithOccurrences = new Set();
  occurrencesSnapshot.forEach(doc => {
    const data = doc.data();
    if (data.userId) {
      usersWithOccurrences.add(data.userId);
    }
  });
  
  const userIds = Array.from(usersWithOccurrences);
  console.log(`[ForceSnapshots] Encontrados ${userIds.length} usuários com ocorrências neste período`);
  
  // 2. Buscar snapshots existentes para este período
  const snapshotsSnapshot = await db.collection('userBalanceSnapshots')
    .where('periodId', '==', targetPeriodId)
    .get();
  
  const usersWithSnapshots = new Set();
  snapshotsSnapshot.forEach(doc => {
    const data = doc.data();
    if (data.userId) {
      usersWithSnapshots.add(data.userId);
    }
  });
  
  console.log(`[ForceSnapshots] Já existem ${usersWithSnapshots.size} snapshots para este período`);
  
  // 3. Determinar quais usuários precisam de snapshots
  const usersNeedingSnapshots = userIds.filter(userId => !usersWithSnapshots.has(userId));
  
  console.log(`[ForceSnapshots] ${usersNeedingSnapshots.length} usuários precisam de snapshots`);
  
  const results = {
    periodId: targetPeriodId,
    dryRun,
    totalUsersWithOccurrences: userIds.length,
    totalExistingSnapshots: usersWithSnapshots.size,
    usersNeedingSnapshots: usersNeedingSnapshots.length,
    snapshotsCreated: 0,
    errors: []
  };
  
  // 4. Criar snapshots faltantes
  if (!dryRun && usersNeedingSnapshots.length > 0) {
    for (const userId of usersNeedingSnapshots) {
      try {
        await db.collection('userBalanceSnapshots').add({
          userId,
          periodId: targetPeriodId,
          finalBalance: 0, // Valor aproximado
          resetTimestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRetroactive: true // Marcar como retroativo
        });
        
        results.snapshotsCreated++;
        console.log(`[ForceSnapshots] Criado snapshot para o usuário ${userId}`);
      } catch (error) {
        console.error(`[ForceSnapshots] Erro ao criar snapshot para o usuário ${userId}:`, error);
        results.errors.push({
          userId,
          error: error.message
        });
      }
    }
    
    console.log(`[ForceSnapshots] Criados ${results.snapshotsCreated} snapshots com sucesso`);
  }
  
  return results;
});

// Adicione estas funções ao seu index.js:
// exports.forceUpdatePeriodIds = require('./forceUpdatePeriodIds').forceUpdatePeriodIds;
// exports.forceCreateMissingSnapshots = require('./forceUpdatePeriodIds').forceCreateMissingSnapshots;