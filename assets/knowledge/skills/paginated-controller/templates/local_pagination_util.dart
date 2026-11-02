/// Infers whether another page exists from page fullness: a full page means probably yes, a short
/// page means the end. No server `total` is needed.
class LocalPaginationUtil {
  /// Creates the util.
  const LocalPaginationUtil();

  /// The next page to request: [page] + 1 after a full page, [page] after a short one.
  int checkIsListHasMorePageInt({
    required List<Object?> list,
    required int page,
    required int limitInPage,
  }) => list.length >= limitInPage ? page + 1 : page;

  /// Whether another page probably exists.
  bool checkIsListHasMorePageBool({required List<Object?> list, required int limitInPage}) =>
      list.length >= limitInPage;
}
