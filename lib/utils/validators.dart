class Validators {
  static String? validateFullName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your full name';
    }

    final trimmedValue = value.trim();
    
    // 1. Length Check (3-20)
    if (trimmedValue.length < 3 || trimmedValue.length > 20) {
      return 'Name must be 3–20 characters long';
    }

    // 4. Starting Character Check (Must start with letter)
    if (!RegExp(r'^[a-zA-Z]').hasMatch(trimmedValue)) {
      return 'Name must start with a letter';
    }

    // 2 & 3. Allowed/Disallowed Characters Check (Including spaces for full name)
    // The user rules didn't allow spaces, but for "Full Name" we usually need them.
    // However, the user said "strict", so I'll follow the rule exactly as provided.
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(trimmedValue)) {
      return 'Only letters, numbers, "." and "_" are allowed';
    }

    // 6. Consecutive Special Characters Check
    if (RegExp(r'[._]{2,}').hasMatch(trimmedValue)) {
      return 'Name cannot contain consecutive "." or "_"';
    }

    // 7. Leading/Trailing Special Characters Check
    if (trimmedValue.endsWith('.') || trimmedValue.endsWith('_')) {
      return 'Name cannot end with "." or "_"';
    }

    // 5. Numeric-only Check
    if (RegExp(r'^\d+$').hasMatch(trimmedValue)) {
      return 'Name cannot be only numbers';
    }

    // 8. Reserved Usernames Check
    const reserved = ['admin', 'root', 'system', 'support'];
    if (reserved.contains(trimmedValue.toLowerCase())) {
      return 'This name is reserved';
    }

    return null;
  }
}
