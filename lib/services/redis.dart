import 'package:peaceful_partner/auth/secrets.dart';
import 'package:redis/redis.dart';

// export a function that returns a Future<Command> that is the connection
// to the redis server
Future<Command> getRedisCommand() async {
  try {
    final redis = RedisConnection();
    Command command = await redis.connect(redisHostname, redisPortnum);
    await command.send_object(['AUTH', 'default', redisKey]);
    return command;
  } on Exception catch (e) {
    print("WE GOT AN EXCEPTION $e");
    rethrow;
  }
}
