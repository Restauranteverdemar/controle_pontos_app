// lib/shared/models/point_occurrence.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Para @immutable

/// Status possíveis para uma ocorrência de pontuação.
///
/// Gerencia os diferentes estados que uma ocorrência pode ter
/// durante seu ciclo de vida no sistema.
enum OccurrenceStatus {
  Pendente,
  Aprovada,
  Reprovada;

  /// Converte uma string vinda do Firestore para o enum [OccurrenceStatus].
  ///
  /// Realiza comparação case-insensitive e retorna [OccurrenceStatus.Pendente]
  /// como padrão para valores nulos ou desconhecidos.
  static OccurrenceStatus fromString(String? statusString) {
    if (statusString == null) return OccurrenceStatus.Pendente;

    // Normaliza a string para minúsculas para comparação segura
    final normalizedStatus = statusString.toLowerCase();

    // Usa um switch expression (Dart 3+) para mapeamento conciso
    return switch (normalizedStatus) {
      'aprovada' => OccurrenceStatus.Aprovada,
      'reprovada' => OccurrenceStatus.Reprovada,
      // Caso padrão inclui 'pendente' e qualquer outro valor inesperado
      _ => OccurrenceStatus.Pendente,
    };
  }

  /// Retorna a representação em string do nome do enum.
  ///
  /// Usado para armazenar o status como string no Firestore.
  /// A propriedade `.name` é a forma padrão e recomendada no Dart moderno.
  String toJsonString() {
    return name;
  }

  /// Retorna um valor legível para exibição na interface do usuário.
  String get displayValue {
    return switch (this) {
      OccurrenceStatus.Pendente => 'Pendente',
      OccurrenceStatus.Aprovada => 'Aprovada',
      OccurrenceStatus.Reprovada => 'Reprovada',
    };
  }
}

/// Representa uma ocorrência de pontuação registrada para um funcionário.
///
/// Esta classe imutável (@immutable) contém todos os dados relacionados a um evento
/// que pode resultar em ajuste na pontuação de um funcionário, após passar
/// por um processo de aprovação/reprovação. Inclui um [periodId] para marcar
/// ocorrências pertencentes a períodos mensais fechados.
@immutable
class PointOccurrence {
  /// Identificador único da ocorrência no Firestore.
  final String id;

  /// ID do funcionário (usuário) a quem a ocorrência se refere.
  final String userId;

  /// Nome do funcionário no momento do registro (denormalizado).
  /// Facilita a exibição sem requerer busca adicional.
  final String employeeName;

  /// ID do tipo de incidente/ocorrência selecionado.
  final String incidentTypeId;

  /// Nome do tipo de incidente/ocorrência no momento do registro (denormalizado).
  final String incidentName;

  /// Data e hora em que o fato que gerou a ocorrência aconteceu.
  /// Definido pelo administrador no momento do registro.
  final Timestamp occurrenceDate;

  /// ID do usuário (administrador) que registrou a ocorrência.
  final String registeredBy;

  /// Nome do administrador que registrou (denormalizado).
  final String registeredByName;

  /// Data e hora em que a ocorrência foi registrada no sistema (timestamp do Firestore).
  /// Pode ser diferente de [occurrenceDate]. Geralmente definido pelo servidor.
  final Timestamp registeredAt; // Renomeado de timestamp para clareza

  /// Status atual do fluxo da ocorrência (Pendente, Aprovada, Reprovada).
  final OccurrenceStatus status;

  /// Pontuação padrão associada ao [incidentTypeId] no momento do registro.
  final int defaultPoints;

  /// Ajuste manual de pontos feito pelo administrador (opcional).
  /// Pode ser positivo ou negativo para modificar [defaultPoints].
  final int? manualPointsAdjustment;

  /// Pontuação final que será aplicada ao saldo do funcionário se aprovada.
  /// Calculada como `defaultPoints + (manualPointsAdjustment ?? 0)`.
  final int finalPoints;

  /// Observações, justificativas ou detalhes adicionais sobre a ocorrência (opcional).
  final String? notes;

  /// ID do usuário (administrador) que realizou a última ação de aprovação ou reprovação (opcional).
  final String? approvedRejectedBy;

