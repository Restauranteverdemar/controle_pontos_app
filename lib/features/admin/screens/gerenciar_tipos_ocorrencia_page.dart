import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Importado para formatação de data
import '../../shared/models/incident_type.dart'; // Modelo
import 'criar_editar_tipo_ocorrencia_page.dart'; // Tela de criação/edição
import 'dart:async'; // Para Debouncer

// Enum para definir os possíveis filtros de status (mantido, mas menos relevante para exclusão)
enum StatusFilter { todos, ativos, inativos }

class GerenciarTiposOcorrenciaPage extends StatefulWidget {
  const GerenciarTiposOcorrenciaPage({super.key});

  @override
  State<GerenciarTiposOcorrenciaPage> createState() =>
      _GerenciarTiposOcorrenciaPageState();
}

class _GerenciarTiposOcorrenciaPageState
    extends State<GerenciarTiposOcorrenciaPage> {
  // --- Estado para Filtro e Busca ---
  StatusFilter _filtroStatus = StatusFilter.todos; // Mantido por enquanto
  String _termoBusca = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // --- Constantes ---
  // MELHORIA: Extraí as constantes para estáticas de classe para melhorar a legibilidade e manutenibilidade
  static const double _cardMarginVertical = 6.0;
  static const double _cardMarginHorizontal = 8.0;
  static const double _pagePaddingHorizontal = 12.0;
  static const double _pagePaddingVertical = 8.0;
  static const int _debounceMs = 400;

  // --- Formatador de Data ---
  final DateFormat _dateFormatter = DateFormat('dd/MM/yyyy HH:mm');

  // --- Referência ao Firestore ---
  // MELHORIA: Adicionei o final para garantir que a referência seja imutável
  final CollectionReference _incidentTypesCollection =
      FirebaseFirestore.instance.collection('incidentTypes');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // Função chamada quando o texto de busca muda (com debounce)
  void _onSearchChanged() {
    // MELHORIA: Otimizado o código do debounce para ser mais conciso
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (mounted) {
        setState(() {
          _termoBusca = _searchController.text.trim().toLowerCase();
        });
      }
    });
  }

  // --- REMOVIDO: Função _toggleStatus ---
  // A função _toggleStatus foi removida pois foi substituída pela _deleteIncidentType

  // --- Função Auxiliar para Navegação (Mantida) ---
  void _navigateToCriarEditar({IncidentType? incidentType}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CriarEditarTipoOcorrenciaPage(incidentType: incidentType),
      ),
    ).then((_) {
      // Atualiza o estado caso algo mude na tela de edição (como nome)
      // Embora o StreamBuilder atualize a lista, isso pode forçar
      // uma re-renderização mais imediata se necessário.
      if (mounted) setState(() {});
    });
  }

  // --- NOVA FUNÇÃO: Excluir Tipo de Ocorrência ---
  Future<void> _deleteIncidentType(IncidentType type) async {
    // MELHORIA: Capturado o Messenger antes do await para evitar problemas de contexto
    final scaffoldMessenger =
        ScaffoldMessenger.of(context); // Capture antes do await
    final typeName = type.name; // Capture nome antes do await

    // --- ETAPA CRÍTICA: CONFIRMAÇÃO ---
    // MELHORIA: Adicionei const para widgets estáticos para melhorar a performance
    final confirmDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Impede fechar clicando fora
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(dialogContext)
                  .style
                  .copyWith(fontSize: 16), // Estilo base
              children: <TextSpan>[
                const TextSpan(
                    text:
                        'Tem certeza que deseja excluir permanentemente o tipo de ocorrência "'),
                TextSpan(
                    text: typeName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const TextSpan(text: '"?\n\n'),
                const TextSpan(
                    text: 'Esta ação não pode ser desfeita.',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red)),
                const TextSpan(
                    text:
                        '\nOcorrências já registradas com este tipo permanecerão, mas podem perder a referência ao nome/pontos originais.',
                    style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Colors.orange)),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(false); // Retorna false se cancelar
              },
            ),
            TextButton(
              style: TextButton.styleFrom(
                  foregroundColor:
                      Colors.red), // Botão de confirmação em vermelho
              child: const Text('Excluir Permanentemente'),
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(true); // Retorna true se confirmar
              },
            ),
          ],
        );
      },
    );

    // Se o usuário não confirmou (clicou em Cancelar ou fechou o dialog), sai da função
    if (confirmDelete != true) {
      return;
    }

    // MELHORIA: Adicionei uma verificação de montagem antes do primeiro SnackBar
    if (!scaffoldMessenger.mounted) return;

    // Se confirmou, prossegue com a exclusão
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Excluindo "$typeName"...'),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      // Comando para excluir o documento no Firestore
      await _incidentTypesCollection.doc(type.id).delete();

      // Não é necessário atualizar o estado localmente, o StreamBuilder fará isso.
      if (!scaffoldMessenger.mounted) return; // Check se ainda está montado
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Tipo "$typeName" excluído com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // MELHORIA: Adicionei um log mais detalhado do erro
      print('Erro ao excluir o tipo "$typeName" (ID: ${type.id}): $e');
      // Verifique se o widget ainda está montado antes de mostrar o SnackBar de erro
      if (!scaffoldMessenger.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
              'Erro ao excluir o tipo "$typeName". Verifique as permissões ou a conexão (${e.toString()})'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --- MODIFICADO: Método para criar PopupMenuItems (com Excluir) ---
  // MELHORIA: Extraí este método separado para melhorar a legibilidade e reutilização
  List<PopupMenuEntry<String>> _buildPopupMenuItems(IncidentType incidentType) {
    return <PopupMenuEntry<String>>[
      // 1. Opção Editar (Mantida)
      const PopupMenuItem<String>(
        value: 'edit',
        child: ListTile(
          leading: Icon(Icons.edit_outlined, size: 20),
          title: Text('Editar'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),

      // 2. Opção Ativar/Desativar (Removida)
      // PopupMenuItem<String>( ... ),

      // 3. Separador Visual (Adicionado)
      const PopupMenuDivider(),

      // 4. Opção Excluir (Adicionada)
      const PopupMenuItem<String>(
        value: 'delete', // Valor para identificar a ação de excluir
        child: ListTile(
          leading: Icon(
            Icons.delete_outline, // Ícone de lixeira
            size: 20,
            color: Colors.red, // Cor vermelha para alerta
          ),
          title: Text(
            'Excluir',
            style: TextStyle(color: Colors.red), // Texto em vermelho
          ),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ];
  }

  // --- Método para construir o Card (com onSelected atualizado) ---
  Widget _buildIncidentTypeCard(IncidentType incidentType) {
    // ... (lógica de cores, ícones, etc., permanece a mesma) ...
    final bool isPositive = incidentType.defaultPoints >= 0;
    final Color pointsColor =
        isPositive ? Colors.green.shade700 : Colors.red.shade700;
    final IconData pointIcon =
        isPositive ? Icons.arrow_upward : Icons.arrow_downward;
    final String statusText = incidentType.isActive ? "Ativo" : "Inativo";
    final Color statusColor =
        incidentType.isActive ? Colors.green : Colors.grey;
    final Color textColor =
        incidentType.isActive ? Colors.black : Colors.grey.shade600;
    final TextDecoration textDecoration = incidentType.isActive
        ? TextDecoration.none
        : TextDecoration.lineThrough;

    // MELHORIA: Adicionei const onde possível para widgets estáticos
    return Card(
      margin: const EdgeInsets.symmetric(
          vertical: _cardMarginVertical, horizontal: _cardMarginHorizontal),
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
          side: BorderSide(
            color: incidentType.isActive
                ? Colors.grey.shade300
                : Colors.grey.shade400,
            width: incidentType.isActive ? 0.5 : 1.0,
          )),
      color: incidentType.isActive
          ? Colors.white
          : Colors.grey.shade100.withOpacity(0.8),
      child: ListTile(
        // ... (leading, title, subtitle permanecem os mesmos) ...
        leading: CircleAvatar(
          backgroundColor: pointsColor.withOpacity(0.15),
          child: Icon(pointIcon, color: pointsColor, size: 20),
        ),
        title: Text(
          incidentType.name,
          style: TextStyle(
              fontWeight: FontWeight.w500,
              color: textColor,
              decoration: textDecoration),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pontos: ${incidentType.defaultPoints > 0 ? '+' : ''}${incidentType.defaultPoints}',
              style: TextStyle(
                  color: pointsColor,
                  fontWeight: FontWeight.bold,
                  decoration: textDecoration),
            ),
            // MELHORIA: Otimizei a verificação de descrição não nula e não vazia
            if (incidentType.description?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  incidentType.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: textColor.withOpacity(0.8),
                      decoration: textDecoration),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                'Status: $statusText', // Ainda mostra o status se o campo existir
                style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w500),
              ),
            ),
            if (incidentType.updatedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  'Atualizado: ${_dateFormatter.format(incidentType.updatedAt!.toDate())}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ),
          ],
        ),
        isThreeLine: (incidentType.description?.isNotEmpty ?? false) ||
            incidentType.updatedAt != null,

        // --- MODIFICADO: PopupMenuButton ---
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          tooltip: "Mais opções",
          onSelected: (String result) {
            switch (result) {
              case 'edit':
                _navigateToCriarEditar(incidentType: incidentType);
                break;
              // case 'toggleStatus': // REMOVIDO
              //   _toggleStatus(incidentType);
              //   break;
              case 'delete': // ADICIONADO
                _deleteIncidentType(incidentType); // Chama a função de exclusão
                break;
            }
          },
          itemBuilder: (BuildContext context) =>
              _buildPopupMenuItems(incidentType), // Usa o menu modificado
        ),
        onTap: () =>
            _navigateToCriarEditar(incidentType: incidentType), // Mantido
      ),
    );
  }

  // --- Método para obter o stream com base nos filtros (Mantido) ---
  // A query ainda pode usar 'isActive' se você mantiver o campo,
  // mesmo que a UI não permita mais desativar. Se remover o campo 'isActive'
  // do Firestore, remova os filtros '.where' daqui.
  Stream<QuerySnapshot> _getIncidentTypesStream() {
    Query query = _incidentTypesCollection.orderBy('name');

    // O filtro de status ainda funciona se o campo 'isActive' existir.
    // Se você remover 'isActive' dos seus dados, remova essas linhas:
    if (_filtroStatus == StatusFilter.ativos) {
      query = query.where('isActive', isEqualTo: true);
    } else if (_filtroStatus == StatusFilter.inativos) {
      query = query.where('isActive', isEqualTo: false);
    }

    return query.snapshots(includeMetadataChanges: false);
  }

  // --- Método auxiliar para mensagem de lista vazia (Mantido) ---
  String _getMensagemListaVazia() {
    // A mensagem ainda considera o filtro, ajuste se remover o campo 'isActive'
    if (_termoBusca.isNotEmpty && _filtroStatus != StatusFilter.todos) {
      final statusDesc =
          _filtroStatus == StatusFilter.ativos ? 'ativos' : 'inativos';
      return 'Nenhum tipo $statusDesc encontrado com o termo "$_termoBusca".';
    } else if (_termoBusca.isNotEmpty) {
      return 'Nenhum tipo encontrado com o termo "$_termoBusca".';
    } else if (_filtroStatus != StatusFilter.todos) {
      final statusDesc =
          _filtroStatus == StatusFilter.ativos ? 'ativos' : 'inativos';
      // Poderia mudar esta mensagem se 'isActive' for removido, ex:
      // return 'Não há tipos de ocorrência cadastrados (filtro ativo).';
      return 'Não há tipos de ocorrência $statusDesc cadastrados.';
    } else {
      return 'Nenhum tipo de ocorrência cadastrado ainda.';
    }
  }

  // --- Método para filtrar a lista de tipos com base nos critérios (Mantido) ---
  List<IncidentType> _filterIncidentTypes(List<IncidentType> types) {
    // O filtro de busca local permanece o mesmo
    if (_termoBusca.isEmpty) {
      return types;
    }
    // MELHORIA: Otimizei a verificação de descrição não nula
    return types.where((type) {
      final searchMatch = type.name.toLowerCase().contains(_termoBusca) ||
          (type.description?.toLowerCase().contains(_termoBusca) ?? false);
      return searchMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // MELHORIA: Adicionei const em mais widgets estáticos para melhorar performance
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tipos de Ocorrência'),
        // O filtro de status no AppBar pode ser mantido ou removido,
        // dependendo se você ainda quer filtrar por 'isActive' (se o campo existir)
        actions: [
          PopupMenuButton<StatusFilter>(
            initialValue: _filtroStatus,
            tooltip: 'Filtrar por Status',
            icon: Icon(
              Icons.filter_list,
              color: _filtroStatus != StatusFilter.todos
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onSelected: (StatusFilter result) {
              setState(() {
                _filtroStatus = result;
              });
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<StatusFilter>>[
              const PopupMenuItem<StatusFilter>(
                  value: StatusFilter.todos, child: Text('Mostrar Todos')),
              const PopupMenuItem<StatusFilter>(
                  value: StatusFilter.ativos, child: Text('Apenas Ativos')),
              const PopupMenuItem<StatusFilter>(
                  value: StatusFilter.inativos, child: Text('Apenas Inativos')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // --- Barra de Busca (Mantida) ---
          Padding(
            padding: const EdgeInsets.fromLTRB(
                _pagePaddingHorizontal, 8.0, _pagePaddingHorizontal, 8.0),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou descrição...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30.0),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey[200],
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                        tooltip: 'Limpar busca',
                      )
                    : null,
              ),
            ),
          ),
          // --- Lista com StreamBuilder (Mantida, mas usa o _buildIncidentTypeCard modificado) ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  _getIncidentTypesStream(), // Usa a stream (filtrada ou não por isActive)
              builder: (context, snapshot) {
                // ... (lógica de loading, erro, lista vazia inicial permanece a mesma) ...
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  // MELHORIA: Melhorei o tratamento de erro para mostrar o erro específico
                  debugPrint('Erro ao buscar tipos: ${snapshot.error}');
                  return Center(
                      child: Text('Erro ao carregar dados: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  if (_termoBusca.isEmpty) {
                    // MELHORIA: Adicionei uma UI mais informativa para lista vazia
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.category_outlined,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(_getMensagemListaVazia(),
                              style: const TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          if (_filtroStatus != StatusFilter.todos)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _filtroStatus = StatusFilter.todos;
                                });
                              },
                              child: const Text('Limpar filtro'),
                            ),
                        ],
                      ),
                    );
                  }
                }

                final docsFromStream = snapshot.data!.docs;
                final List<IncidentType> typesFromStream = [];
                final List<String> errorDocIds =
                    []; // Para tratar erros de conversão

                for (var doc in docsFromStream) {
                  try {
                    typesFromStream.add(IncidentType.fromSnapshot(doc));
                  } catch (e) {
                    errorDocIds.add(doc.id);
                    debugPrint(
                        "Erro ao converter DocumentSnapshot: $e - Doc ID: ${doc.id}");
                    // Considerar mostrar um card de erro para estes IDs
                  }
                }

                // Aplica o filtro de BUSCA localmente
                final List<IncidentType> filteredList =
                    _filterIncidentTypes(typesFromStream);

                // Mensagem se a lista ficou VAZIA APÓS A BUSCA
                if (filteredList.isEmpty) {
                  if (docsFromStream.isNotEmpty || _termoBusca.isNotEmpty) {
                    // MELHORIA: Adicionei uma UI mais informativa para busca sem resultados
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.search_off,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(_getMensagemListaVazia(),
                              style: const TextStyle(color: Colors.grey)),
                          const SizedBox(height: 8),
                          if (_termoBusca.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                _searchController.clear();
                              },
                              child: const Text('Limpar busca'),
                            ),
                        ],
                      ),
                    );
                  }
                }

                // Constrói a ListView
                // MELHORIA: Corrigi a definição dos paddings que estava incompleta
                final listPadding = const EdgeInsets.fromLTRB(
                    _pagePaddingHorizontal,
                    _pagePaddingVertical,
                    _pagePaddingHorizontal,
                    _pagePaddingVertical);

                return ListView.builder(
                  padding: listPadding,
                  itemCount: filteredList.length,
                  cacheExtent: 500, // Opcional: Cache para listas longas
                  itemBuilder: (context, index) {
                    final incidentType = filteredList[index];
                    // Opcional: Mostrar um card diferente se houve erro na conversão
                    // if (errorDocIds.contains(incidentType.id)) {
                    //   return Card(/* Card de erro */);
                    // }
                    // Usa o card modificado que agora tem o menu de exclusão
                    return _buildIncidentTypeCard(incidentType);
                  },
                );
              },
            ),
          ),
        ],
      ),
      // --- FloatingActionButton (Mantido) ---
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Novo Tipo'),
        onPressed: () => _navigateToCriarEditar(),
        tooltip: 'Adicionar Novo Tipo de Ocorrência',
        elevation: 4,
      ),
    );
  }
}
