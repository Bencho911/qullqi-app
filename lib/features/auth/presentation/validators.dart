/// Validaciones de los formularios de acceso. Devuelven el mensaje para la
/// persona, o `null` si está bien.
abstract final class Validate {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  static String? name(String v) => v.trim().split(RegExp(r'\s+')).length < 2
      ? 'Escribe tu nombre y tu apellido.'
      : null;

  static String? email(String v) {
    if (v.trim().isEmpty) return 'Escribe tu correo.';
    if (!_email.hasMatch(v.trim())) {
      return 'Revisa el correo: le falta algo como @correo.com.';
    }
    return null;
  }

  static String? password(String v) =>
      v.length < 8 ? 'Usa al menos 8 caracteres.' : null;

  /// Celular colombiano: 10 dígitos que empiezan por 3.
  static String? phone(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10 || !digits.startsWith('3')) {
      return 'Son 10 dígitos y empiezan por 3.';
    }
    return null;
  }

  /// "3105550142" → "310 555 0142".
  static String formatPhone(String v) {
    final d = v.replaceAll(RegExp(r'\D'), '');
    if (d.length != 10) return v;
    return '${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
  }
}

enum PasswordStrength {
  weak('Débil'),
  fair('Aceptable'),
  strong('Fuerte');

  PasswordStrength(this.label);

  final String label;

  static PasswordStrength of(String v) {
    var score = 0;
    if (v.length >= 8) score++;
    if (v.length >= 12) score++;
    if (RegExp('[A-Z]').hasMatch(v) && RegExp('[a-z]').hasMatch(v)) score++;
    if (RegExp(r'\d').hasMatch(v)) score++;
    if (RegExp('[^A-Za-z0-9]').hasMatch(v)) score++;
    return score >= 4
        ? PasswordStrength.strong
        : score >= 2
        ? PasswordStrength.fair
        : PasswordStrength.weak;
  }
}
