// lib/core/constants/app_dimensions.dart

import 'package:flutter/material.dart';

/// Constantes de dimensões utilizadas em todo o aplicativo
///
/// Centraliza todos os espaçamentos, tamanhos e dimensões
/// para manter a consistência visual e facilitar adaptação
/// para diferentes tamanhos de tela.
class AppDimensions {
  // Espaçamentos
  static const formItemSpacing = 16.0;
  static const largeSpacing = 24.0;
  static const buttonSpacing = 12.0;
  static const bottomSpacing = 20.0;
  static const smallSpacing = 8.0;

  // Tamanhos fixos
  static const buttonHeight = 48.0;
  static const loadingIndicatorSize = 24.0;
  static const iconSize = 24.0;
  static const smallIconSize = 18.0;
  static const largeIconSize = 32.0;
  static const avatarSize = 40.0;

  // Bordas
  static const borderRadius = 8.0;
  static const cardBorderRadius = 12.0;

  // Espessuras
  static const borderWidth = 1.0;
  static const dividerThickness = 1.0;

  // Paddings pré-definidos
  static const padding = EdgeInsets.all(16.0);
  static const smallPadding = EdgeInsets.all(8.0);
  static const largePadding = EdgeInsets.all(24.0);
  static const horizontalPadding = EdgeInsets.symmetric(horizontal: 16.0);
  static const verticalPadding = EdgeInsets.symmetric(vertical: 16.0);

  // Tamanhos de texto
  static const titleFontSize = 20.0;
  static const subtitleFontSize = 16.0;
  static const bodyFontSize = 14.0;
  static const smallFontSize = 12.0;

  // Alturas de linha
  static const defaultLineHeight = 1.2;
}
