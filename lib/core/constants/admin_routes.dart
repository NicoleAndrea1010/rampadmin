abstract final class AdminRoutes {
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const landlords = '/landlords';
  static const operations = '/operations';
  static const landlordNew = '/landlords/new';
  static const landlordDetails = '/landlords/:uid';
  static String landlord(String uid) => '/landlords/$uid';
  static String landlordEdit(String uid) => '/landlords/$uid/edit';
  static const activity = '/activity';
  static const settings = '/settings';
}
