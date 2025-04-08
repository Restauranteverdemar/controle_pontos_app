Sistema de Gestão de Ocorrências e Pontuação (README)
(Última Atualização: 9 de Abril de 2025 - Implementação de Filtro Avançado e Histórico de Saldo Mensal)
Objetivo Principal e Visão Geral
Desenvolver um aplicativo multiplataforma (Mobile/Web) utilizando Flutter e Firebase para um restaurante, focado em:

Registro e Gestão Manual: Registrar, gerenciar, aprovar e calcular pontos (positivos/negativos) de funcionários associados a ocorrências específicas do dia a dia, impactando um saldo de pontos principal unificado (saldoPontosAprovados).
Automação via Regras: Implementar um sistema onde regras automáticas (definidas pelo Admin) podem gerar ocorrências de pontos (positivas como bônus, ou negativas como advertências pendentes) que impactam o saldo principal. Essas regras operam em ciclos de avaliação definidos (ex: diário, semanal, mensal) e são executadas por Cloud Functions.
Reset Mensal e Histórico: Implementar um reset mensal configurável do saldo principal (saldoPontosAprovados), enquanto preserva um histórico completo de todas as ocorrências (pointsOccurrences) e mantém um histórico dos saldos finais de cada mês (userBalanceSnapshots).

O sistema visa automatizar parte da gestão de desempenho e ocorrências através de regras personalizáveis, unificando todos os pontos (manuais, negativos, bônus automáticos) em um único saldo (saldoPontosAprovados). Possui dois níveis de acesso principais: Admin e Funcionário (segmentados por Cozinha e Salão).
Níveis de Acesso e Funcionalidades
Funcionário

Visão: Acesso ao seu próprio perfil, ocorrências e saldo de pontos.
Permissões:

Visualizar seu Saldo Principal Aprovado (saldoPontosAprovados), que reflete TODAS as ocorrências ('Approved') desde o último reset mensal. (Implementado ✓).
Visualizar seu histórico detalhado de Ocorrências (pointsOccurrences) com status, quem registrou (incluindo 'system/automatic'), data (registeredAt), tipo (incluindo bônus automáticos) e anexos. (Implementado ✓ - Com Filtro Avançado ✓).
Visualizar histórico de saldo final dos meses anteriores (via Modal). (Implementado ✓)
Navegar para visualizar ocorrências de um mês específico a partir do histórico de saldo. (Implementado ✓)
Editar informações básicas do seu perfil (nome - pendente, e-mail - pendente, senha - pendente - via Auth). ✗ (PENDENTE MENOR)



Admin

Visão: Acesso total ao sistema para gerenciamento completo.
Permissões:

Gerenciar Funcionários: (CRUD, Promoção, Alterar Role/Dept, Reset Senha - via Modais e Cloud Functions). ✓
Gerenciar Tipos de Ocorrência: (CRUD, Pontos, Departamentos). ✓ Nota: Admins DEVEM criar tipos de ocorrência específicos para os Bônus/Advertências Automáticas.
Gerenciar Ocorrências (Fluxo Manual): (Registrar, Aprovar/Reprovar Pendentes, Editar, Excluir, Histórico Completo com Filtros). ✓
Visualizar saldo atual de pontos dos funcionários diretamente na lista de funcionários. ✓
Acessar histórico mensal de pontos através do modal de detalhes do funcionário. ✓
Gerenciar Regras Automáticas (Motor de Regras - Fase 2):

Frontend (UI): Criar e gerenciar regras (automationRules) na interface do app (Definir nome, descrição, frequência, escopo, condição, ação - tipo de ocorrência e status inicial). ✓
Interface otimizada exibindo nomes de tipos de ocorrência em vez de IDs. ✓
Backend (Cloud Functions): Funções agendadas (processDaily/Weekly/MonthlyRules) que leem as regras, avaliam as condition (tipos suportados: occurrenceCount, absenceOfOccurrence) e executam a action (criando ocorrências em pointsOccurrences com status 'Approved' ou 'Pending'). ✓ (Implementado - Requer Testes/Monitoramento)


Executar Reset Mensal Manual: Habilidade de iniciar manualmente o processo de reset mensal para testes ou situações excepcionais. (Implementado ✓)
Configurar Reset Mensal (se necessário - ex: ativar/desativar, definir escopo - Funcionalidade futura opcional). ✗



Tecnologias Utilizadas

Linguagem (Frontend): Dart
Framework (Frontend): Flutter
Backend: Firebase
Autenticação: Firebase Authentication (Email/Senha) ✓
Banco de Dados: Firestore ✓

