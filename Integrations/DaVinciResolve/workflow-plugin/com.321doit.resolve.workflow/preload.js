'use strict';

const { contextBridge, ipcRenderer } = require('electron/renderer');

contextBridge.exposeInMainWorld('bridgeAPI', {
  getContext: () => ipcRenderer.invoke('bridge:getContext'),
  chooseTask: (locale) => ipcRenderer.invoke('bridge:chooseTask', locale),
  chooseScriptLog: (locale) => ipcRenderer.invoke('bridge:chooseScriptLog', locale),
  preflight: (payload) => ipcRenderer.invoke('bridge:preflight', payload),
  execute: (payload) => ipcRenderer.invoke('bridge:execute', payload)
});
