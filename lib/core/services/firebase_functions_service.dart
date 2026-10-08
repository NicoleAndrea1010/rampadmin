import 'package:cloud_functions/cloud_functions.dart';

class FirebaseFunctionsService {
  FirebaseFunctionsService(this._functions);
  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final result = await _functions
        .httpsCallable(name)
        .call<Map<String, dynamic>>(data);
    return result.data;
  }
}
