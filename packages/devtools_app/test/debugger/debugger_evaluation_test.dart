// Copyright 2021 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:devtools_app/src/screens/debugger/breakpoint_manager.dart';
import 'package:devtools_app/src/screens/debugger/debugger_controller.dart';
import 'package:devtools_app/src/shared/console/eval/eval_service.dart';
import 'package:devtools_app/src/shared/console/widgets/evaluate.dart';
import 'package:devtools_app/src/shared/eval_on_dart_library.dart';
import 'package:devtools_app/src/shared/globals.dart';
import 'package:devtools_app/src/shared/primitives/storage.dart';
import 'package:devtools_app/src/shared/primitives/utils.dart';
import 'package:devtools_app/src/shared/ui/search.dart';
import 'package:devtools_test/devtools_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_infra/flutter_test_driver.dart';
import '../test_infra/flutter_test_environment.dart';
import '../test_infra/flutter_test_storage.dart';

void main() {
  setGlobal(Storage, FlutterTestStorage());

  final FlutterTestEnvironment env = FlutterTestEnvironment(
    const FlutterRunConfiguration(withDebugger: true),
  );

  late Disposable isAlive;
  late DebuggerController debuggerController;
  late EvalOnDartLibrary eval;

  setUp(() async {
    setGlobal(BreakpointManager, BreakpointManager());
    setGlobal(EvalService, EvalService());
    isAlive = Disposable();
    await env.setupEnvironment();
    debuggerController = DebuggerController();

    eval = EvalOnDartLibrary(
      'package:flutter_app/src/autocomplete.dart',
      serviceManager.service!,
      disableBreakpoints: false,
    );
  });

  tearDown(() async {
    await debuggerController.resume();
    isAlive.dispose();
    debuggerController.dispose();
    await env.tearDownEnvironment();
  });

  tearDownAll(() async {
    await env.tearDownEnvironment(force: true);
  });

  Future<void> runMethodAndWaitForPause(String method) async {
    unawaited(eval.eval(method, isAlive: isAlive));

    await whenMatches(debuggerController.selectedStackFrame, (f) => f != null);
  }

  group(
    'EvalOnDartLibrary',
    () {
      test(
        'returns scoped variables when EditingParts is not a field',
        () async {
          await runMethodAndWaitForPause(
            'AnotherClass().pauseWithScopedVariablesMethod()',
          );
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: 'foo',
                leftSide: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals(['foo', 'foobar']),
          );
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: 'b',
                leftSide: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals(['bar', 'baz']),
          );
        },
        timeout: const Timeout.factor(8),
      );

      test(
        'returns filtered members when EditingParts is a field ',
        () async {
          await runMethodAndWaitForPause(
            'AnotherClass().pauseWithScopedVariablesMethod()',
          );
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: 'f',
                leftSide: 'foo.',
                rightSide: '',
              ),
              evalService,
            ),
            equals(['field1', 'field2', 'func1', 'func2']),
          );
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: 'fu',
                leftSide: 'foo.',
                rightSide: '',
              ),
              evalService,
            ),
            equals(['func1', 'func2']),
          );
        },
        timeout: const Timeout.factor(8),
      );

      test(
        'returns filtered members when EditingParts is a class name ',
        () async {
          await runMethodAndWaitForPause(
            'AnotherClass().pauseWithScopedVariablesMethod()',
          );
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                leftSide: 'FooClass.',
                activeWord: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals([
              'staticField1',
              'staticField2',
              'namedConstructor',
              'factory1',
              'staticMethod',
            ]),
          );
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: 'fa',
                leftSide: 'FooClass.',
                rightSide: '',
              ),
              evalService,
            ),
            equals(['factory1']),
          );
        },
        timeout: const Timeout.factor(8),
      );
      test(
        'returns privates only from library',
        () async {
          await runMethodAndWaitForPause(
            'AnotherClass().pauseWithScopedVariablesMethod()',
          );
          expect(
            collectionEquals(
              await autoCompleteResultsFor(
                EditingParts(
                  activeWord: '_',
                  leftSide: '',
                  rightSide: '',
                ),
                evalService,
              ),
              [
                '_privateField2',
                '_privateField1',
                '_PrivateClass',
              ],
              ordered: false,
            ),
            isTrue,
          );
        },
        timeout: const Timeout.factor(8),
      );
      test(
        'returns exported members from import',
        () async {
          await runMethodAndWaitForPause(
            'AnotherClass().pauseWithScopedVariablesMethod()',
          );
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: 'exportedField',
                leftSide: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals([
              'exportedField',
            ]),
          );

          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: 'ExportedClass',
                leftSide: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals([
              'ExportedClass',
            ]),
          );

          // Privates are not exported
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: '_privateExportedField',
                leftSide: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals([]),
          );

          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: '_PrivateExportedClass',
                leftSide: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals([]),
          );
        },
        timeout: const Timeout.factor(8),
      );

      test(
        'returns prefixes of libraries imported',
        () async {
          await runMethodAndWaitForPause(
            'AnotherClass().pauseWithScopedVariablesMethod()',
          );
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: 'developer',
                leftSide: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals([
              'developer',
            ]),
          );

          expect(
            await autoCompleteResultsFor(
              EditingParts(
                activeWord: 'math',
                leftSide: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals([
              'math',
            ]),
          );
        },
        timeout: const Timeout.factor(8),
      );

      test(
        'returns no operators for int',
        () async {
          await runMethodAndWaitForPause(
            'AnotherClass().pauseWithScopedVariablesMethod()',
          );
          expect(
            await autoCompleteResultsFor(
              EditingParts(
                leftSide: '7.',
                activeWord: '',
                rightSide: '',
              ),
              evalService,
            ),
            equals(
              [
                'hashCode',
                'bitLength',
                'toString',
                'remainder',
                'abs',
                'sign',
                'isEven',
                'isOdd',
                'isNaN',
                'isNegative',
                'isInfinite',
                'isFinite',
                'toUnsigned',
                'toSigned',
                'compareTo',
                'round',
                'floor',
                'ceil',
                'truncate',
                'roundToDouble',
                'floorToDouble',
                'ceilToDouble',
                'truncateToDouble',
                'clamp',
                'toInt',
                'toDouble',
                'toStringAsFixed',
                'toStringAsExponential',
                'toStringAsPrecision',
                'toRadixString',
                'modPow',
                'modInverse',
                'gcd',
                'noSuchMethod',
                'runtimeType',
              ],
            ),
          );
        },
        timeout: const Timeout.factor(8),
      );
    },
  );
}