  /// Nome do administrador que aprovou/reprovou (denormalizado, opcional).
  final String? approvedRejectedByName;

  /// Data e hora da última ação de aprovação/reprovação (opcional).
  final Timestamp? approvedRejectedAt;

  /// URL para um arquivo anexado (imagem/comprovante) no Firebase Storage (opcional).
  final String? attachmentUrl;

  /// Identificador do período mensal ao qual esta ocorrência pertence após o reset.
  /// Formato: "YYYY-MM" (ex: "2025-03").
  /// É `null` para ocorrências do período atual (antes do reset mensal).
  /// Preenchido pela função de reset mensal para marcar ocorrências do período fechado.
  final String? periodId;

  /// Cria uma nova instância imutável de [PointOccurrence].
  ///
  /// Todos os parâmetros obrigatórios devem ser fornecidos.
  /// [periodId] é opcional e definido explicitamente como null por padrão na criação inicial.
  const PointOccurrence({
    required this.id,
    required this.userId,
    required this.employeeName,
    required this.incidentTypeId,
    required this.incidentName,
    required this.occurrenceDate,
    required this.registeredBy,
    required this.registeredByName,
    required this.registeredAt,
    required this.status,
    required this.defaultPoints,
    this.manualPointsAdjustment,
    required this.finalPoints, // Obrigatório pois sempre será calculado ou fornecido
    this.notes,
    this.approvedRejectedBy,
    this.approvedRejectedByName,
    this.approvedRejectedAt,
    this.attachmentUrl,
    this.periodId =
        null, // Valor padrão explícito como null para novas ocorrências
  });

  /// Cria uma instância de [PointOccurrence] a partir de um ID de documento
  /// e um mapa de dados (JSON) vindo do Firestore.
  ///
  /// Realiza validações básicas e atribui valores padrão seguros para campos
  /// que possam estar ausentes ou com tipos incorretos no banco de dados.
  factory PointOccurrence.fromJson(String id, Map<String, dynamic> json) {
    // Extração segura de campos numéricos
    final defaultPts = (json['defaultPoints'] as num?)?.toInt() ?? 0;
    final manualPts = (json['manualPointsAdjustment'] as num?)?.toInt();

    // Cálculo dos pontos finais: usa valor do JSON se existir, senão calcula.
    final finalPts = (json['finalPoints'] as num?)?.toInt() ??
        (defaultPts + (manualPts ?? 0));

    // Extração segura de timestamps, com fallback para Timestamp.now()
    // Atenção: Usar Timestamp.now() pode mascarar problemas se o campo for obrigatório.
    // Considere lançar um erro ou usar um valor nulo se fizer mais sentido.
    final occurrenceTs =
        json['occurrenceDate'] as Timestamp? ?? Timestamp.now();
    final registeredTs = json['registeredAt'] as Timestamp? ?? Timestamp.now();
    final approvedRejectedTs =
        json['approvedRejectedAt'] as Timestamp?; // Nullable é ok

    return PointOccurrence(
      id: id, // ID vem do documento, não do mapa de dados
      userId:
          json['userId'] as String? ?? '', // Fornecer default ou lançar erro
      employeeName:
          json['employeeName'] as String? ?? 'Funcionário Desconhecido',
      incidentTypeId: json['incidentTypeId'] as String? ?? '',
      incidentName: json['incidentName'] as String? ?? 'Tipo Desconhecido',
      occurrenceDate: occurrenceTs,
      registeredBy: json['registeredBy'] as String? ?? '',
      registeredByName:
          json['registeredByName'] as String? ?? 'Admin Desconhecido',
      registeredAt: registeredTs,
      status: OccurrenceStatus.fromString(
          json['status'] as String?), // Usa o helper do Enum
      defaultPoints: defaultPts,
      manualPointsAdjustment: manualPts, // Nullable é ok
      finalPoints: finalPts,
      notes: json['notes'] as String?, // Nullable é ok
      approvedRejectedBy:
          json['approvedRejectedBy'] as String?, // Nullable é ok
      approvedRejectedByName:
          json['approvedRejectedByName'] as String?, // Nullable é ok
      approvedRejectedAt: approvedRejectedTs, // Nullable é ok
      attachmentUrl: json['attachmentUrl'] as String?, // Nullable é ok
      periodId:
          json['periodId'] as String?, // Leitura do campo periodId (nullable)
    );
  }

