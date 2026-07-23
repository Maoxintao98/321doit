'use strict';

const { app, BrowserWindow, dialog, ipcMain } = require('electron');
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const WorkflowIntegration = require('./WorkflowIntegration.node');

const PLUGIN_ID = 'com.321doit.resolve.workflow';
const MAX_BACKEND_OUTPUT = 16 * 1024 * 1024;

let mainWindow = null;
let initialized = false;
let resolvePromise = null;

async function initializeResolve() {
  if (!initialized) {
    initialized = Boolean(await WorkflowIntegration.InitializePromise(PLUGIN_ID));
  }
  if (!initialized) {
    throw new Error('Resolve Workflow Integration 初始化失败。');
  }
  if (!resolvePromise) {
    resolvePromise = WorkflowIntegration.GetResolvePromise();
  }
  return resolvePromise;
}

function findPython() {
  const candidates = [
    '/opt/homebrew/bin/python3',
    '/usr/local/bin/python3',
    '/usr/bin/python3'
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) || null;
}

function normalizePayload(payload) {
  const source = payload && typeof payload === 'object' ? payload : {};
  const options = source.options && typeof source.options === 'object'
    ? source.options : {};
  return {
    taskPath: String(source.taskPath || '').trim(),
    scriptLogPath: String(source.scriptLogPath || '').trim(),
    preflightToken: String(source.preflightToken || ''),
    options: {
      importOriginals: options.importOriginals !== false,
      writeScriptLogMetadata: options.writeScriptLogMetadata !== false,
      applyStatusColors: options.applyStatusColors !== false,
      applyCircleFlags: options.applyCircleFlags !== false,
      skipAlreadyImported: options.skipAlreadyImported !== false,
      allowPartial: options.allowPartial === true
    }
  };
}

function runBackend(action, rawPayload) {
  const python = findPython();
  if (!python) {
    return Promise.reject(new Error('未找到 Python 3，无法启动 321Doit 后台。'));
  }
  const payload = normalizePayload(rawPayload);
  if (!payload.taskPath) {
    return Promise.reject(new Error('请先选择一个 321Doit 拷卡任务。'));
  }

  const helper = path.join(__dirname, 'backend', 'workflow_cli.py');
  const env = {
    ...process.env,
    PYTHONPATH: [
      path.join(__dirname, 'backend'),
      '/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules'
    ].join(path.delimiter),
    RESOLVE_SCRIPT_API: '/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting',
    RESOLVE_SCRIPT_LIB: '/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so'
  };

  return new Promise((resolve, reject) => {
    const child = spawn(python, [helper, action], {
      env,
      stdio: ['pipe', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';

    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (chunk) => {
      stdout += chunk;
      if (stdout.length > MAX_BACKEND_OUTPUT) child.kill();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk;
      if (stderr.length > MAX_BACKEND_OUTPUT) child.kill();
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(stderr.trim() || `321Doit 后台退出，代码 ${code}`));
        return;
      }
      try {
        const result = JSON.parse(stdout);
        if (!result.ok) {
          reject(new Error(result.error || '321Doit 后台返回未知错误。'));
          return;
        }
        resolve(result);
      } catch (error) {
        reject(new Error(`无法解析 321Doit 后台结果：${error.message}`));
      }
    });
    child.stdin.end(JSON.stringify(payload));
  });
}

async function getContext() {
  const resolve = await initializeResolve();
  const version = await resolve.GetVersionString();
  const projectManager = await resolve.GetProjectManager();
  const project = projectManager ? await projectManager.GetCurrentProject() : null;
  const projectName = project ? await project.GetName() : '';
  return {
    version: String(version || 'unknown'),
    projectName: String(projectName || '')
  };
}

function isChinese(locale) {
  return String(locale || app.getLocale() || '').toLowerCase().startsWith('zh');
}

async function chooseTask(_event, locale) {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: isChinese(locale) ? '选择 321Doit 拷卡任务目录' : 'Choose a 321Doit offload task folder',
    properties: ['openDirectory']
  });
  return result.canceled ? '' : String(result.filePaths[0] || '');
}

async function chooseScriptLog(_event, locale) {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: isChinese(locale) ? '选择场记文件' : 'Choose a script-log file',
    properties: ['openFile'],
    filters: [
      { name: isChinese(locale) ? '321Doit 场记' : '321Doit Script Log', extensions: ['321log'] },
      { name: isChinese(locale) ? '所有文件' : 'All Files', extensions: ['*'] }
    ]
  });
  return result.canceled ? '' : String(result.filePaths[0] || '');
}

async function cleanup() {
  if (initialized) {
    try { WorkflowIntegration.CleanUp(); } catch (_) {}
  }
  initialized = false;
  resolvePromise = null;
}

function registerHandlers() {
  ipcMain.handle('bridge:getContext', getContext);
  ipcMain.handle('bridge:chooseTask', chooseTask);
  ipcMain.handle('bridge:chooseScriptLog', chooseScriptLog);
  ipcMain.handle('bridge:preflight', (_event, payload) => runBackend('preflight', payload));
  ipcMain.handle('bridge:execute', (_event, payload) => runBackend('execute', payload));
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 980,
    height: 760,
    minWidth: 760,
    minHeight: 620,
    useContentSize: true,
    title: '321Doit',
    backgroundColor: '#17181b',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false
    }
  });
  mainWindow.setMenu(null);
  mainWindow.loadFile('index.html');
  mainWindow.once('ready-to-show', () => mainWindow.show());
  mainWindow.on('closed', () => {
    mainWindow = null;
    app.quit();
  });
}

app.whenReady().then(() => {
  registerHandlers();
  createWindow();
  try {
    WorkflowIntegration.RegisterCallback('ResolveQuit', () => app.quit());
  } catch (_) {}
});

app.on('before-quit', () => { cleanup(); });
app.on('window-all-closed', () => app.quit());
app.on('activate', () => {
  if (!mainWindow) createWindow();
});
