const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');

const config = JSON.parse(readFileSync('.github/renovate.json', 'utf8'));

test('approved GitHub Actions automerge only stable minor and patch updates', () => {
  const rules = config.packageRules.filter(
    (rule) => rule.matchManagers?.includes('github-actions')
      && ('automerge' in rule || 'automergeType' in rule),
  );
  assert.equal(rules.length, 1);
  const [rule] = rules;
  assert.deepEqual(rule.matchUpdateTypes, ['minor', 'patch']);
  assert.equal(rule.matchNewValue, '!/-/');
  assert.equal(rule.ignoreUnstable, undefined);
  assert.equal(rule.automerge, true);
  assert.deepEqual(rule.matchPackageNames, [
    'super-linter/super-linter',
    'ShiftLeftSecurity/scan-action',
    'goodwithtech/dockle-action',
    'aquasecurity/trivy-action',
    'anchore/scan-action',
  ]);
});

test('custom calcardbackup application manager has no automerge rule', () => {
  const rules = config.packageRules.filter(
    (rule) => rule.matchManagers?.includes('custom.regex')
      && ('automerge' in rule || 'automergeType' in rule),
  );
  assert.deepEqual(rules, []);
});
