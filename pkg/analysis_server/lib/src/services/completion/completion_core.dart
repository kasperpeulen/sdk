// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library analysis_server.src.services.completion.completion_core;

import 'package:analysis_server/src/provisional/completion/completion_core.dart';
import 'package:analysis_server/src/services/search/search_engine.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/source.dart';

/**
 * The information about a requested list of completions.
 */
class CompletionRequestImpl implements CompletionRequest {
  @override
  final AnalysisContext context;

  @override
  final Source source;

  @override
  final int offset;

  @override
  final ResourceProvider resourceProvider;

  @override
  final SearchEngine searchEngine;

  /**
   * Initialize a newly created completion request based on the given arguments.
   */
  CompletionRequestImpl(this.context, this.resourceProvider, this.searchEngine,
      this.source, this.offset);
}
