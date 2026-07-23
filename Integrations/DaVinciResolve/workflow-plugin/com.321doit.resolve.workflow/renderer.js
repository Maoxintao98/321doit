'use strict';

const state = {
  preflightToken: '',
  busy: false,
  locale: localStorage.getItem('321doit.locale') ||
    (navigator.language.toLowerCase().startsWith('zh') ? 'zh-CN' : 'en'),
  statusKey: 'waiting'
};

const $ = (id) => document.getElementById(id);

const messages = {
  'zh-CN': {
    subtitle: '拷卡与场记衔接', notConnected: '未连接项目', noProject: '未打开项目',
    resolveFailed: 'Resolve 连接失败', sourceEyebrow: '01 / 来源',
    sourceTitle: '选择已完成的拷卡任务', safeNote: '选择文件不会修改项目',
    chooseTask: '选择任务', taskLabel: '任务目录或 task.json',
    taskPlaceholder: '选择包含 .321doit/task.json 的任务目录', chooseLog: '选择场记',
    logLabel: '场记文件（可选）', logPlaceholder: '留空时自动查找 .321log',
    optionsEyebrow: '02 / 规则', optionsTitle: '导入选项', importOriginals: '导入原始素材',
    writeMetadata: '写入场记元数据', applyColors: '应用状态颜色', applyFlags: '标记优选条',
    skipDuplicates: '跳过已导入素材', allowPartial: '允许只导入已验证部分',
    resultEyebrow: '03 / 核对', resultTitle: '预检结果', waiting: '等待预检',
    files: '素材', verified: '已验证', missing: '缺失', matched: '场记匹配',
    conflicts: '冲突', duplicates: '重复',
    initialLog: '选择任务后运行预检。执行导入前不会更改 Resolve 项目。',
    runPreflight: '运行预检', executeImport: '执行导入', busyPreflight: '正在读取任务并核对 Resolve 媒体池…',
    busyImport: '正在导入素材并写入元数据…', actionFailed: '操作失败',
    error: '[错误] {value}', reminder: '[提醒] {value}', blocker: '[阻断] {value}',
    missingLine: '[缺失] {count} 个已验证素材无法在磁盘定位',
    preflightPassedLine: '预检通过，可以执行导入。', blocked: '已阻断',
    executableWarning: '可执行，有提醒', preflightPassed: '预检通过',
    importStatus: '导入状态：{status}', importCounts: '已导入 {imported}，跳过重复 {skipped}',
    resultPath: '结果记录：{path}', importDone: '导入完成', partial: '部分完成',
    importFailed: '导入失败'
  },
  en: {
    subtitle: 'Offload and script-log bridge', notConnected: 'No project connection', noProject: 'No project open',
    resolveFailed: 'Resolve connection failed', sourceEyebrow: '01 / SOURCE',
    sourceTitle: 'Select a completed offload task', safeNote: 'Selecting files does not modify the project',
    chooseTask: 'Choose Task', taskLabel: 'Task folder or task.json',
    taskPlaceholder: 'Choose a task folder containing .321doit/task.json', chooseLog: 'Choose Log',
    logLabel: 'Script log (optional)', logPlaceholder: 'Leave empty to find a .321log automatically',
    optionsEyebrow: '02 / RULES', optionsTitle: 'Import options', importOriginals: 'Import original media',
    writeMetadata: 'Write script-log metadata', applyColors: 'Apply status colors', applyFlags: 'Flag circle takes',
    skipDuplicates: 'Skip existing media', allowPartial: 'Allow verified portion only',
    resultEyebrow: '03 / REVIEW', resultTitle: 'Preflight result', waiting: 'Waiting for preflight',
    files: 'Media', verified: 'Verified', missing: 'Missing', matched: 'Log matches',
    conflicts: 'Conflicts', duplicates: 'Duplicates',
    initialLog: 'Choose a task and run preflight. Resolve is not modified before import.',
    runPreflight: 'Run Preflight', executeImport: 'Execute Import', busyPreflight: 'Reading task and checking the Resolve media pool…',
    busyImport: 'Importing media and writing metadata…', actionFailed: 'Operation failed',
    error: '[Error] {value}', reminder: '[Notice] {value}', blocker: '[Blocked] {value}',
    missingLine: '[Missing] {count} verified media files could not be located',
    preflightPassedLine: 'Preflight passed. Import can proceed.', blocked: 'Blocked',
    executableWarning: 'Ready with notices', preflightPassed: 'Preflight passed',
    importStatus: 'Import status: {status}', importCounts: 'Imported {imported}; skipped {skipped} duplicates',
    resultPath: 'Result record: {path}', importDone: 'Import complete', partial: 'Partially complete',
    importFailed: 'Import failed'
  }
};

function t(key, vars = {}) {
  const table = messages[state.locale] || messages.en;
  let text = table[key] || messages.en[key] || key;
  for (const [name, value] of Object.entries(vars)) {
    text = text.replace(`{${name}}`, String(value));
  }
  return text;
}

function applyLocale() {
  document.documentElement.lang = state.locale;
  for (const element of document.querySelectorAll('[data-i18n]')) {
    element.textContent = t(element.dataset.i18n);
  }
  for (const element of document.querySelectorAll('[data-i18n-placeholder]')) {
    element.placeholder = t(element.dataset.i18nPlaceholder);
  }
  $('language-toggle').textContent = state.locale === 'zh-CN' ? 'EN' : '中文';
  $('language-toggle').setAttribute('aria-label',
    state.locale === 'zh-CN' ? 'Switch to English' : '切换到中文');
  $('status-badge').textContent = t(state.statusKey);
}

