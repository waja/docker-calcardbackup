// Run with: node --test tests/renovate.test.cjs
// These local configuration tests do not perform Renovate datasource lookups.
const assert = require('node:assert/strict');
const { existsSync, readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const root = path.resolve(__dirname, '..');
const config = JSON.parse(
  readFileSync(path.join(root, '.github/renovate.json'), 'utf8'),
);
const managers = config.customManagers.filter(
  (manager) => manager.depNameTemplate === 'BernieO/calcardbackup',
);
assert.equal(managers.length, 1, 'calcardbackup must have one custom manager');
const [manager] = managers;

function extractVersions(content) {
  return manager.matchStrings.flatMap((pattern) =>
    Array.from(content.matchAll(new RegExp(pattern, 'g')), (match) =>
      match.groups?.currentValue,
    ).filter((value) => value !== undefined),
  );
}

function versionDeclarations(content) {
  return content.split(/\r\n|\r|\n/).filter(
    (line) => /^[ \t]*[Ee][Nn][Vv][ \t]+CALCARDBACKUP_VERSION[ \t]+/.test(line),
  );
}

test('calcardbackup uses Codeberg Forgejo tags and coerced semver', () => {
  assert.equal(manager.customType, 'regex');
  assert.equal(manager.datasourceTemplate, 'forgejo-tags');
  assert.equal(manager.registryUrlTemplate, 'https://codeberg.org');
  assert.equal(manager.packageNameTemplate, 'BernieO/calcardbackup');
  assert.equal(manager.versioningTemplate, 'semver-coerced');
});

test('the custom manager targets only the root Dockerfile', () => {
  const patterns = manager.managerFilePatterns.map((pattern) => {
    assert.ok(pattern.startsWith('/') && pattern.endsWith('/'));
    return new RegExp(pattern.slice(1, -1));
  });
  assert.ok(patterns.some((pattern) => pattern.test('Dockerfile')));
  for (const filename of [
    'Dockerfile.dev',
    'nested/Dockerfile',
    'OtherDockerfile',
    'docker-compose-example.yml',
    '.github/workflows/docker.image.yml',
  ]) {
    assert.ok(
      !patterns.some((pattern) => pattern.test(filename)),
      'must not extract dependencies from ' + filename,
    );
  }
});

test('extracts exactly the version used by the real Dockerfile', () => {
  const dockerfile = readFileSync(path.join(root, 'Dockerfile'), 'utf8');
  const declarations = versionDeclarations(dockerfile);
  assert.equal(declarations.length, 1);
  const expected = declarations[0].trim().split(/\s+/)[2];
  assert.match(expected, /^\d+\.\d+\.\d+$/);
  assert.deepEqual(extractVersions(dockerfile), [expected]);
});

test('Dockerfile ENV instruction matching is case-insensitive', () => {
  for (const line of [
    'ENV CALCARDBACKUP_VERSION 11.2.0',
    'env CALCARDBACKUP_VERSION 11.2.0',
    'EnV\tCALCARDBACKUP_VERSION\t11.2.0',
  ]) {
    const declarations = versionDeclarations(line);
    assert.deepEqual(declarations, [line]);
    assert.deepEqual(extractVersions(line), ['11.2.0']);
  }
});

for (const [name, content, expected] of [
  ['ordinary release', 'ENV CALCARDBACKUP_VERSION 11.2.0\n', ['11.2.0']],
  ['tabs', 'ENV CALCARDBACKUP_VERSION\t11.2.0\n', ['11.2.0']],
  ['indented instruction', '  ENV CALCARDBACKUP_VERSION 11.2.0\n', ['11.2.0']],
  ['lowercase instruction', 'env CALCARDBACKUP_VERSION 11.2.0\n', ['11.2.0']],
  ['mixed case instruction', 'eNv CALCARDBACKUP_VERSION 11.2.0\n', ['11.2.0']],
  ['CRLF', 'ENV CALCARDBACKUP_VERSION 11.2.0\r\n', ['11.2.0']],
  ['CR line ending', 'FROM alpine\rENV CALCARDBACKUP_VERSION 11.2.0\r', ['11.2.0']],
  ['end of file', 'ENV CALCARDBACKUP_VERSION 11.2.0', ['11.2.0']],
  ['prerelease', 'ENV CALCARDBACKUP_VERSION 12.0.0-rc.1\n', ['12.0.0-rc.1']],
  ['trailing comment', 'ENV CALCARDBACKUP_VERSION 11.2.0 # release\n', ['11.2.0']],
  ['other variable', 'ENV OTHER_VERSION 11.2.0\n', []],
  ['similar variable', 'ENV CALCARDBACKUP_VERSION_EXTRA 11.2.0\n', []],
  ['missing version', 'ENV CALCARDBACKUP_VERSION \n', []],
  ['commented declaration', '# ENV CALCARDBACKUP_VERSION 99.0.0\n', []],
  ['indented comment', '  # ENV CALCARDBACKUP_VERSION 99.0.0\n', []],
  ['example in another instruction', 'RUN echo ENV CALCARDBACKUP_VERSION 99.0.0\n', []],
  ['empty file', '', []],
]) {
  test('version extraction: ' + name, () => {
    assert.deepEqual(extractVersions(content), expected);
  });
}

test('does not capture adjacent Dockerfile instructions as part of a version', () => {
  assert.deepEqual(
    extractVersions(
      'ENV OTHER_VERSION 99.0.0\nENV CALCARDBACKUP_VERSION 11.2.0\nRUN echo ready\n',
    ),
    ['11.2.0'],
  );
});

test('ignores comments and malformed declarations alongside an active version', () => {
  assert.deepEqual(
    extractVersions(
      '# ENV CALCARDBACKUP_VERSION 99.0.0\nENV CALCARDBACKUP_VERSION \nRUN echo ready\nENV CALCARDBACKUP_VERSION 11.2.0\n',
    ),
    ['11.2.0'],
  );
});

for (const ending of ['\n', '\r\n']) {
  test('ignores continued RUN examples with ' + JSON.stringify(ending), () => {
    const content = [
      'RUN echo example \\',
      '# comment inside continuation',
      '',
      '  ENV CALCARDBACKUP_VERSION 99.0.0',
      'ENV CALCARDBACKUP_VERSION 11.2.0',
    ].join(ending);
    assert.deepEqual(extractVersions(content), ['11.2.0']);
  });
}

test('comment ending with a backslash does not hide an active declaration', () => {
  assert.deepEqual(
    extractVersions('# example \\\nENV CALCARDBACKUP_VERSION 11.2.0\n'),
    ['11.2.0'],
  );
});

for (const [tag, expected] of [
  ['v11.2.0', '11.2.0'],
  ['v12.0.0-rc.1', '12.0.0-rc.1'],
  ['v11.2.0+build.7', '11.2.0+build.7'],
  ['11.2.0', undefined],
  ['V11.2.0', undefined],
  ['release-v11.2.0', undefined],
  ['', undefined],
]) {
  test('upstream tag prefix extraction: ' + JSON.stringify(tag), () => {
    const match = new RegExp(manager.extractVersionTemplate).exec(tag);
    assert.equal(match?.groups?.version, expected);
  });
}

function mayAffectManager(rule, managerName) {
  const names = rule.matchManagers;
  return !Array.isArray(names) || names.length === 0
    || !names.every((name) => /^[a-z][a-z0-9.-]*$/.test(name))
    || names.includes(managerName);
}

function assertDockerfileAutomergePolicy(packageRules) {
  const rules = packageRules.filter(
    (rule) => ('automerge' in rule || 'automergeType' in rule)
      && mayAffectManager(rule, 'dockerfile'),
  );
  assert.equal(rules.length, 2);
  assert.deepEqual(
    rules.flatMap((rule) => rule.matchUpdateTypes).sort(),
    ['digest', 'patch'],
  );
  for (const rule of rules) {
    assert.deepEqual(rule.matchManagers, ['dockerfile']);
    assert.equal(rule.automerge, true);
    assert.equal(rule.automergeType, 'pr');
  }
  const patch = rules.find((rule) => rule.matchUpdateTypes.includes('patch'));
  assert.equal(patch.matchCurrentVersion, '!/^0/');
}

test('Dockerfile automerge remains limited to patch and digest updates', () => {
  assert.notEqual(config.automerge, true);
  assertDockerfileAutomergePolicy(config.packageRules);
});

test('rejects broad automerge rules affecting Dockerfile updates', () => {
  const broad = { automerge: true, matchUpdateTypes: ['major'] };
  assert.throws(
    () => assertDockerfileAutomergePolicy([...config.packageRules, broad]),
    assert.AssertionError,
  );
});

test('calcardbackup application-version updates require review', () => {
  const rules = config.packageRules.filter(
    (rule) => ('automerge' in rule || 'automergeType' in rule)
      && mayAffectManager(rule, 'custom.regex'),
  );
  assert.deepEqual(rules, []);
});

const approvedActions = [
  'super-linter/super-linter',
  'ShiftLeftSecurity/scan-action',
  'goodwithtech/dockle-action',
  'aquasecurity/trivy-action',
  'anchore/scan-action',
];

test('GitHub Actions automerge is restricted to the reviewed allowlist', () => {
  const rules = config.packageRules.filter(
    (rule) => rule.matchManagers?.includes('github-actions')
      && ('automerge' in rule || 'automergeType' in rule),
  );
  assert.equal(rules.length, 1);
  assert.deepEqual(rules[0].matchFileNames, ['.github/workflows/**']);
  assert.deepEqual(rules[0].matchManagers, ['github-actions']);
  assert.deepEqual(rules[0].matchPackageNames, approvedActions);
  assert.equal(rules[0].automerge, true);
  assert.equal(rules[0].automergeType, 'pr');
});

test('workflow action references are SHA-pinned and version-labelled', () => {
  const workflow = readFileSync(
    path.join(root, '.github/workflows/docker.image.yml'),
    'utf8',
  );
  const uses = workflow.split(/\r?\n/).filter((line) => /^\s*-?\s*uses:/.test(line));
  assert.ok(uses.length > 0);
  for (const line of uses) {
    assert.match(
      line,
      /uses:\s+[^@\s]+@[0-9a-f]{40}\s+# v\d+\.\d+\.\d+\s*$/,
      'invalid action reference: ' + line,
    );
  }
});

test('image builds do not depend on SARIF upload permissions', () => {
  const workflow = readFileSync(
    path.join(root, '.github/workflows/docker.image.yml'),
    'utf8',
  );
  const build = workflow.match(
    /^ {2}test-build:\n([\s\S]*?)(?=^ {2}[a-z][a-z-]*:)/m,
  )?.[1];
  assert.ok(build, 'test-build job must exist');
  const needs = build.match(/ {4}needs:\n((?: {6}- [^\n]+\n)+)/)?.[1];
  assert.ok(needs, 'build prerequisites must exist');
  assert.deepEqual(
    Array.from(needs.matchAll(/ {6}- ([^\n]+)/g), (match) => match[1]).sort(),
    ['renovate-policy-tests', 'renovate-tests', 'shiftleft', 'super-linter'],
  );
});

test('Dependabot remains configured alongside Renovate', () => {
  const dependabot = path.join(root, '.github/dependabot.yml');
  assert.equal(existsSync(dependabot), true);
  const content = readFileSync(dependabot, 'utf8');
  assert.match(content, /package-ecosystem:\s*github-actions/);
  assert.match(content, /package-ecosystem:\s*docker/);
});