  /// Converte a instância [PointOccurrence] para um mapa (JSON)
  /// para ser armazenado no Firestore.
  ///
  /// Campos opcionais (`String?`, `int?`, `Timestamp?`) só são incluídos
  /// no mapa se não forem nulos. Campos `String?` vazios também são omitidos.
  /// O campo `registeredAt` deve ser idealmente definido pelo servidor
  /// (`FieldValue.serverTimestamp()`) ao *criar* o documento, não aqui.
  /// Este método é útil para *atualizações* ou se a criação for feita
  /// inteiramente pelo cliente.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'userId': userId,
      'employeeName': employeeName,
      'incidentTypeId': incidentTypeId,
      'incidentName': incidentName,
      'occurrenceDate': occurrenceDate, // Data do fato
      'registeredBy': registeredBy,
      'registeredByName': registeredByName,
      // 'registeredAt': registeredAt, // Geralmente não incluído aqui, usar serverTimestamp na escrita inicial
      'status':
          status.toJsonString(), // Usa o método do enum para obter a string
      'defaultPoints': defaultPoints,
      'finalPoints': finalPoints, // Sempre incluir pontos finais
    };

    // Adiciona campos opcionais apenas se tiverem valor
    if (manualPointsAdjustment != null) {
      data['manualPointsAdjustment'] = manualPointsAdjustment;
    }
    if (notes != null && notes!.isNotEmpty) {
      data['notes'] = notes;
    }
    if (approvedRejectedBy != null) {
      data['approvedRejectedBy'] = approvedRejectedBy;
    }
    if (approvedRejectedByName != null) {
      data['approvedRejectedByName'] = approvedRejectedByName;
    }
    if (approvedRejectedAt != null) {
      data['approvedRejectedAt'] = approvedRejectedAt;
    }
    if (attachmentUrl != null) {
      data['attachmentUrl'] = attachmentUrl;
    }
    // Campo periodId é incluído apenas se não for nulo
    // Esta lógica já existe no código original e está correta
    if (periodId != null) {
      data['periodId'] = periodId;
    }

    return data;
  }

  /// Cria uma cópia desta instância [PointOccurrence] com a possibilidade
  /// de substituir valores de campos específicos.
  ///
  /// Útil para atualizações imutáveis do estado.
  /// Os flags `clearX` permitem definir explicitamente um campo opcional como nulo.
  /// Os `finalPoints` são recalculados automaticamente com base nos novos
  /// `defaultPoints` e `manualPointsAdjustment`, a menos que um novo valor
  /// `finalPoints` seja fornecido diretamente.
  PointOccurrence copyWith({
    String? id,
    String? userId,
    String? employeeName,
    String? incidentTypeId,
    String? incidentName,
    Timestamp? occurrenceDate,
    String? registeredBy,
    String? registeredByName,
    Timestamp? registeredAt,
    OccurrenceStatus? status,
    int? defaultPoints,
    int? manualPointsAdjustment,
    bool clearManualPointsAdjustment = false, // Flag para limpar explicitamente
    int? finalPoints, // Permite sobrescrever o cálculo automático
    String? notes,
    bool clearNotes = false, // Flag para limpar
    String? approvedRejectedBy,
    bool clearApprovedRejectedBy = false, // Flag para limpar
    String? approvedRejectedByName,
    bool clearApprovedRejectedByName = false, // Flag para limpar
    Timestamp? approvedRejectedAt,
    bool clearApprovedRejectedAt = false, // Flag para limpar
    String? attachmentUrl,
    bool clearAttachmentUrl = false, // Flag para limpar
    String? periodId,
    bool clearPeriodId = false, // Flag para limpar (definir como null)
  }) {
    // Determina os valores efetivos considerando os novos valores e os flags 'clear'
    final effectiveDefaultPoints = defaultPoints ?? this.defaultPoints;
    final effectiveManualAdjustment = clearManualPointsAdjustment
        ? null // Se clear for true, define como null
        : (manualPointsAdjustment ??
            this.manualPointsAdjustment); // Senão, usa novo ou antigo

    // Recalcula os pontos finais se não foram explicitamente fornecidos
    final calculatedFinalPoints =
        effectiveDefaultPoints + (effectiveManualAdjustment ?? 0);

    return PointOccurrence(
      // Usa o novo valor se fornecido, senão mantém o valor atual ('this')
      id: id ?? this.id,
      userId: userId ?? this.userId,
      employeeName: employeeName ?? this.employeeName,
      incidentTypeId: incidentTypeId ?? this.incidentTypeId,
      incidentName: incidentName ?? this.incidentName,
      occurrenceDate: occurrenceDate ?? this.occurrenceDate,
      registeredBy: registeredBy ?? this.registeredBy,
      registeredByName: registeredByName ?? this.registeredByName,
      registeredAt: registeredAt ?? this.registeredAt,
      status: status ?? this.status,
      defaultPoints: effectiveDefaultPoints,
      manualPointsAdjustment: effectiveManualAdjustment,
      // Usa 'finalPoints' fornecido, ou o valor recalculado
      finalPoints: finalPoints ?? calculatedFinalPoints,
      notes: clearNotes ? null : (notes ?? this.notes),
      approvedRejectedBy: clearApprovedRejectedBy
          ? null
          : (approvedRejectedBy ?? this.approvedRejectedBy),
      approvedRejectedByName: clearApprovedRejectedByName
          ? null
          : (approvedRejectedByName ?? this.approvedRejectedByName),
      approvedRejectedAt: clearApprovedRejectedAt
          ? null
          : (approvedRejectedAt ?? this.approvedRejectedAt),
      attachmentUrl:
          clearAttachmentUrl ? null : (attachmentUrl ?? this.attachmentUrl),
      periodId: clearPeriodId
          ? null
          : (periodId ?? this.periodId), // Lógica para periodId
    );
  }

  /// Retorna uma representação textual concisa da ocorrência para depuração.
  @override
  String toString() {
    final dateStr = occurrenceDate
        .toDate()
        .toIso8601String()
        .substring(0, 16); // Formato YYYY-MM-DDTHH:mm
    final attachmentInfo = attachmentUrl != null ? ', attachment: present' : '';
    final periodInfo = periodId != null
        ? ', period: $periodId'
        : ''; // Adiciona info do período se existir
    return 'PointOccurrence(id: $id, user: $employeeName ($userId), incident: $incidentName, '
        'status: ${status.name}, points: $finalPoints, date: $dateStr$attachmentInfo$periodInfo)'; // Inclui periodInfo
  }

  /// Compara esta instância com outro objeto para igualdade.
  /// Considera todos os campos da classe.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PointOccurrence &&
        other.id == id &&
        other.userId == userId &&
        other.employeeName == employeeName &&
        other.incidentTypeId == incidentTypeId &&
        other.incidentName == incidentName &&
        other.occurrenceDate == occurrenceDate &&
        other.registeredBy == registeredBy &&
        other.registeredByName == registeredByName &&
        other.registeredAt == registeredAt &&
        other.status == status &&
        other.defaultPoints == defaultPoints &&
        other.manualPointsAdjustment == manualPointsAdjustment &&
        other.finalPoints == finalPoints &&
        other.notes == notes &&
        other.approvedRejectedBy == approvedRejectedBy &&
        other.approvedRejectedByName == approvedRejectedByName &&
        other.approvedRejectedAt == approvedRejectedAt &&
        other.attachmentUrl == attachmentUrl &&
        other.periodId == periodId; // Comparar periodId
  }

  /// Calcula o código hash para esta instância baseado em todos os seus campos.
  /// Necessário ao sobrescrever o operador `==`.
  @override
  int get hashCode {
    return Object.hash(
      id,
      userId,
      employeeName,
      incidentTypeId,
      incidentName,
      occurrenceDate,
      registeredBy,
      registeredByName,
      registeredAt,
      status,
      defaultPoints,
      manualPointsAdjustment,
      finalPoints,
      notes,
      approvedRejectedBy,
      approvedRejectedByName,
      approvedRejectedAt,
      attachmentUrl,
      periodId, // Incluir periodId no hash
    );
  }
}