users: Dados dos funcionários, incluindo saldoPontosAprovados (saldo atual volátil).
incidentTypes: Definição dos tipos de ocorrências (manuais e automáticas).
pointsOccurrences: Registro histórico permanente de TODAS as ocorrências (manuais, automáticas, positivas, negativas). Fonte do histórico detalhado e base para cálculo de saldo via triggers. Contém status, userId, incidentTypeId, points, registeredAt (Timestamp do registro/evento), createdBy ('system/automatic' ou UID do admin), createdByRuleId (se aplicável), periodId (null para ocorrências atuais, "YYYY-MM" para ocorrências após reset).
automationRules: Configuração das regras automáticas (condições, frequência, escopo, ação - qual incidentTypeId criar e defaultStatus).
userBalanceSnapshots: Coleção que armazena o saldo final (finalBalance) de cada usuário ao final de cada mês (yearMonth), registrado pela função de reset. Essencial para o histórico de saldo mensal. ✓
adminLogs: Registro de ações administrativas importantes, como reset manual de saldo. ✓
(Opcional) clockInRecords: Registros de ponto (se regras de atraso forem implementadas).


Cloud Functions (Node.js/JavaScript): ✓

Estrutura: Código organizado em src/index.js (triggers, callable, exports), src/automationRules.js (lógica do motor de regras), src/monthlyReset.js (lógica de reset mensal), src/utils.js (constantes e helpers). ✓
Triggers:

onCreateUser: Cria documento inicial em users. ✓
onOccurrenceStatusChange: ÚNICO local que atualiza users.saldoPontosAprovados com base na transição de status da ocorrência para/de 'Approved'. ✓ (Implementado - Verificado)
onOccurrenceDelete: Reverte pontos no saldoPontosAprovados se uma ocorrência 'Approved' for excluída. ✓ (Implementado - Verificado)


Funções Agendadas (Scheduler):

processDailyRules, processWeeklyRules, processMonthlyRules: Executam periodicamente, chamando a lógica em automationRules.js. ✓ (Implementado - Requer Testes/Monitoramento)
resetMonthlyBalances: Executa no início de cada mês. Responsável por: 1. Ler saldo atual, 2. Salvar em userBalanceSnapshots, 3. Resetar users.saldoPontosAprovados para 0, 4. Marcar ocorrências com periodId correspondente. ✓ (Implementado - Verificado via testes manuais)


Funções Callable (HTTP):

createUser, deleteUser, updateUserEmail, sendUserPasswordReset, promoteUserToAdmin, changeUserRole. ✓
resetMonthlyBalanceManual: Permite administradores executarem o reset mensal manualmente. ✓
httpResetMonthlyBalances: Endpoint HTTP para reset manual direto pelo console do Firebase. ✓


Lógica do Motor de Regras (automationRules.js):

evaluateRulesForFrequency, processRule, processRuleForEmployee, evaluateCondition (occurrenceCount, absenceOfOccurrence), executeRuleAction. ✓ (Implementado - Requer Testes/Monitoramento)




Storage: Firebase Storage para anexos de ocorrências. ✓
App Check: Configurado. ✓
Gerenciamento de Estado (Flutter): Provider + ChangeNotifier, StreamBuilder ✓
Pacotes Principais: firebase_core, firebase_auth, cloud_firestore, cloud_functions, firebase_storage, provider, image_picker, intl ✓

Status Atual (9 de Abril de 2025)

Contexto Atual:

Branch: develop/fase2-finalization (sugestão)
Foco Anterior: Implementar as funcionalidades de filtro avançado de ocorrências e histórico de saldo mensal com drill-down para o funcionário.
Foco Atual: Realizar testes end-to-end das novas funcionalidades, monitorar logs e realizar refinamentos.


Estado Técnico:

Backend (Cloud Functions - Motor de Regras): Implementado ✓ (Requer Testes/Monitoramento contínuos).
Backend (Triggers de Atualização de Saldo): Implementados ✓ (Verificados).
Backend (Reset Mensal): Implementado com salvamento de histórico ✓ (Testado manualmente).
Frontend (UI Admin - CRUD de Regras): Implementada com nomes e cache. ✓
Frontend (UI Admin - Reset Manual): Implementado com confirmação e feedback. ✓
Frontend (UI Admin - Visualização de Saldo na Lista de Funcionários): Implementado. ✓
Frontend (UI Admin - Histórico Mensal no Modal de Detalhes): Implementado. ✓
Frontend (UI Funcionário - Dashboard com Filtro Avançado): Implementado. ✓
Frontend (UI Funcionário - Modal de Histórico Mensal): Implementado como componente reutilizável. ✓
Frontend (UI Funcionário - Drill-Down para Ocorrências Mensais): Implementado. ✓
Modelo de Dados - Implementação de periodId: Corrigido para garantir que novas ocorrências sejam criadas com periodId: null. ✓
Índices Compostos no Firestore: Criados para suportar consultas complexas. ✓


