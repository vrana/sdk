// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analysis_server/protocol/protocol.dart';
import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analysis_server/src/handler/legacy/legacy_handler.dart';
import 'package:analysis_server/src/legacy_analysis_server.dart';
import 'package:analysis_server/src/plugin/result_merger.dart';
import 'package:analysis_server/src/request_handler_mixin.dart';
import 'package:analysis_server/src/services/kythe/kythe_visitors.dart';
import 'package:analyzer/src/dart/element/inheritance_manager3.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as plugin;

/// The handler for the `kythe.getKytheEntries` request.
class KytheGetKytheEntriesHandler extends LegacyHandler
    with RequestHandlerMixin<LegacyAnalysisServer> {
  /// Initialize a newly created handler to be able to service requests for the
  /// [server].
  KytheGetKytheEntriesHandler(
      super.server, super.request, super.cancellationToken);

  @override
  Future<void> handle() async {
    var file = KytheGetKytheEntriesParams.fromRequest(request).file;
    var driver = server.getAnalysisDriver(file);
    if (driver == null) {
      sendResponse(Response.getKytheEntriesInvalidFile(request));
    } else {
      //
      // Allow plugins to start computing entries.
      //
      var requestParams = plugin.KytheGetKytheEntriesParams(file);
      var pluginFutures = server.pluginManager.broadcastRequest(
        requestParams,
        contextRoot: driver.analysisContext!.contextRoot,
      );
      //
      // Compute entries generated by server.
      //
      var allResults = <KytheGetKytheEntriesResult>[];
      var result = await server.getResolvedUnit(file);
      if (result != null) {
        var entries = <KytheEntry>[];
        // TODO(brianwilkerson) Figure out how to get the list of files.
        var files = <String>[];
        result.unit.accept(KytheDartVisitor(server.resourceProvider, entries,
            file, InheritanceManager3(), result.content));
        allResults.add(KytheGetKytheEntriesResult(entries, files));
      }
      //
      // Add the entries produced by plugins to the server-generated entries.
      //
      var responses = await waitForResponses(pluginFutures,
          requestParameters: requestParams);
      for (var response in responses) {
        var result = plugin.KytheGetKytheEntriesResult.fromResponse(response);
        allResults
            .add(KytheGetKytheEntriesResult(result.entries, result.files));
      }
      //
      // Return the result.
      //
      var merger = ResultMerger();
      var mergedResults = merger.mergeKytheEntries(allResults);
      sendResult(KytheGetKytheEntriesResult(
          mergedResults.entries, mergedResults.files));
    }
  }
}
