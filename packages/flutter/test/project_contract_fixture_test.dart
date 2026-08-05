import 'package:flutter_test/flutter_test.dart';
import 'package:napaxi_flutter/napaxi_flutter.dart';

import 'support/contract_fixtures.dart';

// contract-fixture: fixtures/project/project_record.json
// contract-fixture: fixtures/project/session_placement.json
void main() {
  test('project contract fixtures decode through public models', () {
    final project = NapaxiProject.fromMap(
      contractFixtureObject('project/project_record.json'),
    );
    final placement = NapaxiSessionPlacement.fromMap(
      contractFixtureObject('project/session_placement.json'),
    );

    expect(project.id, 'project-release');
    expect(placement.projectId, project.id);
    expect(placement.runtimeMatchesProject(project), isTrue);
    expect(placement.revision, 4);
  });
}