Funcionalidades Pendentes/Em Andamento:

Testar/Monitorar desempenho do motor de regras em produção. ⏳ (Contínuo)
(Opcional) Implementar suporte a mais ConditionTypes no backend e frontend. ✗
Edição de Perfil (Funcionário): Nome, email, senha. ✗ (PENDENTE MENOR)
Refinamentos Adicionais (Testes Unitários/Integração, UI/UX). ⏳ (Contínuo)



Modificações Recentes (8-9/Abril/2025)

Implementação do filtro avançado de ocorrências na interface do funcionário.
Implementação do componente reutilizável BalanceHistoryModal para exibição de histórico de saldo.
Implementação da tela MonthlyOccurrencesPage para visualização de ocorrências por mês.
Modificação da Cloud Function resetMonthlyBalances para salvar histórico de saldo.
Correção do modelo de dados para garantir que novas ocorrências sejam criadas com periodId: null.
Atualização dos serviços e controllers para manter a consistência do campo periodId.
Adição de visualização de saldo mensal diretamente nos cards da lista de funcionários.
Implementação de nova aba de histórico mensal no modal de detalhes do funcionário.
Criação das funções callable/HTTP para reset manual de saldo.
Implementação do botão reutilizável ResetMonthlyBalanceButton para interface de admin.
Criação dos índices compostos necessários no Firestore.
Atualização das regras de segurança do Firestore para a nova coleção userBalanceSnapshots.
Correção de problemas de layout/overflow na interface do funcionário.

Estrutura de Pastas (Frontend Atualizada)
lib/ # Código Flutter (Frontend)
├── core/
├── features/
│ ├── admin/
│ │ ├── screens/
│ │ │ ├── automation_rules_page.dart
│ │ │ ├── create_edit_rule_page.dart
│ │ │ ├── employee_detail_modal.dart # Atualizado com aba de histórico mensal ✓
│ │ │ ├── lista_funcionarios_page.dart # Atualizado com visualização de saldo ✓
│ │ │ └── ... (outras telas admin)
│ │ ├── services/
│ │ │ └── automation_rule_service.dart
│ │ │ └── ... (outros serviços admin)
│ │ └── widgets/
│ │   └── reset_monthly_balance_button.dart # NOVO - Botão para reset manual
│ ├── auth/
│ ├── employee/
│ │ ├── screens/
│ │ │ ├── employee_dashboard_page.dart # Modificado com filtro avançado ✓
│ │ │ └── monthly_occurrences_page.dart # NOVO - Tela de drill-down ✓
│ │ └── services/ # (Opcional: balance_history_service.dart)
│ │ └── widgets/ # (Opcional: Widgets reutilizáveis)
│ ├── shared/
│ │ ├── controllers/
│ │ │ └── registro_ocorrencia_controller.dart # Atualizado para garantir periodId=null ✓
│ │ ├── enums/
│ │ ├── models/
│ │ │ └── point_occurrence.dart # Atualizado para definir periodId=null por padrão ✓
│ │ ├── services/ 
│ │ │ └── point_occurrence_service.dart # Atualizado com métodos que garantem periodId=null ✓
│ │ ├── utils/ # (Helpers de formatação, etc.)
│ │ └── widgets/ 
│ │   └── balance_history_modal.dart # NOVO - Widget reutilizável para histórico
│
├── firebase_options.dart
└── main.dart # Configuração dos Providers ✓
functions/ # Código Cloud Functions (Backend)
├── node_modules/
├── src/ # Pasta com código fonte das funções
│ ├── index.js # Ponto de entrada: Triggers, Callable, Exports, Funções de Reset ✓
│ ├── automationRules.js# Lógica principal do Motor de Regras ✓
│ ├── monthlyReset.js # Lógica do Reset Mensal (Modificada) ✓
│ ├── forceUpdatePeriodIds.js # NOVO - Ferramenta para corrigir ocorrências existentes ✓
│ ├── debugMonthlyReset.js # NOVO - Ferramenta para diagnosticar ocorrências ✓
│ └── utils.js # Constantes e Helpers compartilhados ✓
├── package.json # Dependências e configuração ("main": "src/index.js") ✓
├── .eslintrc.js # Configuração do Linter (opcional)
└── .gitignore
Roteiro de Desenvolvimento (Revisado - 9 de Abril de 2025)
(Itens 1-23 Concluídos/Mantidos ✓)
19. Refatoração de Código: ✓ (Contínuo)
20. Implementação do Motor de Regras (Fase 2): ✓
*   Frontend UI (CRUD de Regras): ✓
*   Backend Cloud Functions (Avaliação, Ação, Agendamento): ✓
*   Backend Triggers (Atualização de Saldo): ✓
*   Testes e Monitoramento: ⏳ (Em Andamento/Contínuo)
21. Implementação Filtro Avançado Ocorrências (Frontend - EmployeeDashboardPage) ✓
22. Modificação Backend resetMonthlyBalances (Salvar Histórico Saldo em userBalanceSnapshots) ✓
23. Implementação UI Histórico Saldo Mensal (Modal + Drill-Down para MonthlyOccurrencesPage) ✓
24. Implementação de Reset Manual para Administradores ✓
25. Correção do modelo de dados para garantir periodId: null em novas ocorrências ✓
26. Adição de visualização de saldo na lista de funcionários ✓
27. Implementação de aba de histórico mensal no modal de detalhes do funcionário ✓
28. Testes End-to-End das Novas Funcionalidades ⏳ (Em Andamento)
29. (Opcional) Implementar mais ConditionTypes. ✗
30. Implementação de perfil do funcionário (edição de dados pessoais). ⏳ (PENDENTE MENOR)
31. Refinamentos Adicionais (Testes Unitários/Integração, UI/UX). ⏳ (Contínuo)
Próximos Passos Imediatos (Revisado - 9 de Abril de 2025)

