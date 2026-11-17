#!/usr/bin/env node
// `npm run lint` 的垫片：本项目是 Flutter(Dart) + Python，没有 ESLint。
//
// 为什么需要它：claude-scene 的 review 步骤会用 `npm run lint [-- --fix]` 跑项目自检，
// 而 flutter analyze 不认识 `--fix`（会直接报 "Could not find an option named --fix"，
// 于是被判定成「审查跳过」或误报）。这里丢掉多余参数，只跑真正的静态检查。
//
// 用法：npm run lint  /  npm run lint -- --fix（多余参数忽略）

const { spawnSync } = require('node:child_process');
const path = require('node:path');

const frontend = path.join(__dirname, '..', 'frontend');
const r = spawnSync('flutter', ['analyze', 'lib/', 'test/'], {
  cwd: frontend,
  stdio: 'inherit',
  shell: true,
});

if (r.error) {
  console.error(`无法执行 flutter analyze：${r.error.message}`);
  process.exit(1);
}
process.exit(r.status === null ? 1 : r.status);