function setStatus(key, className) {
  state.statusKey = key;
  $('status-badge').className = `status ${className}`;
  $('status-badge').textContent = t(key);
}

function options() {
  return {
    importOriginals: $('import-originals').checked,
    writeScriptLogMetadata: $('write-metadata').checked,
    applyStatusColors: $('apply-colors').checked,
    applyCircleFlags: $('apply-flags').checked,
    skipAlreadyImported: $('skip-duplicates').checked,
    allowPartial: $('allow-partial').checked
  };
}

function payload() {
  return {
    taskPath: $('task-path').value.trim(),
    scriptLogPath: $('log-path').value.trim(),
    preflightToken: state.preflightToken,
    options: options()
  };
}

function invalidate() {
  state.preflightToken = '';
  $('execute').disabled = true;
  setStatus('waiting', 'neutral');
}

function setBusy(busy, label = '') {
  state.busy = busy;
  $('choose-task').disabled = busy;
  $('choose-log').disabled = busy;
  $('preflight').disabled = busy;
  $('execute').disabled = busy || !state.preflightToken;
  $('busy-label').textContent = busy ? label : '';
}

function setLog(lines) {
  const list = Array.isArray(lines) ? lines : [String(lines || '')];
  $('activity-log').textContent = list.filter(Boolean).join('\n');
}

function updateCounts(counts = {}) {
  const mapping = {
    'metric-files': 'discovered',
    'metric-verified': 'verified',
    'metric-missing': 'missing',
    'metric-matched': 'metadataMatched',
    'metric-conflicts': 'metadataConflicts',
    'metric-duplicates': 'skippedDuplicate'
  };
  for (const [element, key] of Object.entries(mapping)) {
    $(element).textContent = Number.isFinite(counts[key]) ? String(counts[key]) : '0';
  }
}

function showError(error) {
  state.preflightToken = '';
  $('execute').disabled = true;
  setStatus('actionFailed', 'error');
  setLog([t('error', { value: error && error.message ? error.message : error })]);
}

async function refreshContext() {
  try {
    const context = await window.bridgeAPI.getContext();
    $('resolve-version').textContent = `Resolve ${context.version || '—'}`;
    $('project-name').textContent = context.projectName || t('noProject');
  } catch (error) {
    $('project-name').textContent = t('resolveFailed');
    showError(error);
  }
}

async function chooseTask() {
  const selected = await window.bridgeAPI.chooseTask(state.locale);
  if (selected) {
    $('task-path').value = selected;
    invalidate();
  }
}

async function chooseLog() {
  const selected = await window.bridgeAPI.chooseScriptLog(state.locale);
  if (selected) {
    $('log-path').value = selected;
    invalidate();
  }
}

async function preflight() {
  setBusy(true, t('busyPreflight'));
  try {
    const result = await window.bridgeAPI.preflight(payload());
    state.preflightToken = result.preflightToken || '';
    if (result.scriptLogPath) $('log-path').value = result.scriptLogPath;
    if (result.projectName) $('project-name').textContent = result.projectName;
    updateCounts(result.counts);
    const messages = [];
    for (const item of result.warnings || []) messages.push(t('reminder', { value: item }));
    for (const item of result.errors || []) messages.push(t('blocker', { value: item }));
    if (result.missing && result.missing.length) {
      messages.push(t('missingLine', { count: result.missing.length }));
    }
    if (!messages.length) messages.push(t('preflightPassedLine'));
    setLog(messages);
    setStatus(result.blocking ? 'blocked' :
      ((result.warnings || []).length ? 'executableWarning' : 'preflightPassed'),
    result.blocking ? 'error' : ((result.warnings || []).length ? 'warn' : 'ok'));
    if (result.blocking) state.preflightToken = '';
  } catch (error) {
    showError(error);
  } finally {
    setBusy(false);
  }
}

async function executeImport() {
  if (!state.preflightToken) return;
  setBusy(true, t('busyImport'));
  try {
    const response = await window.bridgeAPI.execute(payload());
    const result = response.result || {};
    const counts = result.counts || {};
    updateCounts(counts);
    const messages = [
      t('importStatus', { status: result.status || 'unknown' }),
      t('importCounts', { imported: counts.imported || 0, skipped: counts.skippedDuplicate || 0 })
    ];
    for (const item of result.warnings || []) messages.push(t('reminder', { value: item }));
    for (const item of result.errors || []) messages.push(t('error', { value: item }));
    if (response.resultPath) messages.push(t('resultPath', { path: response.resultPath }));
    setLog(messages);
    const ok = result.status === 'success';
    setStatus(ok ? 'importDone' : (result.status === 'partial' ? 'partial' : 'importFailed'),
      ok ? 'ok' : (result.status === 'partial' ? 'warn' : 'error'));
    state.preflightToken = '';
    await refreshContext();
  } catch (error) {
    showError(error);
  } finally {
    setBusy(false);
  }
}

window.addEventListener('DOMContentLoaded', () => {
  applyLocale();
  $('choose-task').addEventListener('click', chooseTask);
  $('choose-log').addEventListener('click', chooseLog);
  $('preflight').addEventListener('click', preflight);
  $('execute').addEventListener('click', executeImport);
  $('language-toggle').addEventListener('click', () => {
    state.locale = state.locale === 'zh-CN' ? 'en' : 'zh-CN';
    localStorage.setItem('321doit.locale', state.locale);
    applyLocale();
  });

  for (const id of ['task-path', 'log-path']) {
    $(id).addEventListener('input', invalidate);
  }
  for (const id of [
    'import-originals', 'write-metadata', 'apply-colors',
    'apply-flags', 'skip-duplicates', 'allow-partial'
  ]) {
    $(id).addEventListener('change', invalidate);
  }
  refreshContext();
});
