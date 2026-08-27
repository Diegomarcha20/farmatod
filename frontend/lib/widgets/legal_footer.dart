import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';

/// Aviso legal que debe acompañar cualquier pantalla que muestre
/// resultados de búsqueda o información médica.
class LegalFooter extends StatelessWidget {
  const LegalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Text(
        'Herramienta informativa de aprendizaje. Requiere validación '
        'farmacéutica al dispensar.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          height: 1.4,
          fontStyle: FontStyle.italic,
          color: AppColors.primary.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}
