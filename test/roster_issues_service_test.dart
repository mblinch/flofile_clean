import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/services/roster_issues_service.dart';

void main() {
  test('RosterIssue labels missing jersey clearly', () {
    const issue = RosterIssue(
      kind: RosterIssueKind.missingJersey,
      sportId: 'baseball',
      teamId: 'NYY',
      teamName: 'New York Yankees',
      playerDocId: '123',
      fullName: 'Jane Doe',
      position: 'P',
    );
    expect(issue.kindLabel, 'Missing jersey');
    expect(issue.label, 'Jane Doe · P');
  });

  test('RosterIssue labels duplicate jersey with number', () {
    const issue = RosterIssue(
      kind: RosterIssueKind.duplicateJersey,
      sportId: 'hockey',
      teamId: 'TOR',
      teamName: 'Toronto Maple Leafs',
      playerDocId: '456',
      fullName: 'Auston Matthews',
      jerseyNumber: '34',
      detail: 'Also worn by Example Player',
    );
    expect(issue.kindLabel, 'Duplicate #34');
    expect(issue.detail, contains('Example Player'));
  });
}
