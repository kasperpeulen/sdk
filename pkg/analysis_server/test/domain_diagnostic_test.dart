// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test.domain.diagnostic;

import 'package:analysis_server/plugin/protocol/protocol.dart';
import 'package:analysis_server/src/analysis_server.dart';
import 'package:analysis_server/src/domain_diagnostic.dart';
import 'package:analysis_server/src/plugin/server_plugin.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/instrumentation/instrumentation.dart';
import 'package:plugin/manager.dart';
import 'package:unittest/unittest.dart';

import 'mock_sdk.dart';
import 'mocks.dart';
import 'utils.dart';

main() {
  AnalysisServer server;
  DiagnosticDomainHandler handler;
  MemoryResourceProvider resourceProvider;

  initializeTestEnvironment();

  setUp(() {
    var serverChannel = new MockServerChannel();
    resourceProvider = new MemoryResourceProvider();
    ExtensionManager manager = new ExtensionManager();
    ServerPlugin serverPlugin = new ServerPlugin();
    manager.processPlugins([serverPlugin]);
    server = new AnalysisServer(
        serverChannel,
        resourceProvider,
        new MockPackageMapProvider(),
        null,
        serverPlugin,
        new AnalysisServerOptions(),
        new MockSdk(),
        InstrumentationService.NULL_SERVICE);
    handler = new DiagnosticDomainHandler(server);
  });

  tearDown(() {
    handler.sampler?.stop();
  });

  group('DiagnosticDomainHandler', () {
    test('getDiagnostics', () async {
      String file = '/project/bin/test.dart';
      resourceProvider.newFile('/project/pubspec.yaml', 'name: project');
      resourceProvider.newFile(file, 'main() {}');

      server.setAnalysisRoots('0', ['/project/'], [], {});

      await server.onAnalysisComplete;

      var request = new DiagnosticGetDiagnosticsParams().toRequest('0');
      var response = handler.handleRequest(request);

      int fileCount = MockSdk.LIBRARIES.length + 1 /* test.dart */;

      var json = response.toJson()[Response.RESULT];
      expect(json['contexts'], hasLength(1));
      var context = json['contexts'][0];
      expect(context['name'], '/project');
      expect(context['explicitFileCount'], fileCount);
      expect(context['implicitFileCount'], 0);
      expect(context['workItemQueueLength'], isNotNull);
      expect(context['workItemQueueLengthAverage'], isNotNull);
    });

    test('getDiagnostics - (no root)', () async {
      var request = new DiagnosticGetDiagnosticsParams().toRequest('0');
      var response = handler.handleRequest(request);
      var json = response.toJson()[Response.RESULT];
      expect(json['contexts'], hasLength(0));
    });
  });
}
