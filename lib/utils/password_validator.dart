/// 與後端 `validatePasswordStrength`（users.js）一致
String? validatePasswordStrength(String? password, {bool required = true}) {
  if (password == null || password.isEmpty) {
    return required ? '請輸入密碼' : null;
  }
  if (password.length < 8) {
    return '密碼長度至少 8 個字元';
  }
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return '密碼需包含至少一個大寫字母';
  }
  if (!RegExp(r'[a-z]').hasMatch(password)) {
    return '密碼需包含至少一個小寫字母';
  }
  if (!RegExp(r'[0-9]').hasMatch(password)) {
    return '密碼需包含至少一個數字';
  }
  return null;
}

const passwordStrengthHint =
    '至少 8 字元，需含大寫、小寫字母與數字';
