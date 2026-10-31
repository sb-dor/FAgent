/// Why a project name cannot be a package name.
enum PackageNameProblem {
  /// Nothing is typed.
  empty,

  /// Not lowercase letters, digits and underscores, or it starts with a digit.
  invalid,

  /// A Dart keyword.
  keyword,

  /// The name of a package the new project depends on.
  dependency,
}

final RegExp _identifier = RegExp(r'^[a-z_][a-z0-9_]*$');

/// The words `flutter create` refuses as a package name (`create_base.dart`).
const Set<String> _keywords = <String>{
  'abstract',
  'as',
  'assert',
  'async',
  'await',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'covariant',
  'default',
  'deferred',
  'do',
  'dynamic',
  'else',
  'enum',
  'export',
  'extends',
  'extension',
  'external',
  'factory',
  'false',
  'final',
  'finally',
  'for',
  'function',
  'get',
  'hide',
  'if',
  'implements',
  'import',
  'in',
  'inout',
  'interface',
  'is',
  'late',
  'library',
  'mixin',
  'native',
  'new',
  'null',
  'of',
  'on',
  'operator',
  'out',
  'part',
  'patch',
  'required',
  'rethrow',
  'return',
  'set',
  'show',
  'source',
  'static',
  'super',
  'switch',
  'sync',
  'this',
  'throw',
  'true',
  'try',
  'typedef',
  'var',
  'void',
  'while',
  'with',
  'yield',
};

/// The packages a new Flutter project depends on, so it cannot share their name.
const Set<String> _packageDependencies = <String>{'collection', 'flutter', 'flutter_test', 'meta'};

/// Checks [name] the way `flutter create` does; `null` when it is a valid package name.
PackageNameProblem? checkPackageName(String name) {
  if (name.isEmpty) return PackageNameProblem.empty;
  if (!_identifier.hasMatch(name)) return PackageNameProblem.invalid;
  if (_keywords.contains(name)) return PackageNameProblem.keyword;
  if (_packageDependencies.contains(name)) return PackageNameProblem.dependency;
  return null;
}

/// A valid package name close to [name]: lowercase, `-` and spaces as `_`, a `_` before a leading
/// digit, other characters dropped. `null` when no letter or digit is left or the result is
/// still not a valid name.
String? suggestPackageName(String name) {
  var suggestion = name.toLowerCase().replaceAll(RegExp(r'[-\s]'), '_');
  if (suggestion.startsWith(RegExp('[0-9]'))) suggestion = '_$suggestion';
  suggestion = suggestion.replaceAll(RegExp('[^a-z0-9_]'), '');
  if (!suggestion.contains(RegExp('[a-z0-9]'))) return null;
  return checkPackageName(suggestion) == null ? suggestion : null;
}
