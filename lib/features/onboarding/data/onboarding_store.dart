import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-launch steps of App Flow F0, each shown once per device.
enum OnboardingStep { language, intro }

/// Which steps this device has finished. Reads are synchronous so the first
/// redirect already knows where to go.
abstract interface class OnboardingStore {
  bool isDone(OnboardingStep step);
  Future<void> markDone(OnboardingStep step);
}

/// Device storage. Overridden in `main.dart` with a loaded instance.
class SharedPrefsOnboardingStore implements OnboardingStore {
  SharedPrefsOnboardingStore(this._prefs);

  static String keyFor(OnboardingStep step) => 'onboarding.${step.name}';
  final SharedPreferences _prefs;

  @override
  bool isDone(OnboardingStep step) => _prefs.getBool(keyFor(step)) ?? false;

  @override
  Future<void> markDone(OnboardingStep step) =>
      _prefs.setBool(keyFor(step), true);
}

/// Keeps progress for this run only (tests, and before `main` overrides).
class MemoryOnboardingStore implements OnboardingStore {
  MemoryOnboardingStore([Iterable<OnboardingStep> done = const []])
    : _done = {...done};

  /// A device that has already been through onboarding.
  MemoryOnboardingStore.done() : _done = {...OnboardingStep.values};

  final Set<OnboardingStep> _done;

  @override
  bool isDone(OnboardingStep step) => _done.contains(step);

  @override
  Future<void> markDone(OnboardingStep step) async => _done.add(step);
}

final onboardingStoreProvider = Provider<OnboardingStore>(
  (ref) => MemoryOnboardingStore(),
);

/// Steps finished on this device; the router moves on when this changes.
class OnboardingProgress extends Notifier<Set<OnboardingStep>> {
  @override
  Set<OnboardingStep> build() {
    final store = ref.watch(onboardingStoreProvider);
    return {
      for (final step in OnboardingStep.values)
        if (store.isDone(step)) step,
    };
  }

  Future<void> complete(OnboardingStep step) async {
    state = {...state, step};
    await ref.read(onboardingStoreProvider).markDone(step);
  }
}

final onboardingProgressProvider =
    NotifierProvider<OnboardingProgress, Set<OnboardingStep>>(
      OnboardingProgress.new,
    );
