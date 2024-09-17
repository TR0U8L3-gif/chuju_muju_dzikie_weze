import 'dart:async';
import 'dart:io' as io;

const maxIterationsToRefreshToken = 3;

Future<void> main(List<String> arguments) async {
  io.stdin.echoMode = false;
  io.stdin.lineMode = false;

  StreamSubscription? subscription;
  final tokenManager = TokenManager();

  var iterationsToRefreshToken = 0;

  subscription = io.stdin.listen((List<int> codes) {
      if (codes.first == 0x08) {
        subscription?.cancel();
        return;
      }
      if(iterationsToRefreshToken == maxIterationsToRefreshToken) {
        tokenManager.refreshToken(codes);
        iterationsToRefreshToken = 0;
      }
      iterationsToRefreshToken++;
      
      printData(codes, iterationsToRefreshToken);
  });

  print('Start listening');


}

void printData(List<int> codes, iterationsToRefreshToken) {
  print('Codes: ${codes.toString()}, Iteration($iterationsToRefreshToken/$maxIterationsToRefreshToken)');
}

class TokenManager {
  static final TokenManager _instance = TokenManager._internal();

  factory TokenManager() {
    return _instance;
  }

  TokenManager._internal();

  var refreshTokenInstance = 0;

  Future<void> refreshToken(List<int> codes) async{
    refreshTokenInstance++;
    print('Refreshing token started, Codes: ${codes.toString()}, Instance: $refreshTokenInstance');
    await Future.delayed(Duration(seconds: 5));
    refreshTokenInstance--;
    print('Refreshing token finished, Codes: ${codes.toString()}, Instance: $refreshTokenInstance');
  }
}
