abstract interface class ClientClock {
  DateTime now();

  Future<void> delay(Duration duration);
}

class SystemClientClock implements ClientClock {
  const SystemClientClock();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);
}

class MutableClientClock implements ClientClock {
  MutableClientClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;

  @override
  Future<void> delay(Duration duration) async {
    value = value.add(duration);
  }
}
