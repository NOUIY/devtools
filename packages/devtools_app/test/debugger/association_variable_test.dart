// Copyright 2020 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:devtools_app/src/service/service_manager.dart';
import 'package:devtools_app/src/shared/globals.dart';
import 'package:devtools_app/src/shared/object_tree.dart';
import 'package:devtools_test/devtools_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:vm_service/vm_service.dart';

const isolateId = '433';
const objectId = '123';

final libraryRef = LibraryRef(
  name: 'some library',
  uri: 'package:foo/foo.dart',
  id: 'lib-id-1',
);

void main() {
  late ServiceConnectionManager manager;

  setUp(() {
    final service = createMockVmServiceWrapperWithDefaults();

    manager = FakeServiceManager(service: service);
    setGlobal(ServiceConnectionManager, manager);
  });

  test(
    'Creates bound variables for Map with String key and Double value',
    () async {
      final instance = Instance(
        kind: InstanceKind.kMap,
        id: objectId,
        length: 2,
        associations: [
          MapAssociation(
            key: InstanceRef(
              id: '4',
              kind: InstanceKind.kString,
              valueAsString: 'Hey',
            ),
            value: InstanceRef(
              id: '5',
              kind: InstanceKind.kDouble,
              valueAsString: '12.34',
            ),
          ),
        ],
      );
      final isolateRef = IsolateRef(
        id: isolateId,
        number: '1',
        name: 'my-isolate',
        isSystemIsolate: false,
      );
      final variable = DartObjectNode.create(
        BoundVariable(
          name: 'test',
          value: instance,
        ),
        isolateRef,
      );
      when(manager.service!.getObject(isolateId, objectId, offset: 0, count: 2))
          .thenAnswer((_) async {
        return instance;
      });

      await buildVariablesTree(variable);

      expect(variable.children, [
        matchesVariable(name: 'Hey', value: '12.34'),
      ]);
    },
  );

  test(
    'Creates bound variables for Map with Int key and Double value',
    () async {
      final isolateRef = IsolateRef(
        id: isolateId,
        number: '1',
        name: 'my-isolate',
        isSystemIsolate: false,
      );
      final instance = Instance(
        kind: InstanceKind.kMap,
        id: objectId,
        length: 2,
        associations: [
          MapAssociation(
            key: InstanceRef(
              id: '4',
              kind: InstanceKind.kInt,
              valueAsString: '1',
            ),
            value: InstanceRef(
              id: '5',
              kind: InstanceKind.kDouble,
              valueAsString: '12.34',
            ),
          ),
        ],
      );
      final variable = DartObjectNode.create(
        BoundVariable(
          name: 'test',
          value: instance,
        ),
        isolateRef,
      );
      when(manager.service!.getObject(isolateId, objectId, offset: 0, count: 2))
          .thenAnswer((_) async {
        return instance;
      });

      await buildVariablesTree(variable);

      expect(variable.children, [
        matchesVariable(name: '1', value: '12.34'),
      ]);
    },
  );

  test(
    'Creates bound variables for Map with Object key and Double value',
    () async {
      final isolateRef = IsolateRef(
        id: isolateId,
        number: '1',
        name: 'my-isolate',
        isSystemIsolate: false,
      );
      final instance = Instance(
        kind: InstanceKind.kMap,
        id: objectId,
        length: 2,
        associations: [
          MapAssociation(
            key: InstanceRef(
              classRef: ClassRef(id: 'a', name: 'Foo', library: libraryRef),
              id: '4',
              kind: InstanceKind.kPlainInstance,
            ),
            value: InstanceRef(
              id: '5',
              kind: InstanceKind.kDouble,
              valueAsString: '12.34',
            ),
          ),
        ],
      );
      final variable = DartObjectNode.create(
        BoundVariable(
          name: 'test',
          value: instance,
        ),
        isolateRef,
      );
      when(manager.service!.getObject(isolateId, objectId, offset: 0, count: 2))
          .thenAnswer((_) async {
        return instance;
      });

      await buildVariablesTree(variable);

      expect(variable.children, [
        matchesVariable(name: null, value: '[Entry 0]'),
      ]);
      expect(variable.children.first.children, [
        matchesVariable(name: '[key]', value: 'Foo'),
        matchesVariable(name: '[value]', value: '12.34'),
      ]);
    },
  );
}

Matcher matchesVariable({
  required String? name,
  required Object value,
}) {
  return const TypeMatcher<DartObjectNode>()
      .having(
        (v) => v.displayValue,
        'displayValue',
        equals(value),
      )
      .having(
        (v) => v.name,
        'name',
        equals(name),
      );
}