Realizar Testes End-to-End Completos das Novas Funcionalidades:

Testar o filtro avançado de ocorrências com diferentes períodos e validar resultados.
Testar o modal de histórico de saldo mensal e verificar carregamento dos dados.
Testar a navegação drill-down para visualização de ocorrências mensais específicas.
Testar o reset mensal manual e validar a criação correta de snapshots.
Verificar comportamento da UI em diferentes tamanhos de tela e orientações.
Testar a criação de novas ocorrências e garantir que estejam com periodId: null.


Monitoramento e Otimização:

Revisar logs do Firebase para identificar possíveis erros ou gargalos.
Monitorar desempenho das consultas do Firestore, especialmente as com filtros complexos.
Observar uso de recursos das Cloud Functions, especialmente durante processamento de regras e resets.
Otimizar queries e lógica de negócio conforme necessário.


Documentação e Preparação para Produção:

Atualizar qualquer documentação interna para refletir as novas funcionalidades.
Preparar notas de lançamento ou documentação para usuários finais.
Verificar configurações de backup e recuperação no ambiente de produção.
Planejar estratégia de implantação e comunicação com usuários.


Iniciar Implementação de Funcionalidades Pendentes (Opcional):

Edição de perfil do funcionário.
Suporte a mais tipos de condições no motor de regras.
Melhorias na análise e visualização de dados para administradores.



Resumo da Fase 2 (Finalizada)
A Fase 2 do sistema implementou um motor completo de regras automáticas e expandiu as capacidades de histórico e visualização:

Motor de Regras: Cloud Functions agendadas criam automaticamente ocorrências baseadas em regras definidas pelo Admin. Essas ocorrências são tratadas da mesma forma que ocorrências manuais, afetando o saldo principal quando aprovadas.
Reset Mensal com Histórico: A função de reset mensal agora salva um snapshot do saldo final de cada usuário antes de zerar, permitindo manter um histórico completo dos saldos mensais. Também marca ocorrências existentes com o periodId correspondente.
Visualizações Avançadas:

Os funcionários podem filtrar ocorrências por períodos específicos
Todos os usuários podem acessar um histórico completo dos saldos mensais
Interface para navegar e ver ocorrências de meses específicos
Administradores podem ver o saldo atual na lista de funcionários
Modal de detalhes do funcionário inclui aba dedicada para histórico mensal


Ferramentas de Administração: Os administradores podem executar resets mensais manualmente para testes ou situações excepcionais, com mecanismos de segurança e registro de auditoria.
Correções de Modelo de Dados: Implementação de soluções para garantir que novas ocorrências sejam criadas com periodId: null, essencial para o funcionamento correto do sistema de reset mensal e filtros.

O sistema agora está totalmente funcional para gerenciar tanto ocorrências manuais quanto automáticas, com interfaces intuitivas para usuários e mecanismos robustos de histórico e administração.