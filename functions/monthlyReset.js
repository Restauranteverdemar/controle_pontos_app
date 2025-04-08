// functions/src/monthlyReset.js

/**
 * Função para resetar saldos mensais de todos os usuários
 * - Salva o saldo final em userBalanceSnapshots
 * - Marca as ocorrências do período sendo fechado com periodId: 'YYYY-MM'
 * - Zera o saldoPontosAprovados do usuário
 * 
 * Projetada para ser chamada a partir do index.js que já tem as dependências inicializadas
 * 
 * @param {Object} admin - Instância inicializada do firebase-admin
 * @param {Object} db - Referência ao Firestore
 * @returns {Promise<Object>} Objeto com resultados da operação
 */
async function resetMonthlyBalances(admin, db) {
    const logPrefix = '[resetMonthlyBalances]';
    console.log(`${logPrefix} Iniciando reset mensal de saldos e marcação de ocorrências...`);
  
    try {
      // --- 1. Determinar o Período a ser Fechado ---
      const now = new Date();
      // Pega o último dia do MÊS ANTERIOR para determinar o período
      const previousMonthDate = new Date(now.getFullYear(), now.getMonth(), 0); 
      const year = previousMonthDate.getFullYear();
      // getMonth() é 0-indexado, então adicionamos 1
      const month = String(previousMonthDate.getMonth() + 1).padStart(2, '0'); 
      const periodIdToClose = `${year}-${month}`; // Formato 'YYYY-MM'
  
      console.log(`${logPrefix} Período a ser fechado: ${periodIdToClose}`);
  
      // --- 2. Buscar todos os usuários ---
      const usersSnapshot = await db.collection('users').get();
  
      if (usersSnapshot.empty) {
        console.log(`${logPrefix} Nenhum usuário encontrado para processar.`);
        return { success: true, processedUsers: 0, markedOccurrences: 0, periodIdClosed: periodIdToClose };
      }
  
      // --- 3. Processar cada usuário ---
      let totalProcessedUsers = 0;
      let totalMarkedOccurrences = 0;
      const errors = []; // Para coletar erros por usuário
  
      // Processar um usuário por vez
      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const userData = userDoc.data();
        const currentBalance = userData.saldoPontosAprovados || 0;
        console.log(`${logPrefix} Processando usuário ${userId} (Saldo: ${currentBalance})...`);
  
        try {
          // --- 3a. Salvar Snapshot de Saldo ---
          // Snapshot e reset de saldo são operações simples, faremos juntos
          const userBatch = db.batch();
          const snapshotRef = db.collection('userBalanceSnapshots').doc();
          userBatch.set(snapshotRef, {
            userId,
            periodId: periodIdToClose,
            yearMonth: periodIdToClose,
            finalBalance: currentBalance,
            recordedAt: admin.firestore.FieldValue.serverTimestamp()
          });
  
          // Resetar saldo do usuário
          const userRef = db.collection('users').doc(userId);
          userBatch.update(userRef, {
            saldoPontosAprovados: 0,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
          });
  
          // Executar esse batch separadamente
          await userBatch.commit();
          console.log(`${logPrefix} [${userId}] Snapshot criado e saldo resetado`);
  
          // --- 3b. Marcar Ocorrências do Período ---
          // Busca ocorrências do usuário que AINDA não foram marcadas (periodId é null)
          const occurrencesToMarkSnapshot = await db.collection('pointsOccurrences')
            .where('userId', '==', userId)
            .where('periodId', '==', null)
            .get();
  
          if (!occurrencesToMarkSnapshot.empty) {
            console.log(`${logPrefix} [${userId}] Encontradas ${occurrencesToMarkSnapshot.size} ocorrências para marcar.`);
            
            // CORREÇÃO: Processar em lotes menores para evitar limite de 500 operações por batch
            const occurrenceDocs = occurrencesToMarkSnapshot.docs;
            const batchSize = 450; // Limite seguro para batch (abaixo do limite de 500)
            let markedOccurrencesForUser = 0;
            
            // Processar em lotes
            for (let i = 0; i < occurrenceDocs.length; i += batchSize) {
              const currentBatch = db.batch();
              const currentOccurrences = occurrenceDocs.slice(i, i + batchSize);
              
              console.log(`${logPrefix} [${userId}] Processando lote de ${currentOccurrences.length} ocorrências (${i+1}-${Math.min(i+batchSize, occurrenceDocs.length)} de ${occurrenceDocs.length})`);
              
              // Adicionar cada ocorrência ao batch atual
              currentOccurrences.forEach(doc => {
                currentBatch.update(doc.ref, { periodId: periodIdToClose });
              });
              
              // Executar o batch atual
              await currentBatch.commit();
              markedOccurrencesForUser += currentOccurrences.length;
              console.log(`${logPrefix} [${userId}] Lote de ocorrências processado com sucesso.`);
            }
            
            console.log(`${logPrefix} [${userId}] Total de ${markedOccurrencesForUser} ocorrências marcadas com periodId ${periodIdToClose}.`);
            totalMarkedOccurrences += markedOccurrencesForUser;
          } else {
            console.log(`${logPrefix} [${userId}] Nenhuma ocorrência encontrada para marcar.`);
          }
  
          totalProcessedUsers++;
  
        } catch (userError) {
          console.error(`${logPrefix} [${userId}] ERRO ao processar usuário:`, userError);
          errors.push({ userId, error: userError.message });
          // Continua para o próximo usuário mesmo se um falhar
        }
      } // Fim do loop de usuários
  
      // --- 4. Retornar Resultado Final ---
      console.log(`${logPrefix} Reset concluído. ${totalProcessedUsers} usuários processados, ${totalMarkedOccurrences} ocorrências marcadas.`);
      if (errors.length > 0) {
        console.warn(`${logPrefix} Ocorreram erros durante o processo:`, errors);
        // Retorna sucesso parcial se houve erros, mas alguns usuários processaram
        return { 
          success: errors.length < usersSnapshot.size, // Sucesso parcial
          processedUsers: totalProcessedUsers, 
          markedOccurrences: totalMarkedOccurrences, 
          periodIdClosed: periodIdToClose,
          errors: errors 
        };
      } else {
        // Sucesso total
        return { 
          success: true, 
          processedUsers: totalProcessedUsers, 
          markedOccurrences: totalMarkedOccurrences, 
          periodIdClosed: periodIdToClose 
        };
      }
  
    } catch (error) {
      console.error(`${logPrefix} ERRO GERAL FATAL ao resetar saldos mensais:`, error);
      if (error.stack) {
        console.error(`${logPrefix} Stack trace:`, error.stack);
      }
      // Lança o erro para que a função Cloud principal saiba que falhou
      throw new Error(`Falha crítica no reset mensal: ${error.message}`);
    }
  }
  
  module.exports = {
    resetMonthlyBalances
  };